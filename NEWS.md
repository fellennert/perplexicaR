# perplexicaR 0.1.0

Initial release.

## New features

### Setup & Docker lifecycle

- `perplexica_setup()` — interactive wizard: starts Docker container, opens
  browser to Perplexica settings if no AI provider is configured, and loops
  until a usable provider is detected.
- `perplexica_start()` — pull and start the Perplexica Docker container; polls
  until the API is ready and sets the session URL automatically.
- `perplexica_stop()` — stop the container.
- `perplexica_status()` — lightweight health check; returns `TRUE`/`FALSE`.
- `perplexica_set_url()` / `perplexica_get_url()` — manage the base URL via an
  R option (default `http://localhost:3000`); supports remote instances.

### Search

- `perplexica_search()` — single query; returns a list with `message`
  (synthesised answer) and `sources` (character vector of URLs).
- `perplexica_search_with_retry()` — wraps `perplexica_search()` with
  automatic retry on empty responses or transient errors.
- `perplexica_search_many()` — batch search over a character vector; prints
  progress, writes periodic CSV checkpoints, and supports resuming from a
  checkpoint row.
- All search functions accept `verbose = TRUE` to print the query (and retry
  attempts) before each API call.

### LLM integration

- `perplexica_tool()` — returns an ellmer `ToolDef` that wraps
  `perplexica_search_with_retry()`. Register with `chat$register_tool()` to
  give an LLM autonomous web-search capability. Includes MCP annotations
  (`read_only_hint = TRUE`, `open_world_hint = TRUE`) and exposes source URLs
  in the tool result so the LLM can cite them.
- `perplexica_ask()` — pre-fetch pattern: searches Perplexica unconditionally,
  injects the answer and sources into the prompt, then calls `chat$chat()`.
  Guarantees that live web information is always used, with no tool-calling
  decision involved.

### API helpers

- `perplexica_providers()` — list configured providers from `/api/providers`.
- `perplexica_default_models()` — pick the first provider that has both a chat
  model and an embedding model; mirrors Perplexica's own UI logic.
