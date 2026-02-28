#' Create an ellmer tool definition for Perplexica search
#'
#' Returns a `ToolDef` object (from the `ellmer` package) that wraps
#' [perplexica_search()]. Register it with an `ellmer` chat object to give an
#' LLM the ability to search the web autonomously via Perplexica.
#'
#' The `ellmer` package must be installed (`install.packages("ellmer")`).
#'
#' @param mode Optimisation mode passed to [perplexica_search()].
#'   `"speed"` (default) or `"balanced"`.
#' @param base_url Base URL of the Perplexica instance.
#' @return An `ellmer` `ToolDef` object.
#' @export
#' @examples
#' \dontrun{
#' library(ellmer)
#'
#' chat <- chat_openai(
#'   model = "gpt-4.1",
#'   system_prompt = "You are a helpful assistant with access to live web search."
#' )
#'
#' chat$register_tool(perplexica_tool())
#'
#' chat$chat("Who won the most recent FIFA World Cup?")
#' }
perplexica_tool <- function(mode = "speed", base_url = perplexica_get_url()) {
  if (!requireNamespace("ellmer", quietly = TRUE)) {
    stop(
      "Package 'ellmer' is required for perplexica_tool().\n",
      "Install with: install.packages(\"ellmer\")"
    )
  }

  ellmer::tool(
    fun = function(query) {
      res <- perplexica_search_with_retry(query, mode = mode, base_url = base_url)
      if (length(res$sources) > 0L) {
        paste0(res$message, "\n\nSources:\n", paste0("- ", res$sources, collapse = "\n"))
      } else {
        res$message
      }
    },
    description = paste(
      "Search the web using Perplexica, a self-hosted AI-powered search engine.",
      "Returns a synthesised, source-backed answer to the query.",
      "Use this tool whenever current or factual information is needed.",
      "Be specific and include all relevant context in the query."
    ),
    arguments = list(
      query = ellmer::type_string(
        "The search query. Be specific and include all relevant context."
      )
    ),
    name = "perplexica_search",
    annotations = ellmer::tool_annotations(
      read_only_hint  = TRUE,
      open_world_hint = TRUE
    )
  )
}

#' Search first, then ask an LLM (pre-fetch / RAG pattern)
#'
#' Searches Perplexica for `query`, injects the result as grounding context into
#' the prompt, and calls `chat$chat()`. Because the search result is embedded
#' directly in the message, the LLM is **guaranteed** to reason over live web
#' information — no tool-calling decision is involved.
#'
#' Use this instead of [perplexica_tool()] when every query is a factual
#' lookup and you need a hard guarantee that Perplexica is always consulted.
#' For a general-purpose assistant that searches only when needed, register
#' [perplexica_tool()] and add a system-prompt directive such as
#' `"Always call perplexica_search before answering. Never rely on prior knowledge alone."`
#'
#' @param query A character string — the user's question.
#' @param chat An `ellmer` chat object (e.g. from `ellmer::chat_openai()`).
#' @param mode Optimisation mode passed to [perplexica_search_with_retry()].
#'   `"speed"` (default) or `"balanced"`.
#' @param base_url Base URL of the Perplexica instance.
#' @param verbose If `TRUE`, prints the query sent to Perplexica. Passed to
#'   [perplexica_search_with_retry()]. Default `FALSE`.
#' @return The LLM's response string (whatever `chat$chat()` returns).
#' @export
#' @examples
#' \dontrun{
#' library(ellmer)
#'
#' chat <- chat_openai(
#'   model = "gpt-4.1",
#'   system_prompt = "You are a helpful assistant with access to live web search."
#' )
#'
#' perplexica_ask("Who won the most recent FIFA World Cup?", chat = chat)
#' }
perplexica_ask <- function(
    query,
    chat,
    mode     = "speed",
    base_url = perplexica_get_url(),
    verbose  = FALSE) {

  res <- perplexica_search_with_retry(query, mode = mode, base_url = base_url, verbose = verbose)

  context <- res$message
  if (length(res$sources) > 0L) {
    context <- paste0(
      context,
      "\n\nSources:\n",
      paste0("- ", res$sources, collapse = "\n")
    )
  }

  augmented <- paste0(
    "Answer the following question using only the search results provided below. ",
    "Do not rely on prior knowledge.\n\n",
    "Question: ", query, "\n\n",
    "Search results:\n", context
  )

  chat$chat(augmented)
}
