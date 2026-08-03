" Logical truncation of FIM completion responses.
" Cuts a model's suggestion down to the next short, self-contained step so
" ghost text feels like a single next action rather than a long multi-line
" continuation.
"
" Strategy:
"   1. Balance cheap structural delimiters ( (), [], {} ) across the whole
"      suggestion.  We stop at the first point where the stack becomes empty
"      AND the next non-whitespace character is a primary boundary (statement
"      terminator or newline) or end of text.  If another opener appears
"      before that, we keep going.
"   2. If the suggestion is already balanced, fall back to simple boundary
"      characters: ; \n ) ] } > and quote pairs.
"   3. If balancing fails (unmatched openers), return the original text so
"      we don't break the experience.
"
" This is intentionally simple and fast: one left-to-right pass.
"
" Public functions:
"   fim_ollama#complete#trim(text)

let s:balance_pairs = { '(': ')', '[': ']', '{': '}' }
let s:quote_boundaries = ['"', "'", '`']
let s:primary_boundaries = [';', "\n"]
let s:secondary_boundaries = [')', ']', '}', '>']
let s:all_boundaries = s:primary_boundaries + s:secondary_boundaries

function! fim_ollama#complete#get_boundaries() abort
    return s:all_boundaries
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

" Find the first safe boundary.  Prefer balanced structure, then primary
" boundaries, then quote pairs, then secondary boundaries.
function! s:find_first_boundary(text) abort
    " 1. Structural balance: stop at the first point where the suggestion is
    "    structurally empty and the next token is a statement terminator or
    "    newline.
    let l:balance_cut = s:find_balance_cut(a:text)
    if l:balance_cut >= 0
        return l:balance_cut
    endif

    " 2. Primary boundaries.
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

    " 3. Secondary boundaries only when no primary boundary exists.
    return s:find_min_boundary(a:text, s:secondary_boundaries)
endfunction

" Scan text and return the index at which to cut.  We stop when the structural
" stack first becomes empty and the next non-whitespace character is a primary
" boundary or end of text.  If another opener appears before that, we keep
" going.  Returns -1 if the suggestion is unbalanced or already empty.
function! s:find_balance_cut(text) abort
    let l:len = len(a:text)
    let l:i = 0
    let l:stack = []

    while l:i < l:len
        let l:ch = strpart(a:text, l:i, 1)

        if has_key(s:balance_pairs, l:ch)
            call add(l:stack, s:balance_pairs[l:ch])
        elseif !empty(l:stack) && l:ch ==# l:stack[-1]
            call remove(l:stack, -1)
            if empty(l:stack)
                " We just closed the first still-open pair.  Look ahead to see
                " if this is a good place to cut.
                let l:next_idx = s:skip_whitespace(a:text, l:i + 1)
                if l:next_idx >= l:len
                    " End of suggestion: cut here.
                    return l:i
                endif
                let l:next_ch = strpart(a:text, l:next_idx, 1)
                if index(s:primary_boundaries, l:next_ch) >= 0
                    return l:next_idx
                endif
                " Not a stopping point; keep scanning.
            endif
        elseif index(values(s:balance_pairs), l:ch) >= 0
            " A closer that doesn't match the top of the stack means the
            " suggestion is malformed; fall back to the simple path.
            return -1
        endif

        let l:i += 1
    endwhile

    " Unmatched openers or no good stopping point.
    return -1
endfunction

" Return the index of the next non-whitespace character, or len(text).
function! s:skip_whitespace(text, start) abort
    let l:len = len(a:text)
    let l:i = a:start
    while l:i < l:len
        let l:ch = strpart(a:text, l:i, 1)
        if l:ch !=# ' ' && l:ch !=# "\t"
            return l:i
        endif
        let l:i += 1
    endwhile
    return l:len
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
