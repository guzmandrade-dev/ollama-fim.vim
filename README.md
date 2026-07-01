# ollama-fim.vim

A Vim plugin for inline FIM (fill-in-the-middle) code completions powered by
Ollama models. It is heavily inspired by the UX of `copilot.vim` — suggestions
appear as you type in a popup and can be accepted with `Tab` — but it uses
your own Ollama instance and the same FIM prompt engineering from the
`ollama-fim` VS Code extension https://marketplace.visualstudio.com/items?itemName=guzmandrade-dev.ollama-fim.

## Features

- **Popup-based completions** rendered with `popup_atcursor`, so suggestions
  never modify your buffer.
- **Async `curl` backend** — no Python, Node, or LSP agent required.
- **FIM prompt support** for six model families:
  `rnj-1`, `deepseek`, `qwen`, `gemma`, `mistral`, `ministral`.
- **File-level context** (imports, class/function signatures, recent context,
  comments) ported from the VS Code extension.
- **Current scope hint** (e.g. `// Currently in: class Foo > method bar`).
- **Configurable API key** via `g:fim_ollama_api_key` or the `OLLAMA_API_KEY`
  environment variable.

## Requirements

- Vim with `popup_atcursor` support (Vim 8.2+ popup feature).
- `curl` installed and available in `$PATH`.
- A running Ollama server or Ollama Cloud access.

## Installation

### Using Vim's built-in packages

```bash
mkdir -p ~/.vim/pack/plugins/start
cd ~/.vim/pack/plugins/start
git clone https://github.com/guzmandrade-dev/ollama-fim.vim.git
```

### Using vim-plug

```vim
Plug 'guzmandrade-dev/ollama-fim.vim', { 'rtp': 'vim' }
```

## Configuration

Add to your `.vimrc` / `init.vim`:

```vim
" Required: model running in Ollama or an OpenAI-compatible API
let g:fim_ollama_model = 'rnj-1:8b-cloud'

" FIM format family. Must match the model architecture.
" Options: 'rnj-1', 'deepseek', 'qwen', 'gemma', 'mistral', 'ministral'
let g:fim_ollama_model_type = 'rnj-1'

" Backend: 'ollama' (default) or 'openai' for OpenAI-compatible providers.
let g:fim_ollama_backend = 'ollama'

" Optional: API base URL and endpoint path
let g:fim_ollama_api_url = 'http://localhost:11434'
let g:fim_ollama_api_path = '/api/generate'

" Optional: generation controls
let g:fim_ollama_max_tokens = 64
let g:fim_ollama_temperature = 0.1

" Optional: context awareness
let g:fim_ollama_include_file_context = 1
let g:fim_ollama_include_scope_info = 1
let g:fim_ollama_file_context_chars = 3000

" Optional: request debounce and context window sizes
let g:fim_ollama_debounce_ms = 300
let g:fim_ollama_max_prefix_chars = 2000
let g:fim_ollama_max_suffix_chars = 500

" Optional: normalize indentation in completions to match buffer settings
" (expandtab, tabstop, shiftwidth). Default: 1.
let g:fim_ollama_normalize_indent = 1

" Optional: system prompt used for chat-template-wrapped models (ministral).
let g:fim_ollama_system_prompt = 'Complete the code. Output only raw code, no explanation.'

" Optional: enable request/response logging for debugging
let g:fim_ollama_log_file = expand('~/.fim_ollama.log')
```

## Usage

Suggestions appear automatically in insert mode after a short debounce. Use:

| Key | Action |
|-----|--------|
| `Tab` | Accept the suggestion |
| `Alt-]` | Cycle to the next suggestion |
| `Ctrl-]` | Cycle to the next suggestion (fallback) |

Commands:

```vim
:FimOllamaEnable    " turn on completions
:FimOllamaDisable   " turn off completions
:FimOllamaToggle    " toggle on/off
:FimOllamaDismiss   " dismiss current suggestion
:FimOllamaNext      " request an alternative suggestion
```

## Mapping customization

