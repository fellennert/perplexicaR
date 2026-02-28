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

mock_api <- function(req) {
  if (grepl("providers", req$url)) {
    json_resp(providers_json)
  } else {
    json_resp(paste0(
      '{"message":"Paris is the capital of France.",',
      '"sources":[{"metadata":{"url":"https://example.com","title":"Ex"}}]}'
    ))
  }
}

mock_api_no_sources <- function(req) {
  if (grepl("providers", req$url)) json_resp(providers_json)
  else json_resp('{"message":"An answer with no sources.","sources":[]}')
}

fake_chat <- function() {
  captured <- NULL
  list(
    chat     = function(msg) { captured <<- msg; "LLM answer" },
    captured = function()    captured
  )
}

# perplexica_ask() -------------------------------------------------------------

test_that("perplexica_ask() returns the LLM response", {
  withr::local_options(list(perplexica.base_url = "http://localhost:3000"))
  httr2::local_mocked_responses(mock_api)

  ch  <- fake_chat()
  out <- perplexica_ask("What is the capital of France?", chat = ch)
  expect_equal(out, "LLM answer")
})

test_that("perplexica_ask() injects the search answer into the prompt", {
  withr::local_options(list(perplexica.base_url = "http://localhost:3000"))
  httr2::local_mocked_responses(mock_api)

  ch <- fake_chat()
  perplexica_ask("What is the capital of France?", chat = ch)

  prompt <- ch$captured()
  expect_match(prompt, "What is the capital of France?", fixed = TRUE)
  expect_match(prompt, "Paris is the capital of France.", fixed = TRUE)
})

test_that("perplexica_ask() appends source URLs when present", {
  withr::local_options(list(perplexica.base_url = "http://localhost:3000"))
  httr2::local_mocked_responses(mock_api)

  ch <- fake_chat()
  perplexica_ask("test query", chat = ch)

  expect_match(ch$captured(), "https://example.com", fixed = TRUE)
})

test_that("perplexica_ask() omits Sources section when no sources returned", {
  withr::local_options(list(perplexica.base_url = "http://localhost:3000"))
  httr2::local_mocked_responses(mock_api_no_sources)

  ch <- fake_chat()
  perplexica_ask("test query", chat = ch)

  expect_false(grepl("Sources:", ch$captured(), fixed = TRUE))
})

test_that("perplexica_ask() verbose = TRUE forwards to search and emits a message", {
  withr::local_options(list(perplexica.base_url = "http://localhost:3000"))
  httr2::local_mocked_responses(mock_api)

  ch <- fake_chat()
  expect_message(
    perplexica_ask("test query", chat = ch, verbose = TRUE),
    "Querying Perplexica"
  )
})

# perplexica_tool() ------------------------------------------------------------

test_that("perplexica_tool() errors informatively when ellmer is not installed", {
  skip_if(requireNamespace("ellmer", quietly = TRUE), "ellmer is installed; skipping absence test")
  expect_error(perplexica_tool(), "Package 'ellmer' is required")
})

test_that("perplexica_tool() returns an ellmer ToolDef when ellmer is available", {
  skip_if_not(requireNamespace("ellmer", quietly = TRUE), "ellmer not installed")
  withr::local_options(list(perplexica.base_url = "http://localhost:3000"))

  tool <- perplexica_tool()
  expect_true(inherits(tool, "ellmer::ToolDef"))
  expect_equal(tool@name, "perplexica_search")
})
