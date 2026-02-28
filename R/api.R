#' List configured Perplexica providers
#'
#' Returns the raw list of providers from the Perplexica `/api/providers`
#' endpoint. Each provider contains available chat and embedding models.
#'
#' @param base_url Base URL of the Perplexica instance.
#' @return A list of provider objects.
#' @export
#' @examples
#' \dontrun{
#' perplexica_providers()
#' }
perplexica_providers <- function(base_url = perplexica_get_url()) {
  resp <- httr2::request(base_url) |>
    httr2::req_url_path_append("api", "providers") |>
    httr2::req_perform()
  httr2::resp_body_json(resp)$providers
}

#' Select default chat and embedding models
#'
#' Iterates over the configured providers and returns the first one that has
#' both a chat model and an embedding model available. This is the same
#' selection logic the Perplexica UI uses on first load.
#'
#' @param providers Provider list from [perplexica_providers()]. Fetched
#'   automatically if not supplied.
#' @return A named list with `chatModel` and `embeddingModel`, each containing
#'   `providerId` and `key`.
#' @export
#' @examples
#' \dontrun{
#' perplexica_default_models()
#' }
perplexica_default_models <- function(providers = perplexica_providers()) {
  if (length(providers) == 0) {
    stop(
      "No providers configured in Perplexica.\n",
      "Open http://localhost:3000 and complete the setup wizard."
    )
  }

  for (p in providers) {
    chat <- p$chatModels
    emb  <- p$embeddingModels
    if (length(chat) > 0 && length(emb) > 0) {
      return(list(
        chatModel      = list(providerId = p$id, key = chat[[1]]$key),
        embeddingModel = list(providerId = p$id, key = emb[[1]]$key)
      ))
    }
  }

  stop(
    "No provider with both a chat model and an embedding model was found.\n",
    "Open http://localhost:3000 and add an API key or connect Ollama."
  )
}
