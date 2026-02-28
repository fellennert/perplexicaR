PERPLEXICA_IMAGE <- "itzcrazykns1337/perplexica:latest"
PERPLEXICA_CONTAINER <- "perplexica"
PERPLEXICA_VOLUME <- "perplexica-data"

docker_available <- function() {
  nchar(Sys.which("docker")) > 0
}

docker_container_running <- function() {
  out <- system2("docker", c("ps", "-q", "-f", "name=perplexica"), stdout = TRUE)
  length(out) > 0 && nchar(out[[1]]) > 0
}

docker_container_exists <- function() {
  out <- system2("docker", c("ps", "-aq", "-f", "name=perplexica"), stdout = TRUE)
  length(out) > 0 && nchar(out[[1]]) > 0
}

#' Start the Perplexica Docker container
#'
#' Pulls and starts the Perplexica container if it is not already running,
#' then waits until the API responds. Sets the session URL automatically via
#' [perplexica_set_url()], so no further configuration is needed.
#'
#' Docker Desktop must be installed and running before calling this function.
#'
#' @param port Host port to expose Perplexica on. Defaults to 3000.
#' @param timeout Maximum seconds to wait for the API to become ready.
#' @param image Docker image to use. Override if you self-build Perplexica.
#' @return The base URL, invisibly.
#' @export
#' @examples
#' \dontrun{
#' perplexica_start()
#' perplexica_start(port = 3001, timeout = 60)
#' }
perplexica_start <- function(
    port    = 3000L,
    timeout = 30L,
    image   = PERPLEXICA_IMAGE) {

  if (!docker_available()) {
    stop(
      "Docker not found on PATH.\n",
      "Install Docker Desktop: https://www.docker.com/products/docker-desktop/"
    )
  }

  url <- paste0("http://localhost:", port)

  if (docker_container_running()) {
    message("Perplexica is already running at ", url)
    perplexica_set_url(url)
    return(invisible(url))
  }

  if (docker_container_exists()) {
    message("Starting existing Perplexica container...")
    system2("docker", c("start", PERPLEXICA_CONTAINER))
  } else {
    message("Starting Perplexica container (first run may take a moment to pull the image)...")
    system2("docker", c(
      "run", "-d",
      "--name", PERPLEXICA_CONTAINER,
      "-p", paste0(port, ":3000"),
      "-v", paste0(PERPLEXICA_VOLUME, ":/home/perplexica/data"),
      "--restart", "unless-stopped",
      image
    ))
  }

  message("Waiting for API", appendLF = FALSE)
  deadline <- proc.time()[["elapsed"]] + timeout

  repeat {
    ready <- tryCatch({
      r <- httr2::request(paste0(url, "/api/providers")) |>
        httr2::req_error(is_error = \(r) FALSE) |>
        httr2::req_perform()
      httr2::resp_status(r) == 200L
    }, error = function(e) FALSE)

    if (ready) break

    if (proc.time()[["elapsed"]] > deadline) {
      stop(
        "Perplexica did not start within ", timeout, " seconds.\n",
        "Check logs with: docker logs ", PERPLEXICA_CONTAINER
      )
    }

    message(".", appendLF = FALSE)
    Sys.sleep(1)
  }

  elapsed <- round(proc.time()[["elapsed"]] - (deadline - timeout), 1)
  message(" ready (", elapsed, "s)")
  perplexica_set_url(url)
  message("Perplexica is running at ", url)
  invisible(url)
}

#' Stop the Perplexica Docker container
#'
#' @return Exit status of the `docker stop` command, invisibly.
#' @export
#' @examples
#' \dontrun{
#' perplexica_stop()
#' }
perplexica_stop <- function() {
  if (!docker_available()) stop("Docker not found on PATH.")
  message("Stopping Perplexica container...")
  invisible(system2("docker", c("stop", PERPLEXICA_CONTAINER)))
}

