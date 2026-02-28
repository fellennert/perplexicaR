# perplexicaR

<!-- badges: start -->
[![R CMD check](https://github.com/fellennert/perplexicaR/actions/workflows/R-CMD-check.yaml/badge.svg)](https://github.com/fellennert/perplexicaR/actions/workflows/R-CMD-check.yaml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
<!-- badges: end -->

An R client for [Perplexica](https://github.com/ItzCrazyKns/Perplexica) — a
self-hosted, open-source AI search engine. The package handles the full
lifecycle in R:

- **Docker management** — pull, start, stop, and health-check the Perplexica
  container with one function call
- **Guided setup** — an interactive wizard that walks through first-time
  configuration
- **Search** — single queries, automatic retry on empty responses, and batch
  search with checkpoint/resume support
- **LLM integration** — an [ellmer](https://ellmer.tidyverse.org/) tool
  definition so any ellmer-compatible chat model can search the web
  autonomously, and a pre-fetch helper that guarantees search is always called

## Installation

```r
# install.packages("pak")
pak::pak("fellennert/perplexicaR")
```

The only hard dependency is `httr2`. The `ellmer` package is optional and only
needed for the agentic functions (`perplexica_tool()`, `perplexica_ask()`).

---

## Quick start

```r
library(perplexicaR)

# 1. First-time setup (interactive wizard)
perplexica_setup()

# 2. Search
res <- perplexica_search("What is the current population of Tokyo?")
res$message   # synthesised answer
res$sources   # character vector of source URLs

# 3. Stop when done
perplexica_stop()
```

---

## 1. Setup

### First time

`perplexica_setup()` is an interactive wizard that handles everything:

1. Checks that Docker is installed and starts the container (pulling the image
   on the very first run)
2. Detects whether an AI provider is configured — if not, opens the Perplexica
   settings page in your browser and waits while you add an API key (OpenAI,
   Anthropic, Groq, …) or connect a local Ollama instance
3. Prints a summary of the active models when everything is ready

```r
perplexica_setup()
#>
#> -- Step 1 / 2: Starting Perplexica ------------------------------------
#> Starting Perplexica container (first run may take a moment to pull the image)...
#> Waiting for API.... ready (4.1s)
#> Perplexica is running at http://localhost:3000
#>
#> -- Step 2 / 2: Checking AI provider configuration --------------------
#>
#>   Provider:        openai
#>   Chat model:      gpt-4o-mini
#>   Embedding model: text-embedding-3-small
#>
#>   Setup complete! Try:
#>     perplexica_search("What is the current population of Tokyo?")
```

Safe to call repeatedly — already-complete steps are skipped.

### Subsequent sessions

Once the container exists, `perplexica_start()` is instant:

```r
perplexica_start()
#> Perplexica is already running at http://localhost:3000
```

### Remote instance

If you run Perplexica on another machine, skip Docker entirely:

```r
perplexica_set_url("http://my-server:3000")
```

### Other lifecycle functions

```r
perplexica_stop()        # stop the container
perplexica_status()      # TRUE / FALSE — is the API reachable?
```

---

## 2. Single search

```r
res <- perplexica_search("Who won the most recent FIFA World Cup?")

res$message
#> [1] "Argentina won the 2022 FIFA World Cup, defeating France on penalties..."

res$sources
#> [1] "https://www.fifa.com/..."  "https://en.wikipedia.org/..."
```

Use `mode = "balanced"` for slower but more thorough answers (default is
`"speed"`). Use `verbose = TRUE` to print the query before it is sent — useful
when debugging:

```r
perplexica_search("R 4.4 release date", verbose = TRUE)
#> Querying Perplexica: R 4.4 release date
```

### Retry on empty responses

Perplexica occasionally returns an empty answer under load. Use
`perplexica_search_with_retry()` to retry automatically:

```r
res <- perplexica_search_with_retry(
  "Latest R release version",
  max_retries = 3,
  verbose     = TRUE
)
#> Querying Perplexica: Latest R release version
#>   Retrying (attempt 2/4)
```

---

## 3. Batch search

`perplexica_search_many()` loops over a character vector of queries, printing
progress and saving periodic checkpoints so a crashed session can be resumed
without re-querying completed rows.

```r
queries <- c(
  "Current GDP of Brazil",
  "Population of Nigeria 2025",
  "Largest sovereign wealth funds by assets"
)

results <- perplexica_search_many(
  queries,
  delay            = 2,    # seconds between requests
  checkpoint_every = 25,   # save to disk every 25 rows
  checkpoint_file  = "search_checkpoint.csv"
)
#> [1/3] Current GDP of Brazil
#> [2/3] Population of Nigeria 2025
#> [3/3] Largest sovereign wealth funds by assets
```

`results` is a plain data frame with columns `query` and `message`.

### Resuming after a crash

```r
results <- perplexica_search_many(
  queries,
  checkpoint_file = "search_checkpoint.csv",
  resume_from     = 26   # rows 1–25 are read from the checkpoint file
)
#> Resuming from row 26 (loaded 25 rows from checkpoint)
```

---

## 4. LLM integration (ellmer)

Requires the `ellmer` package (`install.packages("ellmer")`).

### Tool-calling mode

Register `perplexica_tool()` with an ellmer chat object. The LLM decides when
to search:

```r
library(ellmer)

chat <- chat_openai(
  model         = "gpt-4.1",
  system_prompt = "You are a helpful assistant with access to live web search."
)

chat$register_tool(perplexica_tool())

chat$chat("Who won the most recent FIFA World Cup?")
#> [tool call] perplexica_search("most recent FIFA World Cup winner")
#> [tool result] "Argentina won the 2022 FIFA World Cup..."
#>
#> Argentina won the 2022 FIFA World Cup, defeating France on penalties.
```

To encourage the LLM to always search before answering, add a directive to the
system prompt:

```
"Always call perplexica_search before answering. Never rely on prior knowledge alone."
```

### Pre-fetch mode (guaranteed search)

`perplexica_ask()` searches Perplexica first and injects the result directly
into the prompt — the LLM has no option to skip it:

```r
chat <- chat_openai(model = "gpt-4.1")

perplexica_ask("Who won the most recent FIFA World Cup?", chat = chat)
```

Use this when every query is a factual lookup and you need a hard guarantee
that fresh web information is always used.

---

## Function reference

| Function | Purpose |
|---|---|
| `perplexica_setup(port, timeout)` | Interactive first-time setup wizard |
| `perplexica_start(port, timeout)` | Start container; set session URL |
| `perplexica_stop()` | Stop container |
| `perplexica_status(base_url)` | `TRUE` / `FALSE` — API reachable? |
| `perplexica_set_url(url)` | Override URL (e.g. remote server) |
| `perplexica_get_url()` | Read current session URL |
| `perplexica_providers(base_url)` | List configured providers |
| `perplexica_default_models(providers)` | Pick first usable chat + embedding model |
| `perplexica_search(query, mode, base_url, verbose)` | Single search |
| `perplexica_search_with_retry(query, max_retries, ..., verbose)` | Single search with retry |
| `perplexica_search_many(queries, delay, checkpoint_every, checkpoint_file, resume_from, ..., verbose)` | Batch search with checkpointing |
| `perplexica_tool(mode, base_url)` | ellmer tool definition (LLM decides when to search) |
| `perplexica_ask(query, chat, mode, base_url, verbose)` | Pre-fetch search then call LLM |

---

## Requirements

- R >= 4.1.0
- [Docker Desktop](https://www.docker.com/products/docker-desktop/) (only for
  local Docker-managed instances)
- An AI provider configured in Perplexica (OpenAI, Anthropic, Groq, or local
  Ollama)

## License

MIT
