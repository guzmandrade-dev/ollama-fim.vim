" Popup-only UI: render suggestions in a Vim popup and handle accept/dismiss.
" Uses popup_atcursor (floating window, never modifies the buffer).

let s:ghost_text = ''
let s:ghost_bufnr = -1

" Show a suggestion at the given cursor position.
function! fim_ollama#ui#show(bufnr, line, col, text) abort
    call fim_ollama#ui#hide(a:bufnr)

    let s:ghost_text = a:text
    let s:ghost_bufnr = a:bufnr

    call fim_ollama#client#log('UI show called: ' . strpart(a:text, 0, 80))

    if !exists('*popup_atcursor')
        call fim_ollama#client#log('UI popup_atcursor not available')
        return
    endif

    call s:show_popup(a:line, a:col, a:text)
endfunction

function! s:show_popup(line, col, text) abort
    let l:lines = split(a:text, "\n")
    let l:maxheight = min([len(l:lines), 10])
    let s:ghost_popup_id = popup_atcursor(l:lines, {
        \ 'highlight': 'Comment',
        \ 'padding': [0, 1, 0, 1],
        \ 'border': [],
        \ 'moved': 'any',
        \ 'maxheight': l:maxheight,
        \ })
    call fim_ollama#client#log('UI popup created id=' . s:ghost_popup_id)
endfunction

" Hide the current suggestion popup, if any.
function! fim_ollama#ui#hide(...) abort
    let l:bufnr = a:0 >= 1 ? a:1 : s:ghost_bufnr

    if exists('s:ghost_popup_id') && s:ghost_popup_id > 0
        try
            call popup_close(s:ghost_popup_id)
        catch
        endtry
        unlet s:ghost_popup_id
    endif

    let s:ghost_text = ''
endfunction

" Accept the visible suggestion and return its text for insertion.
function! fim_ollama#ui#accept() abort
    if empty(s:ghost_text)
        return ''
    endif

    let l:text = s:ghost_text
    call fim_ollama#ui#hide()
    return l:text
endfunction

" Dismiss the visible suggestion.
function! fim_ollama#ui#dismiss() abort
    call fim_ollama#ui#hide()
endfunction

" Check whether a suggestion is currently shown.
function! fim_ollama#ui#is_visible() abort
    return !empty(s:ghost_text)
endfunction

" Get the text of the visible suggestion.
function! fim_ollama#ui#get_ghost_text() abort
    return s:ghost_text
endfunction

