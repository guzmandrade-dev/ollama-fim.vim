" Main orchestration: collect context, debounce, request, render.

let s:enabled = 1
let s:debounce_timer = -1
let s:request_counter = 0
let s:accept_lock = 0
let s:last_accepted_text = ''
let s:chars_since_accept = 999
let s:current_seed = 0
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
    let s:enabled = s:get('enabled')

    augroup FimOllama
        autocmd!
        if s:enabled
            autocmd InsertCharPre * call fim_ollama#core#on_insert_char()
            autocmd TextChangedI  * call fim_ollama#core#on_text_changed()
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

" Called when a character is about to be inserted.
function! fim_ollama#core#on_insert_char() abort
    let s:chars_since_accept += 1
endfunction

" Called after buffer text changed in insert mode.
function! fim_ollama#core#on_text_changed() abort
    call fim_ollama#core#schedule_request()
endfunction

function! fim_ollama#core#schedule_request() abort
    if !s:enabled | return | endif

    " After accepting a suggestion, suppress ALL requests for a short time
    " AND until at least 3 genuine keystrokes have been typed. This prevents
    " the model from immediately repeating the same suggestion because the
    " context barely changed.
    if s:accept_lock | return | endif
    if s:chars_since_accept < 3 | return | endif

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

    let s:current_seed += 1

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
        \ 'seed': s:current_seed,
        \ 'raw': fim_ollama#prompt#requires_raw(l:model_type),
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

    " Reject the suggestion if it's identical to the one we just accepted
    " OR if it starts with what we already accepted (prevents the model
    " from offering the same prefix again, especially for comments).
    if !empty(s:last_accepted_text)
        if a:text ==# s:last_accepted_text
            return
        endif
        if stridx(a:text, s:last_accepted_text) == 0
            return
        endif
    endif

    " Strip any text that the model echoed back from the current line prefix.
    " Some FIM models return the full line including what's already typed;
    " we only want to show the genuinely new completion part.
    let l:text = a:text
    let l:line_prefix = strpart(getline('.'), 0, a:col - 1)
    if !empty(l:line_prefix) && stridx(l:text, l:line_prefix) == 0 && len(l:text) > len(l:line_prefix)
        let l:text = strpart(l:text, len(l:line_prefix))
        if empty(trim(l:text, " \t\n\r"))
            return
        endif
    endif

    call fim_ollama#ui#show(a:bufnr, a:line, a:col, l:text)
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

    " Remember what we accepted so we can reject identical re-suggestions.
    let s:last_accepted_text = l:text

    " Lock down: prevent ANY requests from firing. The lock is released
    " by a timer after the immediate TextChangedI/InsertCharPre events
    " from the insertion have settled. This is more reliable than
    " clearing the lock on InsertCharPre because InsertCharPre may also
    " fire for the returned text itself in some Vim versions.
    let s:accept_lock = 1
    let s:chars_since_accept = 0
    call fim_ollama#core#cancel_debounce()
    call fim_ollama#client#cancel()
    call fim_ollama#ui#hide()

    " Release the lock after 800ms. This is long enough for the
    " TextChangedI from the accepted text to settle, but short enough
    " that the user can still get a fresh suggestion after typing a few
    " characters.
    call timer_start(800, function('s:release_accept_lock'))

    " Insert the completion text at cursor.
    return l:text
endfunction

function! s:release_accept_lock(timer_id) abort
    let s:accept_lock = 0
endfunction

" Dismiss the current suggestion and cancel any pending request.
function! fim_ollama#core#dismiss() abort
    let s:last_accepted_text = ''
    call fim_ollama#ui#hide()
    call fim_ollama#client#cancel()
    call fim_ollama#core#cancel_debounce()
endfunction

" Request a fresh alternative suggestion at the current cursor position.
function! fim_ollama#core#next_suggestion() abort
    if !fim_ollama#ui#is_visible()
        return
    endif

    let l:cur = getcurpos()
    let l:line = l:cur[1]
    let l:col = l:cur[2]
    let l:bufnr = bufnr('%')

    let s:current_seed += 1

    let l:prefix = s:get_prefix(l:bufnr, l:line, l:col)
    let l:suffix = s:get_suffix(l:bufnr, l:line, l:col)

    let l:model_type = s:get('model_type')
    let l:prompt = fim_ollama#prompt#build_fim_prompt(l:prefix, l:suffix, l:model_type)
    let l:stop_tokens = fim_ollama#prompt#all_stop_tokens(l:model_type)

    let s:request_counter += 1
    let l:request_id = s:request_counter

    let l:config = {
        \ 'url': s:get('api_url'),
        \ 'model': s:get('model'),
        \ 'prompt': l:prompt,
        \ 'stop_tokens': l:stop_tokens,
        \ 'max_tokens': s:get('max_tokens'),
        \ 'temperature': 0.7,
        \ 'seed': s:current_seed,
        \ 'raw': fim_ollama#prompt#requires_raw(l:model_type),
        \ }

    call fim_ollama#client#cancel()
    call fim_ollama#core#cancel_debounce()

    call fim_ollama#client#request(l:request_id, l:config, function('s:on_next_suggestion_completion', [l:request_id, l:bufnr, l:line, l:col]))
endfunction

function! s:on_next_suggestion_completion(request_id, bufnr, line, col, returned_request_id, text) abort
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

function! fim_ollama#core#cleanup() abort
    let s:accept_lock = 0
    let s:last_accepted_text = ''
    let s:chars_since_accept = 999
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
