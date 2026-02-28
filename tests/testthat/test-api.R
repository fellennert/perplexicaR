# Fake provider lists used across tests ----------------------------------------

provider_full <- list(
  list(
    id = "openai",
    chatModels      = list(list(key = "gpt-4o-mini")),
    embeddingModels = list(list(key = "text-embedding-3-small"))
  )
)

provider_chat_only <- list(
  list(
    id = "openai",
    chatModels      = list(list(key = "gpt-4o-mini")),
    embeddingModels = list()
  )
)

provider_embed_only <- list(
  list(
    id = "openai",
    chatModels      = list(),
    embeddingModels = list(list(key = "text-embedding-3-small"))
  )
)

provider_multi <- list(
  list(id = "a", chatModels = list(list(key = "chat-a")), embeddingModels = list()),
  list(id = "b", chatModels = list(),                     embeddingModels = list(list(key = "emb-b"))),
  list(id = "c", chatModels = list(list(key = "chat-c")), embeddingModels = list(list(key = "emb-c")))
)

# perplexica_default_models() --------------------------------------------------

test_that("perplexica_default_models() returns correct structure", {
  m <- perplexica_default_models(provider_full)
  expect_type(m, "list")
  expect_named(m, c("chatModel", "embeddingModel"))
  expect_named(m$chatModel,      c("providerId", "key"))
  expect_named(m$embeddingModel, c("providerId", "key"))
})

test_that("perplexica_default_models() picks correct model keys", {
  m <- perplexica_default_models(provider_full)
  expect_equal(m$chatModel$providerId,      "openai")
  expect_equal(m$chatModel$key,             "gpt-4o-mini")
  expect_equal(m$embeddingModel$providerId, "openai")
  expect_equal(m$embeddingModel$key,        "text-embedding-3-small")
})

test_that("perplexica_default_models() errors when provider list is empty", {
  expect_error(perplexica_default_models(list()), "No providers configured")
})

test_that("perplexica_default_models() errors when no provider has both model types", {
  expect_error(
    perplexica_default_models(c(provider_chat_only, provider_embed_only)),
    "No provider with both"
  )
})

test_that("perplexica_default_models() skips incomplete providers and uses first complete one", {
  m <- perplexica_default_models(provider_multi)
  expect_equal(m$chatModel$providerId,      "c")
  expect_equal(m$chatModel$key,             "chat-c")
  expect_equal(m$embeddingModel$key,        "emb-c")
})
