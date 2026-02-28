# Helpers ----------------------------------------------------------------------

json_resp <- function(body, status_code = 200L) {
  httr2::response(
    status_code = status_code,
    headers     = list("content-type" = "application/json"),
    body        = charToRaw(body)
  )
}

providers_json <- paste0(
  '{"providers":[{"id":"openai",',
  '"chatModels":[{"key":"gpt-4o-mini"}],',
  '"embeddingModels":[{"key":"text-embedding-3-small"}]}]}'
)

search_json <- paste0(
  '{"message":"Paris is the capital of France.",',
  '"sources":[{"metadata":{"url":"https://example.com","title":"Example"}}]}'
)

search_empty_json <- '{"message":"","sources":[]}'

mock_ok <- function(req) {
  if (grepl("providers", req$url)) json_resp(providers_json)
  else                             json_resp(search_json)
}

mock_empty <- function(req) {
  if (grepl("providers", req$url)) json_resp(providers_json)
  else                             json_resp(search_empty_json)
}

# perplexica_search() ----------------------------------------------------------

test_that("perplexica_search() returns a named list with message and sources", {
  withr::local_options(list(perplexica.base_url = "http://localhost:3000"))
  httr2::local_mocked_responses(mock_ok)

  res <- perplexica_search("What is the capital of France?")

  expect_type(res, "list")
  expect_named(res, c("message", "sources"))
  expect_equal(res$message, "Paris is the capital of France.")
  expect_equal(res$sources, "https://example.com")
})

test_that("perplexica_search() returns an empty character vector when sources are absent", {
  withr::local_options(list(perplexica.base_url = "http://localhost:3000"))
  httr2::local_mocked_responses(function(req) {
    if (grepl("providers", req$url)) json_resp(providers_json)
    else json_resp('{"message":"Answer with no sources.","sources":[]}')
  })

  res <- perplexica_search("test query")
  expect_length(res$sources, 0L)
})

test_that("perplexica_search() filters out sources with empty URLs", {
  withr::local_options(list(perplexica.base_url = "http://localhost:3000"))
  httr2::local_mocked_responses(function(req) {
    if (grepl("providers", req$url)) return(json_resp(providers_json))
    json_resp(paste0(
      '{"message":"Answer.",',
      '"sources":[',
      '{"metadata":{"url":"","title":"Empty"}},',
      '{"metadata":{"url":"https://good.com","title":"Good"}}',
      ']}'
    ))
  })

  res <- perplexica_search("test query")
  expect_equal(res$sources, "https://good.com")
})

test_that("perplexica_search() with verbose = TRUE emits the query as a message", {
  withr::local_options(list(perplexica.base_url = "http://localhost:3000"))
  httr2::local_mocked_responses(mock_ok)

  expect_message(
    perplexica_search("capital of France?", verbose = TRUE),
    "Querying Perplexica: capital of France?"
  )
})

test_that("perplexica_search() with verbose = FALSE emits no messages", {
  withr::local_options(list(perplexica.base_url = "http://localhost:3000"))
  httr2::local_mocked_responses(mock_ok)

  expect_no_message(perplexica_search("test query", verbose = FALSE))
})

# perplexica_search_with_retry() -----------------------------------------------

test_that("perplexica_search_with_retry() returns immediately when first call succeeds", {
  withr::local_options(list(perplexica.base_url = "http://localhost:3000"))
  httr2::local_mocked_responses(mock_ok)

  res <- perplexica_search_with_retry("test query", max_retries = 2L)
  expect_equal(res$message, "Paris is the capital of France.")
})

test_that("perplexica_search_with_retry() retries on empty message and returns second result", {
  withr::local_options(list(perplexica.base_url = "http://localhost:3000"))
  search_calls <- 0L
  httr2::local_mocked_responses(function(req) {
    if (grepl("providers", req$url)) return(json_resp(providers_json))
    search_calls <<- search_calls + 1L
    if (search_calls == 1L) json_resp(search_empty_json) else json_resp(search_json)
  })
  local_mocked_bindings(Sys.sleep = function(time) invisible(NULL), .package = "base")

  res <- perplexica_search_with_retry("test query", max_retries = 1L)
  expect_equal(res$message, "Paris is the capital of France.")
  expect_equal(search_calls, 2L)
})