To avoid `Tab` conflicts (e.g. with a snippet plugin), override before the
plugin loads:

```vim
imap <silent> <C-J> <Plug>(FimAccept)
imap <silent> <C-L> <Plug>(FimDismiss)
```

## OpenAI-compatible providers

The plugin can talk to any provider that exposes an OpenAI-style text
completions endpoint (`/v1/completions`). This includes Together AI,
local Ollama, and other OpenAI-compatible hosts.

```vim
let g:fim_ollama_backend = 'openai'
let g:fim_ollama_api_url = 'https://api.together.ai/v1'
let g:fim_ollama_api_path = '/completions'
let g:fim_ollama_model = 'Qwen/Qwen2.5-Coder-7B-Instruct'
let g:fim_ollama_model_type = 'qwen'
let g:fim_ollama_api_key = '<YOUR_API_KEY>'
let g:fim_ollama_max_tokens = 64
let g:fim_ollama_temperature = 0.1
```

The `backend` setting changes the request/response shape: `ollama` sends
Ollama's `/api/generate` payload, while `openai` sends an OpenAI
`/v1/completions` payload with separate `prompt` and `suffix` fields so
providers can apply the model's native FIM template. The generated code
is read from `choices[0].text` (with a fallback to
`choices[0].message.content` for chat-style responses). The FIM prompt
tokens are still selected by `g:fim_ollama_model_type`.

## Model-specific notes

| Family | Format | Example model |
|--------|--------|---------------|
| `rnj-1` | `\<|pre_fim\|>...\<|suf_fim\|>...\<|mid_fim\|>` | `rnj-1:8b-cloud` |
| `deepseek` | `\<|fim_begin\|>...\<|fim_hole\|>...\<|fim_end\|>` | `deepseek-coder-v2:lite-instruct` |
| `qwen` | `\<|fim_prefix\|>...\<|fim_suffix\|>...\<|fim_middle\|>` | `qwen2.5-coder:7b` |
| `gemma` | `\<|fim_prefix\|>...\<|fim_middle\|>...\<|fim_suffix\|>` | `gemma3:latest` |
| `mistral` | `\<s\u003e[SUFFIX]{suffix}[PREFIX]{prefix}` (raw mode) | `codestral:latest` |
| `ministral` | chat-template-wrapped SPM FIM with terse code-completion instruction (raw mode unsupported on Ollama Cloud) | `ministral-3:3b-cloud` |

**Using `mistral` / `ministral`:** `mistral` uses Ollama `raw` mode to send
`<s>[SUFFIX]{suffix}[PREFIX]{prefix}` directly to the model. `ministral`
does the same, but because Ollama Cloud currently rejects `raw` mode for
`ministral-3`, the plugin embeds the SPM markers inside a short
instruction so the chat template still produces a code completion. You
can tweak that instruction with `g:fim_ollama_system_prompt`.

```vim
let g:fim_ollama_system_prompt = 'Complete the code. Output only raw code, no explanation.'
```

## Files

```text
vim/
├── plugin/fim_ollama.vim        " entry point, commands, mappings
├── autoload/fim_ollama/
│   ├── core.vim                 " orchestration, context gathering
│   ├── prompt.vim               " FIM token formatting per model family
│   ├── context.vim              " file context + current scope extraction
│   ├── indent.vim               " indentation normalization
│   ├── client.vim               " async curl Ollama client
│   └── ui.vim                   " popup-based suggestion UI
└── doc/
    └── fim_ollama.txt           " Vim help documentation
```

## Indentation handling

The plugin respects your buffer's indentation settings:

- When `expandtab` is set, completions are normalized so leading tab
  characters become spaces (based on `tabstop`).
- When `noexpandtab` is set, leading spaces that align with `shiftwidth`
  are converted to tabs.
- Context sent to the model is also normalized so the model is primed
  with your current style.

To disable normalization:

```vim
let g:fim_ollama_normalize_indent = 0
```

## Changelog

See [CHANGELOG.md](CHANGELOG.md).

## License

MIT