#' Check whether the Perplexica API is reachable
#'
#' Does a lightweight GET to `/api/providers` and returns `TRUE` if the
#' response is HTTP 200, `FALSE` otherwise (including when the container is
#' not running).
#'
#' @param base_url Base URL to check. Defaults to the session URL.
#' @return Logical scalar.
#' @export
#' @examples
#' \dontrun{
#' perplexica_status()
#' }
perplexica_status <- function(base_url = perplexica_get_url()) {
  tryCatch({
    r <- httr2::request(paste0(base_url, "/api/providers")) |>
      httr2::req_error(is_error = \(r) FALSE) |>
      httr2::req_perform()
    httr2::resp_status(r) == 200L
  }, error = function(e) FALSE)
}

#' Interactive setup wizard for Perplexica
#'
#' Walks through everything needed to get Perplexica up and running in one
#' call: checks Docker, starts the container, and guides you through
#' configuring an AI provider (API key or Ollama). Steps that are already
#' complete are skipped automatically, so it is safe to call repeatedly.
#'
#' Must be run in an interactive R session.
#'
#' @param port Host port Perplexica is (or will be) exposed on. Default 3000.
#' @param timeout Seconds to wait for the API to become ready after container
#'   start. Default 30.
#' @param image Docker image to use. Override only if you self-build Perplexica.
#' @return `TRUE` invisibly on success.
#' @export
#' @examples
#' \dontrun{
#' perplexica_setup()
#' }
perplexica_setup <- function(
    port    = 3000L,
    timeout = 30L,
    image   = PERPLEXICA_IMAGE) {

  if (!interactive()) {
    stop("perplexica_setup() must be run in an interactive R session.", call. = FALSE)
  }

  url <- paste0("http://localhost:", port)

  # -- Step 1: Ensure Perplexica is reachable ---------------------------------
  message("\n-- Step 1 / 2: Starting Perplexica ------------------------------------")

  if (perplexica_status(url)) {
    message("  Already running at ", url, " - skipping.")
    perplexica_set_url(url)

  } else if (docker_available()) {
    perplexica_start(port = port, timeout = timeout, image = image)

  } else {
    stop(
      "Perplexica is not reachable at ", url, " and Docker was not found on PATH.\n\n",
      "Fix one of the following, then run perplexica_setup() again:\n\n",
      "  A) Install Docker Desktop so the package can start Perplexica for you:\n",
      "       https://www.docker.com/products/docker-desktop/\n\n",
      "  B) Start Perplexica manually and point the package at it:\n",
      "       perplexica_set_url(\"http://<host>:<port>\")",
      call. = FALSE
    )
  }

  # -- Step 2: Ensure an AI provider is configured ----------------------------
  message("\n-- Step 2 / 2: Checking AI provider configuration --------------------")

  providers_ok <- function() {
    tryCatch({
      perplexica_default_models(perplexica_providers())
      TRUE
    }, error = function(e) FALSE)
  }

  if (!providers_ok()) {
    message(
      "\n  No AI provider is configured yet.\n",
      "  Perplexica needs a model to generate search answers - either a\n",
      "  cloud API key (OpenAI, Anthropic, Groq, etc.) or a local Ollama instance.\n\n",
      "  Opening the Perplexica settings page in your browser now.\n\n",
      "  In the browser:\n",
      "    1. Click the settings cog in the bottom-left corner.\n",
      "    2. Under 'Chat model', select a provider and paste in your API key\n",
      "       (or choose 'Ollama' if you have it running locally).\n",
      "    3. Under 'Embedding model', do the same.\n",
      "    4. Click Save.\n"
    )
    utils::browseURL(perplexica_get_url())

    repeat {
      readline("  Press Enter once you have saved the settings...")
      if (providers_ok()) break
      message("  No configured provider detected yet - please complete the setup in the browser.")
    }
  }

  # -- Summary ----------------------------------------------------------------
  models <- perplexica_default_models(perplexica_providers())
  message(
    "\n  Provider:        ", models$chatModel$providerId,
    "\n  Chat model:      ", models$chatModel$key,
    "\n  Embedding model: ", models$embeddingModel$key,
    "\n\n  Setup complete! Try:\n",
    "    perplexica_search(\"What is the current population of Tokyo?\")\n"
  )

  invisible(TRUE)
}