test_that("perplexica_search_with_retry() returns empty message after exhausting all retries", {
  withr::local_options(list(perplexica.base_url = "http://localhost:3000"))
  httr2::local_mocked_responses(mock_empty)
  local_mocked_bindings(Sys.sleep = function(time) invisible(NULL), .package = "base")

  res <- perplexica_search_with_retry("test query", max_retries = 1L)
  expect_equal(res$message, "")
})

test_that("perplexica_search_with_retry() treats API errors as empty responses", {
  withr::local_options(list(perplexica.base_url = "http://localhost:3000"))
  httr2::local_mocked_responses(function(req) {
    if (grepl("providers", req$url)) return(json_resp(providers_json))
    stop("connection refused")
  })
  local_mocked_bindings(Sys.sleep = function(time) invisible(NULL), .package = "base")

  res <- perplexica_search_with_retry("test query", max_retries = 0L)
  expect_equal(res$message, "")
})

test_that("perplexica_search_with_retry() verbose = TRUE emits retry messages", {
  withr::local_options(list(perplexica.base_url = "http://localhost:3000"))
  search_calls <- 0L
  httr2::local_mocked_responses(function(req) {
    if (grepl("providers", req$url)) return(json_resp(providers_json))
    search_calls <<- search_calls + 1L
    if (search_calls == 1L) json_resp(search_empty_json) else json_resp(search_json)
  })
  local_mocked_bindings(Sys.sleep = function(time) invisible(NULL), .package = "base")

  expect_message(
    perplexica_search_with_retry("test query", max_retries = 1L, verbose = TRUE),
    "Retrying"
  )
})

# perplexica_search_many() -----------------------------------------------------

test_that("perplexica_search_many() returns a data frame with columns query and message", {
  withr::local_options(list(perplexica.base_url = "http://localhost:3000"))
  httr2::local_mocked_responses(mock_ok)
  local_mocked_bindings(Sys.sleep = function(time) invisible(NULL), .package = "base")

  res <- perplexica_search_many(c("q1", "q2"), delay = 0)

  expect_s3_class(res, "data.frame")
  expect_named(res, c("query", "message"))
  expect_equal(nrow(res), 2L)
  expect_equal(res$query,   c("q1", "q2"))
  expect_equal(res$message, c("Paris is the capital of France.",
                              "Paris is the capital of France."))
})

test_that("perplexica_search_many() warns when checkpoint_every set without checkpoint_file", {
  withr::local_options(list(perplexica.base_url = "http://localhost:3000"))
  httr2::local_mocked_responses(mock_ok)
  local_mocked_bindings(Sys.sleep = function(time) invisible(NULL), .package = "base")

  expect_warning(
    perplexica_search_many(c("q1", "q2"), delay = 0, checkpoint_every = 1L),
    "no checkpoint_file"
  )
})

test_that("perplexica_search_many() loads completed rows from checkpoint and skips them", {
  withr::local_options(list(perplexica.base_url = "http://localhost:3000"))
  httr2::local_mocked_responses(mock_ok)
  local_mocked_bindings(Sys.sleep = function(time) invisible(NULL), .package = "base")

  tmp <- tempfile(fileext = ".csv")
  on.exit(unlink(tmp), add = TRUE)
  utils::write.csv(
    data.frame(query = "q1", message = "cached answer", stringsAsFactors = FALSE),
    tmp, row.names = FALSE
  )

  res <- perplexica_search_many(
    c("q1", "q2"),
    checkpoint_file = tmp,
    resume_from     = 2L,
    delay           = 0
  )

  expect_equal(nrow(res), 2L)
  expect_equal(res$message[[1L]], "cached answer")
  expect_equal(res$message[[2L]], "Paris is the capital of France.")
})

test_that("perplexica_search_many() writes a checkpoint file at the right interval", {
  withr::local_options(list(perplexica.base_url = "http://localhost:3000"))
  httr2::local_mocked_responses(mock_ok)
  local_mocked_bindings(Sys.sleep = function(time) invisible(NULL), .package = "base")

  tmp <- tempfile(fileext = ".csv")
  on.exit(unlink(tmp), add = TRUE)

  perplexica_search_many(
    c("q1", "q2"),
    delay            = 0,
    checkpoint_every = 2L,
    checkpoint_file  = tmp
  )

  expect_true(file.exists(tmp))
  saved <- utils::read.csv(tmp, stringsAsFactors = FALSE)
  expect_equal(nrow(saved), 2L)
})
