" Async ctags-based symbol extraction for richer FIM context.
" Enabled only when g:fim_ollama_use_ctags is set and Universal Ctags is
" available. All operations fall back to the existing regex-based context
" if ctags is missing or returns no useful tags.

let s:ctags_checked = 0
let s:ctags_available = 0

" Kinds we consider useful for code-completion context. Variables are
" intentionally excluded to keep the context compact.
let s:useful_kinds = ['c', 'd', 'e', 'f', 'g', 'i', 'm', 'n', 'p', 's', 't', 'u']

" ---------------------------------------------------------------------------
" Feature detection
" ---------------------------------------------------------------------------

function! fim_ollama#tags#is_available() abort
    if s:ctags_checked
        return s:ctags_available
    endif

    let s:ctags_checked = 1

    if !executable('ctags')
        return 0
    endif

    let l:version_output = system('ctags --version')
    if v:shell_error != 0 || l:version_output !~# 'Universal Ctags'
        return 0
    endif

    " Sanity-check: ctags must accept the flags we plan to use.
    let l:tmp = tempname() . '.c'
    call writefile(['void dummy(void) {}'], l:tmp)
    let l:test = system('ctags -f - --excmd=number --fields=+S+n --sort=no ' . shellescape(l:tmp))
    call delete(l:tmp)
    if v:shell_error != 0
        return 0
    endif

    let s:ctags_available = 1
    return 1
endfunction

" ---------------------------------------------------------------------------
" Public API
" ---------------------------------------------------------------------------

function! fim_ollama#tags#enabled() abort
    return get(g:, 'fim_ollama_use_ctags', 0) && fim_ollama#tags#is_available()
endfunction

" Refresh the tag cache for a buffer. Safe to call repeatedly.
function! fim_ollama#tags#refresh(bufnr) abort
    if !fim_ollama#tags#enabled()
        return
    endif

    let l:bufname = bufname(a:bufnr)
    if empty(l:bufname) || !filereadable(l:bufname)
        return
    endif

    " Build command as a list to avoid shell quoting issues on all platforms.
    let l:cmd = ['ctags', '-f', '-', '--excmd=number', '--fields=+S+n', '--sort=no', l:bufname]

    call setbufvar(a:bufnr, 'fim_ollama_ctags_pending', 1)

    if has('job')
        let l:jobopts = {
            \ 'out_mode': 'raw',
            \ 'err_mode': 'raw',
            \ 'callback': function('s:job_output', [a:bufnr]),
            \ 'close_cb': function('s:job_close', [a:bufnr]),
            \ }
        call job_start(l:cmd, l:jobopts)
    else
        " Synchronous fallback for old Vim.
        let l:output = system(join(l:cmd, ' '))
        call s:store_tags(a:bufnr, l:output)
    endif
endfunction

" Return 1 if the buffer has a non-empty tag cache.
function! fim_ollama#tags#has_cache(bufnr) abort
    let l:cache = getbufvar(a:bufnr, 'fim_ollama_tags')
    return type(l:cache) == v:t_list && !empty(l:cache)
endfunction

" Build a scope stack (e.g. "class Foo > method bar") for the cursor line.
function! fim_ollama#tags#scope_stack(bufnr, cursor_line) abort
    if !fim_ollama#tags#has_cache(a:bufnr)
        return ''
    endif

    let l:tags = getbufvar(a:bufnr, 'fim_ollama_tags')
    let l:stack = []
    let l:enclosing = s:find_enclosing_tags(l:tags, a:cursor_line)

    for l:tag in l:enclosing
        call add(l:stack, s:kind_name(l:tag.kind) . ' ' . l:tag.name . s:format_signature(l:tag))
    endfor

    return join(l:stack, ' > ')
endfunction

" Build a compact symbols context string for the prompt.
function! fim_ollama#tags#symbols_context(bufnr, cursor_line, max_chars) abort
    if !fim_ollama#tags#has_cache(a:bufnr)
        return ''
    endif

    let l:tags = getbufvar(a:bufnr, 'fim_ollama_tags')
    let l:max = a:max_chars > 0 ? a:max_chars : 200

    " Prefer enclosing tags, then the previous few definitions before cursor.
    let l:enclosing = s:find_enclosing_tags(l:tags, a:cursor_line)
    let l:preceding = s:find_preceding_tags(l:tags, a:cursor_line, 5, l:enclosing)
    let l:selected = l:enclosing + l:preceding

    if empty(l:selected)
        return ''
    endif

    let l:lines = []
    let l:seen = {}
    let l:total = 0

    for l:tag in l:selected
        if has_key(l:seen, l:tag.name)
            continue
        endif
        let l:line = '  ' . s:kind_name(l:tag.kind) . ' ' . l:tag.name . s:format_signature(l:tag)
        let l:len = len(l:line)
        if l:total + l:len > l:max
            break
        endif
        let l:seen[l:tag.name] = 1
        call add(l:lines, l:line)
        let l:total += l:len + 1
    endfor

    if empty(l:lines)
        return ''
    endif

    return "// Symbols:\n" . join(l:lines, "\n") . "\n"
