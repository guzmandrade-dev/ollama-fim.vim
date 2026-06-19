" Main orchestration: collect context, debounce, request, render.

let s:enabled = 1
let s:debounce_timer = -1
let s:request_counter = 0

" Default settings.
let s:defaults = {
    \ 'api_url': 'http://localhost:11434',
    \ 'model': 'rnj-1:8b-cloud',
    \ 'model_type': 'rnj-1',
    \ 'max_tokens': 256,
    \ 'temperature': 0.1,
    \ 'enabled': 1,
    \ 'include_file_context': 1,
    \ 'include_scope_info': 1,
    \ 'file_context_chars': 3000,
    \ 'debounce_ms': 300,
    \ 'max_prefix_chars': 2000,
    \ 'max_suffix_chars': 500,
    \ }

function! s:get(name) abort
    let l:key = 'fim_ollama_' . a:name
    if exists('g:' . l:key)
        return g:{l:key}
    endif
    return s:defaults[a:name]
endfunction

function! fim_ollama#core#setup() abort
    call fim_ollama#ui#init()
    let s:enabled = s:get('enabled')

    augroup FimOllama
        autocmd!
        if s:enabled
            autocmd InsertCharPre * call fim_ollama#core#schedule_request()
            autocmd TextChangedI  * call fim_ollama#core#schedule_request()
            autocmd InsertLeave   * call fim_ollama#core#cleanup()
            autocmd CursorMovedI  * call fim_ollama#core#dismiss_if_moved()
        endif
    augroup END
endfunction

function! fim_ollama#core#toggle() abort
    let s:enabled = !s:enabled
    let g:fim_ollama_enabled = s:enabled

    if s:enabled
        echo 'FIM Ollama enabled'
        call fim_ollama#core#setup()
    else
        echo 'FIM Ollama disabled'
        autocmd! FimOllama
        call fim_ollama#core#cleanup()
    endif
endfunction

function! fim_ollama#core#enabled() abort
    return s:enabled
endfunction

function! fim_ollama#core#schedule_request() abort
    if !s:enabled | return | endif

    call fim_ollama#core#cancel_debounce()
    let s:debounce_timer = timer_start(s:get('debounce_ms'), function('s:do_request'))
endfunction

function! fim_ollama#core#cancel_debounce() abort
    if s:debounce_timer >= 0
        call timer_stop(s:debounce_timer)
        let s:debounce_timer = -1
    endif
endfunction

function! s:do_request(timer_id) abort
    let s:debounce_timer = -1

    if mode() !=# 'i'
        return
    endif

    let l:bufnr = bufnr('%')
    let l:pos = getcurpos()
    let l:line = l:pos[1]
    let l:col = l:pos[2]

    " Cancel any in-flight job before issuing a new one.
    call fim_ollama#client#cancel()

    let s:request_counter += 1
    let l:request_id = s:request_counter

    let l:prefix = s:get_prefix(l:bufnr, l:line, l:col)
    let l:suffix = s:get_suffix(l:bufnr, l:line, l:col)

    " Skip when context is too thin.
    if len(trim(l:prefix)) < 10 && empty(trim(l:suffix))
        return
    endif
    if empty(trim(l:prefix)) && empty(trim(l:suffix))
        return
    endif

    let l:line_prefix = strpart(getline('.'), 0, l:col - 1)
    if empty(trim(l:line_prefix)) && empty(trim(l:suffix))
        return
    endif

    let l:enriched_prefix = s:enrich_prefix(l:bufnr, l:line, l:prefix)

    let l:model_type = s:get('model_type')
    let l:prompt = fim_ollama#prompt#build_fim_prompt(l:enriched_prefix, l:suffix, l:model_type)
    let l:stop_tokens = fim_ollama#prompt#all_stop_tokens(l:model_type)

    let l:config = {
        \ 'url': s:get('api_url'),
        \ 'model': s:get('model'),
        \ 'prompt': l:prompt,
        \ 'stop_tokens': l:stop_tokens,
        \ 'max_tokens': s:get('max_tokens'),
        \ 'temperature': s:get('temperature'),
        \ }

    call fim_ollama#client#request(l:request_id, l:config, function('s:on_completion', [l:request_id, l:bufnr, l:line, l:col]))
