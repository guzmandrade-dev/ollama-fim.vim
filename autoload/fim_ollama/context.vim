" Minimal context extraction for FIM prompts.
" Provides stable prefix enrichment without fragile regex complexity.
" When ctags support is enabled, tag-derived symbols supplement (not
" replace) the existing regex-based extraction.

let s:default_max_context_chars = 3000
let s:symbols_context_ratio = 0.3

" ---------------------------------------------------------------------------
" Public API
" ---------------------------------------------------------------------------

function! fim_ollama#context#extract_file_context(bufnr, cursor_line, max_chars) abort
    let l:max_chars = a:max_chars > 0 ? a:max_chars : s:default_max_context_chars
    let l:symbols_max_chars = float2nr(round(l:max_chars * s:symbols_context_ratio))
    let l:lines_max_chars = l:max_chars - l:symbols_max_chars

    let l:symbols_context = s:get_symbols_context(a:bufnr, a:cursor_line, l:symbols_max_chars)
    let l:lines_context = s:get_lines_context(a:bufnr, a:cursor_line, l:lines_max_chars)

    let l:context = ''
    if !empty(l:symbols_context)
        let l:context .= l:symbols_context . "\n"
    endif
    let l:context .= l:lines_context

    return l:context
endfunction

function! fim_ollama#context#format_file_context(context, file_name, language_id) abort
    if empty(trim(a:context))
        return ''
    endif

    let l:ext = fnamemodify(a:file_name, ':e')
    if empty(l:ext)
        let l:ext = a:language_id
    endif

    return '<|file_context|>File: ' . a:file_name . "\n```" . l:ext . "\n" . a:context . "\n```<|end_file_context|>\n\n"
endfunction

function! fim_ollama#context#extract_current_scope(bufnr, cursor_line) abort
    " Prefer ctags-derived scope when available; fall back to regex.
    if get(g:, 'fim_ollama_use_ctags', 0) && fim_ollama#tags#has_cache(a:bufnr)
        let l:scope = fim_ollama#tags#scope_stack(a:bufnr, a:cursor_line)
        if !empty(l:scope)
            return l:scope
        endif
    endif

    " Walk backwards looking for class/def/fn/function/struct/trait/impl/module lines.
    let l:lines = getbufline(a:bufnr, 1, a:cursor_line)
    let l:scope_stack = []

    for l:i in range(len(l:lines) - 1, 0, -1)
        let l:line = l:lines[l:i]
        let l:m = matchlist(l:line, '\v^\s*(class|def|fn|func|function|struct|interface|trait|impl|module)\s+(\w+)')
        if !empty(l:m)
            call insert(l:scope_stack, l:m[1] . ' ' . l:m[2], 0)
            if len(l:scope_stack) >= 3
                break
            endif
        endif
    endfor

    return join(l:scope_stack, ' > ')
endfunction

" ---------------------------------------------------------------------------
" Internal helpers
" ---------------------------------------------------------------------------

function! s:get_symbols_context(bufnr, cursor_line, max_chars) abort
    if a:max_chars <= 0
        return ''
    endif
    if get(g:, 'fim_ollama_use_ctags', 0) && fim_ollama#tags#has_cache(a:bufnr)
        return fim_ollama#tags#symbols_context(a:bufnr, a:cursor_line, a:max_chars)
    endif
    return ''
endfunction

function! s:get_lines_context(bufnr, cursor_line, max_chars) abort
    let l:max_chars = a:max_chars > 0 ? a:max_chars : s:default_max_context_chars
    let l:all_lines = getbufline(a:bufnr, 1, a:cursor_line)
    let l:result = []

    " First pass: collect header/import-style lines from top of file.
    let l:first_count = min([20, len(l:all_lines)])
    for l:i in range(l:first_count)
        let l:line = l:all_lines[l:i]
        if l:line =~# '^\s*$' | continue | endif
        if l:line =~# '^\s*#'           | call add(l:result, l:line) | continue | endif
        if l:line =~# '^\s*import\s'  | call add(l:result, l:line) | continue | endif
        if l:line =~# '^\s*from\s'    | call add(l:result, l:line) | continue | endif
        if l:line =~# '^\s*use\s'     | call add(l:result, l:line) | continue | endif
        if l:line =~# '^\s*require\s' | call add(l:result, l:line) | continue | endif
        if l:line =~# '^\s*package\s' | call add(l:result, l:line) | continue | endif
        if l:line =~# '^\s*module\s' | call add(l:result, l:line) | continue | endif
        if l:line =~# '^\s*#include'  | call add(l:result, l:line) | continue | endif
        if l:line =~# '^\s*using\s'  | call add(l:result, l:line) | continue | endif
    endfor

    if !empty(l:result)
        call add(l:result, '')
    endif

    " Second pass: append the last ~50 lines before the cursor.
    let l:recent_start = max([0, a:cursor_line - 50])
    for l:i in range(l:recent_start, a:cursor_line - 1)
        call add(l:result, l:all_lines[l:i])
    endfor

    " Truncate from the end if too long, starting at a line boundary.
    let l:context = join(l:result, "\n")
    if len(l:context) > l:max_chars
        let l:context = strpart(l:context, len(l:context) - l:max_chars)
        let l:nl = stridx(l:context, "\n")
        if l:nl > 0
            let l:context = strpart(l:context, l:nl + 1)
        endif
    endif

    return l:context
endfunction