endfunction

" ---------------------------------------------------------------------------
" Job handling
" ---------------------------------------------------------------------------

let s:job_output_buffer = {}

function! s:job_output(bufnr, ch, msg) abort
    let l:key = string(a:bufnr)
    if !has_key(s:job_output_buffer, l:key)
        let s:job_output_buffer[l:key] = ''
    endif
    let s:job_output_buffer[l:key] .= a:msg
endfunction

function! s:job_close(bufnr, ch) abort
    let l:key = string(a:bufnr)
    let l:output = get(s:job_output_buffer, l:key, '')
    unlet! s:job_output_buffer[l:key]
    call s:store_tags(a:bufnr, l:output)
endfunction

function! s:store_tags(bufnr, output) abort
    let l:tags = s:parse_output(a:output)
    call setbufvar(a:bufnr, 'fim_ollama_tags', l:tags)
    call setbufvar(a:bufnr, 'fim_ollama_ctags_pending', 0)
endfunction

" ---------------------------------------------------------------------------
" Parsing
" ---------------------------------------------------------------------------

function! s:parse_output(output) abort
    let l:tags = []

    for l:line in split(a:output, '\r\?\n')
        if empty(l:line) || l:line[0] ==# '!'
            continue
        endif

        let l:fields = split(l:line, "\t")
        if len(l:fields) < 3
            continue
        endif

        let l:name = l:fields[0]
        let l:cmd = l:fields[2]
        let l:line_no = s:extract_line_number(l:cmd)
        if l:line_no <= 0
            continue
        endif

        let l:kind = ''
        let l:signature = ''

        for l:i in range(3, len(l:fields) - 1)
            let l:field = l:fields[l:i]
            if l:field =~# '^kind:'
                let l:kind = substitute(l:field, '^kind:', '', '')
            elseif l:field =~# '^signature:'
                let l:signature = substitute(l:field, '^signature:', '', '')
            endif
        endfor

        if !empty(l:kind) && index(s:useful_kinds, l:kind) < 0
            continue
        endif

        call add(l:tags, {
            \ 'name': l:name,
            \ 'line': l:line_no,
            \ 'kind': l:kind,
            \ 'signature': l:signature,
            \ })
    endfor

    return l:tags
endfunction

function! s:extract_line_number(cmd) abort
    " With --excmd=number, the cmd field is just a line number, optionally
    " followed by ;".
    let l:match = matchstr(a:cmd, '^\d\+')
    if !empty(l:match)
        return str2nr(l:match)
    endif
    return 0
endfunction

" ---------------------------------------------------------------------------
" Tag selection helpers
" ---------------------------------------------------------------------------

function! s:find_enclosing_tags(tags, cursor_line) abort
    let l:container = {}
    let l:function = {}

    for l:tag in a:tags
        if l:tag.line > a:cursor_line
            break
        endif

        if s:is_container(l:tag.kind)
            let l:container = l:tag
            let l:function = {}
        elseif s:is_function_like(l:tag.kind)
            let l:function = l:tag
        endif
    endfor

    let l:result = []
    if !empty(l:container)
        call add(l:result, l:container)
    endif
    if !empty(l:function)
        call add(l:result, l:function)
    endif
    return l:result
endfunction

function! s:find_preceding_tags(tags, cursor_line, count, exclude) abort
    let l:exclude_names = {}
    for l:t in a:exclude
        let l:exclude_names[l:t.name] = 1
    endfor

    let l:result = []

    for l:i in range(len(a:tags) - 1, 0, -1)
        let l:tag = a:tags[l:i]
        if l:tag.line >= a:cursor_line
            continue
        endif
        if has_key(l:exclude_names, l:tag.name)
            continue
        endif
        if s:is_function_like(l:tag.kind) || s:is_container(l:tag.kind)
            call insert(l:result, l:tag, 0)
            if len(l:result) >= a:count
                break
            endif
        endif
    endfor

    return l:result
endfunction

function! s:is_container(kind) abort
    return index(['c', 's', 'i', 't', 'u', 'g', 'n'], a:kind) >= 0
endfunction

function! s:is_function_like(kind) abort
    return index(['f', 'm', 'p'], a:kind) >= 0
endfunction

" ---------------------------------------------------------------------------
" Formatting
" ---------------------------------------------------------------------------

function! s:format_signature(tag) abort
    if empty(a:tag.signature)
        return ''
    endif
    let l:sig = substitute(a:tag.signature, '^\s*', '', '')
    let l:sig = substitute(l:sig, '\n\+\s*$', '', '')
    return l:sig
endfunction

function! s:kind_name(kind) abort
    let l:names = {
        \ 'c': 'class',
        \ 'd': 'define',
        \ 'e': 'enum',
        \ 'f': 'function',
        \ 'g': 'enum',
        \ 'i': 'interface',
        \ 'm': 'method',
        \ 'n': 'namespace',
        \ 'p': 'property',
        \ 's': 'struct',
        \ 't': 'type',
        \ 'u': 'union',
        \ }
    return get(l:names, a:kind, a:kind)
endfunction