endfunction

function! s:on_completion(request_id, bufnr, line, col, returned_request_id, text) abort
    if a:request_id != a:returned_request_id
        return
    endif
    if a:bufnr != bufnr('%') || mode() !=# 'i'
        return
    endif

    let l:cur = getcurpos()
    if l:cur[1] != a:line || l:cur[2] != a:col
        return
    endif

    call fim_ollama#ui#show(a:bufnr, a:line, a:col, a:text)
endfunction

function! s:get_prefix(bufnr, line, col) abort
    let l:max = s:get('max_prefix_chars')
    let l:lines = getbufline(a:bufnr, 1, a:line)
    if empty(l:lines)
        return ''
    endif

    " Current line up to cursor.
    let l:current = strpart(l:lines[-1], 0, a:col - 1)
    let l:lines[-1] = l:current

    let l:prefix = join(l:lines, "\n")
    if len(l:prefix) > l:max
        let l:prefix = strpart(l:prefix, len(l:prefix) - l:max)
        let l:nl = stridx(l:prefix, "\n")
        if l:nl > 0
            let l:prefix = strpart(l:prefix, l:nl + 1)
        endif
    endif
    return l:prefix
endfunction

function! s:get_suffix(bufnr, line, col) abort
    let l:max = s:get('max_suffix_chars')
    let l:line_count = line('$')
    let l:lines = getbufline(a:bufnr, a:line, l:line_count)
    if empty(l:lines)
        return ''
    endif

    let l:current = strpart(l:lines[0], a:col - 1)
    let l:lines[0] = l:current

    let l:suffix = join(l:lines, "\n")
    if len(l:suffix) > l:max
        let l:suffix = strpart(l:suffix, 0, l:max)
    endif
    return l:suffix
endfunction

function! s:enrich_prefix(bufnr, cursor_line, prefix) abort
    let l:prefix = a:prefix

    if s:get('include_file_context')
        let l:max = s:get('file_context_chars')
        let l:file_context = fim_ollama#context#extract_file_context(a:bufnr, a:cursor_line, l:max)
        let l:file_name = fnamemodify(bufname(a:bufnr), ':t')
        let l:lang = getbufvar(a:bufnr, '&filetype')
        let l:formatted = fim_ollama#context#format_file_context(l:file_context, l:file_name, l:lang)
        if !empty(l:formatted)
            let l:prefix = l:formatted . l:prefix
        endif
    endif

    if s:get('include_scope_info')
        let l:scope = fim_ollama#context#extract_current_scope(a:bufnr, a:cursor_line)
        if !empty(l:scope)
            let l:prefix = '// Currently in: ' . l:scope . "\n" . l:prefix
        endif
    endif

    return l:prefix
endfunction

function! fim_ollama#core#accept() abort
    if !fim_ollama#ui#is_visible()
        " Let Tab pass through if no suggestion.
        return "\u0009"
    endif

    let l:text = fim_ollama#ui#accept()
    if empty(l:text)
        return ''
    endif

    " Insert the completion text at cursor.
    return l:text
endfunction

function! fim_ollama#core#dismiss() abort
    call fim_ollama#ui#hide()
    call fim_ollama#client#cancel()
    call fim_ollama#core#cancel_debounce()
endfunction

function! fim_ollama#core#cleanup() abort
    call fim_ollama#ui#hide()
    call fim_ollama#client#cancel()
    call fim_ollama#core#cancel_debounce()
endfunction

" Dismiss ghost text if cursor moved from the request position.
function! fim_ollama#core#dismiss_if_moved() abort
    if fim_ollama#ui#is_visible()
        call fim_ollama#ui#hide()
    endif
endfunction
