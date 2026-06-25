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
- **FIM prompt support** for five model families:
  `rnj-1`, `deepseek`, `qwen`, `gemma`, `mistral`.
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
" Required: model running in Ollama
let g:fim_ollama_model = 'rnj-1:8b-cloud'

" FIM format family. Must match the model architecture.
" Options: 'rnj-1', 'deepseek', 'qwen', 'gemma', 'mistral'
let g:fim_ollama_model_type = 'rnj-1'

" Optional: change Ollama host
let g:fim_ollama_api_url = 'http://localhost:11434'

" Optional: generation controls
let g:fim_ollama_max_tokens = 256
let g:fim_ollama_temperature = 0.1

" Optional: context awareness
let g:fim_ollama_include_file_context = 1
let g:fim_ollama_include_scope_info = 1
let g:fim_ollama_file_context_chars = 3000

" Optional: request debounce and context window sizes
let g:fim_ollama_debounce_ms = 300
let g:fim_ollama_max_prefix_chars = 2000
let g:fim_ollama_max_suffix_chars = 500

" Optional: API key (falls back to $OLLAMA_API_KEY)
let g:fim_ollama_api_key = 'your-token-here'

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

## Model-specific notes

| Family | Format | Example model |
|--------|--------|---------------|
| `rnj-1` | `<\|pre_fim\|>...<\|suf_fim\|>...<\|mid_fim\|>` | `rnj-1:8b-cloud` |
| `deepseek` | `<\|fim_begin\|>...<\|fim_hole\|>...<\|fim_end\|>` | `deepseek-coder-v2:lite-instruct` |
| `qwen` | `<\|fim_prefix\|>...<\|fim_suffix\|>...<\|fim_middle\|>` | `qwen3-coder-next:latest` |
| `gemma` | `<\|fim_prefix\|>...<\|fim_middle\|>...<\|fim_suffix\|>` | `gemma3:latest` |
| `mistral` | `<\|fim_prefix\|>...<\|fim_suffix\|>...<\|fim_middle\|>` | `codestral:latest` |

**Note on Ollama Cloud model availability:** the `rnj-1:8b-cloud` model has
been intermittently returning `500 Internal Server Error` from Ollama Cloud.
If completions stop appearing, check the log (`g:fim_ollama_log_file`) or try
another FIM-capable model such as `gemma3:latest` or `codestral:latest`.

## Files

```text
vim/
├── plugin/fim_ollama.vim        " entry point, commands, mappings
├── autoload/fim_ollama/
│   ├── core.vim                 " orchestration, context gathering
│   ├── prompt.vim               " FIM token formatting per model family
│   ├── context.vim              " file context + current scope extraction
│   ├── client.vim               " async curl Ollama client
│   └── ui.vim                   " popup-based suggestion UI
└── doc/
    └── fim_ollama.txt           " Vim help documentation
```

## Changelog

See [CHANGELOG.md](CHANGELOG.md).

## License

MIT

