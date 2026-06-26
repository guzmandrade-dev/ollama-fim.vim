# Changelog

All notable changes to this project will be documented in this file.

## [1.0.5] - 2026-06-25

### Added

- **Native Ministral / Mistral FIM support.** New `ministral` model family
  (and corrected `mistral` family) use the Mistral native SPM format:
  `<s>[SUFFIX]{suffix}[PREFIX]{prefix}`.
- **Ollama `raw` mode** is automatically enabled for the `mistral`
  family so the model's chat template is bypassed.
- **Chat-template fallback for Ministral:** Ollama Cloud rejects raw
  mode for `ministral-3`, so the plugin wraps the SPM markers in a terse
  code-completion instruction and sends it through the normal generate
  endpoint.
- New `g:fim_ollama_system_prompt` option to customize the instruction
  used for chat-template-wrapped models.
- Documented the `ministral` family in README and Vim help.

### Fixed

- The previous `mistral` token format (`<|fim_prefix|>`...) was not the
  format actually expected by Codestral/Ministral models. It has been
  corrected to the native SPM format.

## [1.0.4] - 2026-06-24

### Changed

- **Popup-only UI:** removed the ghost-text `textprop` fallback. Suggestions are
  now rendered exclusively with `popup_atcursor`, which avoids buffer mutations
  and `E969: Property type already defined` errors when enabling/disabling the
  plugin repeatedly.
- **README updated** to reflect the popup-only UI, the new logging option, and
  the Ollama Cloud `rnj-1:8b-cloud` availability issue.

### Added

- **Request/response logging** via `g:fim_ollama_log_file`. Logs the curl
  command (with API key redacted), request body, HTTP status, stdout, and stderr
  for every completion request.
- **User-visible error reporting** when the API returns an HTTP error, invalid
  JSON, or an `error` field. Messages are throttled so they don't spam the
  user.
- **Automatic retry** for transient 5xx HTTP errors and API `error` responses.
  One retry is attempted with a fresh seed before giving up.
- **HTTP status capture** using `curl -w`, so the plugin reports real status
  codes even when the response body has no trailing newline.

### Fixed

- `FimOllamaEnable` no longer raises `E969` because the `FimOllamaGhostText`
  property type is no longer registered.
- Synchronous curl fallback now passes the correct stderr argument to the
  output handler.

## earlier

- Added file context and scope hint support.
- Added suggestion cycling (`FimOllamaNext`).
- Added cooldown logic to prevent repeated identical suggestions.
- Multi-model family support: `rnj-1`, `deepseek`, `qwen`, `gemma`, `mistral`.

## earlier

- Async `curl` client, debounced requests, accept/dismiss mappings.

## earlier

- Initial release with basic FIM inline completions for `rnj-1`.
