#' Search the web using Perplexica
#'
#' Sends a single query to the Perplexica `/api/search` endpoint and returns
#' the synthesised answer as a named list.
#'
#' @param query A character string containing the search query.
#' @param mode Optimisation mode: `"speed"` (default) or `"balanced"`.
#' @param base_url Base URL of the Perplexica instance.
#' @param verbose If `TRUE`, prints the query sent to Perplexica before each
#'   request. Default `FALSE`.
#' @return A list with elements `message` (the synthesised answer string) and
#'   `sources` (a character vector of source URLs).
#' @export
#' @examples
#' \dontrun{
#' perplexica_search("What is the current population of Tokyo?")
#' perplexica_search("What is the current population of Tokyo?", verbose = TRUE)
#' }
perplexica_search <- function(
    query,
    mode     = "speed",
    base_url = perplexica_get_url(),
    verbose  = FALSE) {

  if (verbose) message("Querying Perplexica: ", query)

  models <- perplexica_default_models(perplexica_providers(base_url))

  body <- list(
    chatModel      = models$chatModel,
    embeddingModel = models$embeddingModel,
    optimizationMode = mode,
    sources        = list("web"),
    query          = query,
    stream         = FALSE
  )

  resp <- httr2::request(base_url) |>
    httr2::req_url_path_append("api", "search") |>
    httr2::req_body_json(body) |>
    httr2::req_perform()

  parsed <- httr2::resp_body_json(resp)
  sources <- vapply(
    parsed$sources %||% list(),
    \(s) s$metadata$url %||% "",
    character(1L)
  )
  list(message = parsed$message %||% "", sources = sources[nchar(sources) > 0])
}

#' Search with automatic retry on empty responses
#'
#' Wraps [perplexica_search()] and retries up to `max_retries` times when the
#' returned message is empty or an error occurs. Waits `5 * attempt` seconds
#' between attempts to avoid hammering the API.
#'
#' @param query A character string containing the search query.
#' @param max_retries Maximum number of additional attempts after the first.
#' @param mode Optimisation mode passed to [perplexica_search()].
#' @param base_url Base URL of the Perplexica instance.
#' @param verbose If `TRUE`, prints the query and any retry attempts. Passed to
#'   [perplexica_search()]. Default `FALSE`.
#' @return A list with elements `message` and `sources` (see [perplexica_search()]).
#' @export
#' @examples
#' \dontrun{
#' perplexica_search_with_retry("Latest R release version", max_retries = 3)
#' perplexica_search_with_retry("Latest R release version", max_retries = 3, verbose = TRUE)
#' }
perplexica_search_with_retry <- function(
    query,
    max_retries = 2L,
    mode        = "speed",
    base_url    = perplexica_get_url(),
    verbose     = FALSE) {

  for (attempt in seq_len(max_retries + 1L)) {
    if (verbose && attempt > 1L) message("  Retrying (attempt ", attempt, "/", max_retries + 1L, ")")
    res <- tryCatch(
      perplexica_search(query, mode = mode, base_url = base_url, verbose = verbose && attempt == 1L),
      error = function(e) list(message = "")
    )
    if (nchar(res$message %||% "") > 0 || attempt > max_retries) return(res)
    Sys.sleep(5 * attempt)
  }
  res
}

#' Batch search over a vector of queries
#'
#' Runs [perplexica_search_with_retry()] for each element of `queries`,
#' printing progress and saving periodic checkpoints so a crashed session can
#' be resumed.
#'
#' @param queries A character vector of search queries.
#' @param delay Seconds to sleep between requests. Default `2`.
#' @param checkpoint_every Write a checkpoint file every this many rows.
#'   Set to `Inf` to disable.
#' @param checkpoint_file Path to the CSV checkpoint file. Required when
#'   `checkpoint_every` is finite.
#' @param resume_from Integer row to resume from. Rows before this index are
#'   read from `checkpoint_file`.
#' @param max_retries Passed to [perplexica_search_with_retry()].
#' @param mode Optimisation mode passed to [perplexica_search()].
#' @param base_url Base URL of the Perplexica instance.
#' @param verbose If `TRUE`, prints each query and any retry attempts. Passed to
#'   [perplexica_search_with_retry()]. Default `FALSE`.
#' @return A data frame with columns `query` and `message`.
#' @export
#' @examples
#' \dontrun{
#' queries <- c(
#'   "Current GDP of Brazil",
#'   "Population of Nigeria 2025",
#'   "Largest sovereign wealth funds by assets"
#' )
#' results <- perplexica_search_many(
#'   queries,
#'   checkpoint_file = "checkpoint.csv",
#'   checkpoint_every = 2
#' )
#'
#' # Resume after a crash at row 2:
#' results <- perplexica_search_many(
#'   queries,
#'   checkpoint_file = "checkpoint.csv",
#'   resume_from = 2
#' )
#' }
perplexica_search_many <- function(
    queries,
    delay            = 2,
    checkpoint_every = 25L,
    checkpoint_file  = NULL,
    resume_from      = NULL,
    max_retries      = 2L,
    mode             = "speed",
    base_url         = perplexica_get_url(),
    verbose          = FALSE) {

  queries <- as.character(queries)
  n       <- length(queries)
  results <- vector("list", n)

  start_from <- 1L

  if (!is.null(resume_from)) {
    start_from <- as.integer(resume_from)
    if (!is.null(checkpoint_file) && file.exists(checkpoint_file)) {
      prev <- utils::read.csv(checkpoint_file, stringsAsFactors = FALSE)
      for (i in seq_len(min(start_from - 1L, nrow(prev)))) {
        results[[i]] <- prev[i, , drop = FALSE]
      }
      message("Resuming from row ", start_from,
              " (loaded ", start_from - 1L, " rows from checkpoint)")
    }
  }

  for (i in seq(start_from, n)) {
    res <- perplexica_search_with_retry(
      queries[[i]],
      max_retries = max_retries,
      mode        = mode,
      base_url    = base_url,
      verbose     = verbose
    )
    results[[i]] <- data.frame(
      query   = queries[[i]],
      message = res$message,
      stringsAsFactors = FALSE
    )

    message("[", i, "/", n, "] ", strtrim(queries[[i]], 60))

    if (is.finite(checkpoint_every) && i %% checkpoint_every == 0L) {
      if (is.null(checkpoint_file)) {
        warning("checkpoint_every set but no checkpoint_file provided; skipping save.")
      } else {
        completed <- do.call(rbind, results[!vapply(results, is.null, logical(1L))])
        utils::write.csv(completed, checkpoint_file, row.names = FALSE)
        message("  Checkpoint saved (", i, "/", n, ") -> ", checkpoint_file)
      }
    }

    if (i < n) Sys.sleep(delay)
  }

  do.call(rbind, results)
}
