" Indentation normalization for completion text.
" Converts leading whitespace in completion strings to match the current
" buffer's tab/space settings.

" Return the current buffer's indentation settings as a dict.
function! fim_ollama#indent#get_buffer_settings(...) abort
    let l:bufnr = a:0 >= 1 ? a:1 : bufnr('%')

    let l:expandtab = getbufvar(l:bufnr, '&expandtab')
    let l:tabstop = getbufvar(l:bufnr, '&tabstop')
    let l:shiftwidth = getbufvar(l:bufnr, '&shiftwidth')
    let l:softtabstop = getbufvar(l:bufnr, '&softtabstop')

    " If shiftwidth is 0, Vim uses tabstop for indent operations.
    let l:indent_size = l:shiftwidth > 0 ? l:shiftwidth : l:tabstop
    " softtabstop of 0 means fall back to shiftwidth or tabstop.
    let l:soft_size = l:softtabstop > 0 ? l:softtabstop : l:indent_size

    return {
        \ 'expandtab': !!l:expandtab,
        \ 'tabstop': max([l:tabstop, 1]),
        \ 'shiftwidth': l:indent_size,
        \ 'softtabstop': l:soft_size,
        \ }
endfunction

" Check whether normalization is enabled globally.
function! fim_ollama#indent#enabled() abort
    return !exists('g:fim_ollama_normalize_indent') || g:fim_ollama_normalize_indent
endfunction

" Normalize leading whitespace of each line in a:text according to the
" current buffer's indent settings.
"   - When expandtab is on, leading tabs are expanded to spaces based on
"     tabstop. Existing leading spaces are left as-is.
"   - When expandtab is off, leading spaces that are multiples of the
"     effective indent width are compressed into tabs; remaining spaces
"     are kept. Leading tabs are left as-is.
" Internal and trailing whitespace is never changed.
function! fim_ollama#indent#normalize_text(text, ...) abort
    if !fim_ollama#indent#enabled()
        return a:text
    endif

    let l:settings = a:0 >= 1 ? a:1 : fim_ollama#indent#get_buffer_settings()

    " Empty or single-line: still normalize that line.
    let l:lines = split(a:text, "\n", 1)
    let l:result = []

    for l:line in l:lines
        call add(l:result, s:normalize_line(l:line, l:settings))
    endfor

    return join(l:result, "\n")
endfunction

function! s:normalize_line(line, settings) abort
    let l:lead = matchstr(a:line, '^\s\+')
    let l:body = strpart(a:line, len(l:lead))

    if empty(l:lead)
        return a:line
    endif

    if a:settings.expandtab
        let l:lead = s:tabs_to_spaces(l:lead, a:settings.tabstop)
    else
        let l:lead = s:spaces_to_tabs(l:lead, a:settings.shiftwidth)
    endif

    return l:lead . l:body
endfunction

" Expand every tab character in leading whitespace to the visual column width
" it represents, given the current tabstop. We process the leading string
" left-to-right so each tab advances the column to the next multiple of
" tabstop.
function! s:tabs_to_spaces(lead, tabstop) abort
    let l:col = 0
    let l:out = ''
    for l:i in range(len(a:lead))
        let l:ch = strpart(a:lead, l:i, 1)
        if l:ch ==# "\t"
            let l:spaces = a:tabstop - (l:col % a:tabstop)
            let l:out .= repeat(' ', l:spaces)
            let l:col += l:spaces
        else
            let l:out .= l:ch
            let l:col += 1
        endif
    endfor
    return l:out
endfunction

" Convert leading spaces into tabs where they align to the indent width.
" Any leftover spaces (remainder) are kept at the end. Tabs already present
" are treated as already-aligned indent atoms of width indent_width columns.
function! s:spaces_to_tabs(lead, indent_width) abort
    " First pass: compute the visual column and build a string of tabs/spaces.
    let l:col = 0
    let l:out = ''
    for l:i in range(len(a:lead))
        let l:ch = strpart(a:lead, l:i, 1)
        if l:ch ==# "\t"
            let l:out .= "\t"
            let l:col += a:indent_width - (l:col % a:indent_width)
        elseif l:ch ==# ' '
            let l:out .= ' '
            let l:col += 1
        else
            " Other whitespace (rare) is preserved.
            let l:out .= l:ch
            let l:col += 1
        endif
    endfor

    " Second pass: turn runs of leading spaces that span whole indent units
    " into tabs. Tabs in the stream are treated as aligned indent atoms, so
    " any spaces before a tab are emitted as spaces, then the tab is emitted.
    let l:final = ''
    let l:space_count = 0
    for l:i in range(len(l:out))
        let l:ch = strpart(l:out, l:i, 1)
        if l:ch ==# ' '
            let l:space_count += 1
            if l:space_count >= a:indent_width
                let l:final .= "\t"
                let l:space_count = 0
            endif
        elseif l:ch ==# "\t"
            if l:space_count > 0
                let l:final .= repeat(' ', l:space_count)
                let l:space_count = 0
            endif
            let l:final .= "\t"
        else
            if l:space_count > 0
                let l:final .= repeat(' ', l:space_count)
                let l:space_count = 0
            endif
            let l:final .= l:ch
        endif
    endfor

    if l:space_count > 0
        let l:final .= repeat(' ', l:space_count)
    endif

    return l:final
endfunction
