" Logical truncation of FIM completion responses.
" Cuts a model's suggestion down to the next short, self-contained step so
" ghost text feels like a single next action rather than a long multi-line
" continuation.
"
" Strategy: scan the suggestion left to right and stop at the first character
" that looks like a natural boundary.  We intentionally keep this simple and
" fast because it runs frequently (after every debounce).
"
" Primary boundaries (highest priority, cut AFTER the character):
"   ;  statement terminator
"   \n end of line
"
" Secondary boundaries (only if no primary boundary exists):
"   )  ]  }  closing delimiters
"   >  closing angle (HTML/XML tags)
"
" Quote boundaries are treated as pairs: cut after the closing quote, unless
" another boundary immediately follows the closing quote.
"
" Public functions:
"   fim_ollama#complete#trim(text)

let s:primary_boundaries = [';', "\n"]
let s:secondary_boundaries = [')', ']', '}', '>']
let s:quote_boundaries = ['"', "'", '`']
let s:all_boundaries = s:primary_boundaries + s:secondary_boundaries

" Optional user override of the primary and secondary lists combined.
let s:default_boundaries = s:all_boundaries

function! fim_ollama#complete#get_boundaries() abort
    if exists('g:fim_ollama_complete_boundaries') && type(g:fim_ollama_complete_boundaries) == v:t_list
        return g:fim_ollama_complete_boundaries
    endif
    return s:default_boundaries
endfunction

" Trim a completion to the first logical stopping point.
function! fim_ollama#complete#trim(text) abort
    if empty(a:text)
        return a:text
    endif

    " Models sometimes emit a leading newline when they want to start a new
    " line.  Preserve that newline, then trim the rest.
    let l:leading_newlines = matchstr(a:text, '^\n\+')
    let l:rest = strpart(a:text, len(l:leading_newlines))

    " Strip obvious trailing noise first.
    let l:rest = s:strip_trailing_noise(l:rest)

    let l:cut = s:find_first_boundary(l:rest)

    if l:cut < 0
        let l:result = l:rest
    else
        let l:result = strpart(l:rest, 0, l:cut + 1)
    endif

    let l:result = s:strip_trailing_noise(l:result)

    " Don't return only whitespace.
    if empty(trim(l:result)) && empty(l:leading_newlines)
        return a:text
    endif

    return l:leading_newlines . l:result
endfunction

" ---------------------------------------------------------------------------
" Internal helpers
" ---------------------------------------------------------------------------

" Remove trailing markdown fences, trailing whitespace, and trailing newlines.
function! s:strip_trailing_noise(text) abort
    let l:text = substitute(a:text, '\(\n\|^\)```\s*$', '', '')
    let l:text = substitute(l:text, '[ \t]\+$', '', '')
    let l:text = substitute(l:text, '\n\+$', '', '')
    return l:text
endfunction

" Find the first boundary index.  Primary boundaries take precedence; we only
" fall back to secondary boundaries when there is no primary boundary at all.
" Quote pairs are considered alongside the current priority level, but if a
" boundary immediately follows the closing quote we prefer the boundary.
function! s:find_first_boundary(text) abort
    let l:primary = s:find_min_boundary(a:text, s:primary_boundaries)
    let l:quote = s:find_first_quote_pair(a:text)

    if l:primary >= 0
        if l:quote >= 0 && l:quote < l:primary
            let l:after_boundary = s:boundary_after(a:text, l:quote)
            if l:after_boundary >= 0
                return l:after_boundary
            endif
            return l:quote
        endif
        return l:primary
    endif

    if l:quote >= 0
        let l:after_boundary = s:boundary_after(a:text, l:quote)
        if l:after_boundary >= 0
            return l:after_boundary
        endif
        return l:quote
    endif

    return s:find_min_boundary(a:text, s:secondary_boundaries)
endfunction

" If a boundary character immediately follows `pos`, return its index.
function! s:boundary_after(text, pos) abort
    let l:next = a:pos + 1
    if l:next >= len(a:text)
        return -1
    endif
    let l:ch = strpart(a:text, l:next, 1)
    if index(s:all_boundaries, l:ch) >= 0
        return l:next
    endif
    return -1
endfunction

" Return the smallest index of any boundary in list, or -1.
function! s:find_min_boundary(text, boundaries) abort
    let l:min = -1
    for l:boundary in a:boundaries
        let l:idx = stridx(a:text, l:boundary)
        if l:idx >= 0 && (l:min < 0 || l:idx < l:min)
            let l:min = l:idx
        endif
    endfor
    return l:min
endfunction

" Return the index of the earliest closing quote (i.e. the end of the first
" complete quote pair), or -1 if no complete pair exists.
function! s:find_first_quote_pair(text) abort
    let l:min = -1
    for l:quote in s:quote_boundaries
        let l:start = stridx(a:text, l:quote)
        if l:start < 0
            continue
        endif
        let l:close = stridx(a:text, l:quote, l:start + 1)
        if l:close < 0
            continue
        endif
        if l:min < 0 || l:close < l:min
            let l:min = l:close
        endif
    endfor
    return l:min
endfunction
