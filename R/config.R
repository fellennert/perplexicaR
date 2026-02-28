# Internal null-coalescing operator
`%||%` <- function(x, y) if (is.null(x)) y else x

#' Set the Perplexica base URL for the current session
#'
#' Stores the URL in an R option so it does not need to be passed to every
#' function call. `perplexica_start()` calls this automatically.
#'
#' @param url Base URL of the running Perplexica instance.
#' @return The URL, invisibly.
#' @export
#' @examples
#' perplexica_set_url("http://localhost:3000")
#' perplexica_set_url("http://my-server:3000")  # remote instance
perplexica_set_url <- function(url = "http://localhost:3000") {
  options(perplexica.base_url = url)
  invisible(url)
}

#' Get the current Perplexica base URL
#'
#' Returns the URL stored by `perplexica_set_url()`, defaulting to
#' `http://localhost:3000`.
#'
#' @return A character string with the base URL.
#' @export
perplexica_get_url <- function() {
  getOption("perplexica.base_url", "http://localhost:3000")
}
