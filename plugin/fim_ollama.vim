" Plugin entry point: global commands, mappings, default config.

if exists('g:loaded_fim_ollama')
    finish
endif
let g:loaded_fim_ollama = 1

" Default global settings (users can override in .vimrc).
if !exists('g:fim_ollama_enabled')
    let g:fim_ollama_enabled = 1
endif
if !exists('g:fim_ollama_api_url')
    let g:fim_ollama_api_url = 'http://localhost:11434'
endif
if !exists('g:fim_ollama_model')
    let g:fim_ollama_model = 'rnj-1:8b-cloud'
endif
if !exists('g:fim_ollama_model_type')
    let g:fim_ollama_model_type = 'rnj-1'
endif
if !exists('g:fim_ollama_max_tokens')
    let g:fim_ollama_max_tokens = 256
endif
if !exists('g:fim_ollama_temperature')
    let g:fim_ollama_temperature = 0.1
endif
if !exists('g:fim_ollama_include_file_context')
    let g:fim_ollama_include_file_context = 1
endif
if !exists('g:fim_ollama_include_scope_info')
    let g:fim_ollama_include_scope_info = 1
endif
if !exists('g:fim_ollama_file_context_chars')
    let g:fim_ollama_file_context_chars = 3000
endif
if !exists('g:fim_ollama_debounce_ms')
    let g:fim_ollama_debounce_ms = 300
endif
if !exists('g:fim_ollama_max_prefix_chars')
    let g:fim_ollama_max_prefix_chars = 2000
endif
if !exists('g:fim_ollama_max_suffix_chars')
    let g:fim_ollama_max_suffix_chars = 500
endif
if !exists('g:fim_ollama_map_tab')
    let g:fim_ollama_map_tab = 1
endif
if !exists('g:fim_ollama_normalize_indent')
    let g:fim_ollama_normalize_indent = 1
endif

command! FimOllamaEnable  call fim_ollama#core#setup()
command! FimOllamaDisable call fim_ollama#core#cleanup()
command! FimOllamaToggle  call fim_ollama#core#toggle()
command! FimOllamaDismiss call fim_ollama#core#dismiss()
command! FimOllamaNext    call fim_ollama#core#next_suggestion()

" Default mappings (only mapped if not already defined by user).
if g:fim_ollama_map_tab && !hasmapto('<Plug>(FimAccept)')
    imap <silent> <Tab> <Plug>(FimAccept)
endif
if !hasmapto('<Plug>(FimNext)')
    " Alt+] is the default, but many terminals swallow it. Provide Ctrl+] as a
    " fallback so the user can always cycle suggestions.
    imap <silent> <M-]> <Plug>(FimNext)
    imap <silent> <C-]> <Plug>(FimNext)
endif

" <Plug> handlers (non-recursive so the Tab fallback doesn't loop).
inoremap <expr> <Plug>(FimAccept)  fim_ollama#core#accept()
inoremap <silent> <Plug>(FimDismiss) <Cmd>call fim_ollama#core#dismiss()<CR>
inoremap <silent> <Plug>(FimNext)   <Cmd>call fim_ollama#core#next_suggestion()<CR>

" Auto-enable if configured.
if g:fim_ollama_enabled
    call fim_ollama#core#setup()
endif
