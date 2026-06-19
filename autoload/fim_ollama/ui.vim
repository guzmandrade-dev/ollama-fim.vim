" Ghost text UI: render inline suggestions and handle accept/dismiss.
" Uses textprop on Vim 9+; falls back to a popup/preview window on older Vim.

let s:ghost_text = ''
let s:ghost_bufnr = -1
let s:ghost_prop_type = 'FimOllamaGhostText'
let s:ghost_prop_id = -1
let s:has_textprop = has('textprop')

" Initialize textprop type if available.
function! fim_ollama#ui#init() abort
    if s:has_textprop
        try
            call prop_type_add(s:ghost_prop_type, {
                \ 'highlight': 'Comment',
                \ 'priority': 100,
                \ 'combine': v:true,
                \ })
        catch /^Vim(err):/
            " Type may already exist on reload.
        endtry
    endif
endfunction

function! fim_ollama#ui#show(bufnr, line, col, text) abort
    call fim_ollama#ui#hide(a:bufnr)

    let s:ghost_text = a:text
    let s:ghost_bufnr = a:bufnr

    if s:has_textprop && a:bufnr == bufnr('%')
        call s:show_textprop(a:line, a:col, a:text)
    else
        call s:show_fallback(a:text)
    endif
endfunction

function! s:show_textprop(line, col, text) abort
    let l:opts = {
        \ 'type': s:ghost_prop_type,
        \ 'text': a:text,
        \ }

    " text_wrap was added in Vim 9.
    if has('patch-9.0.0321')
        let l:opts.text_wrap = 'wrap'
    endif

    try
        let s:ghost_prop_id = prop_add(a:line, a:col, l:opts)
    catch
        " If textprop fails (e.g., unsupported column), fall back silently.
        let s:ghost_prop_id = -1
        call s:show_fallback(a:text)
    endtry
endfunction

function! s:show_fallback(text) abort
    " Minimal fallback: show suggestion in a small popup near cursor.
    if exists('*popup_atcursor')
        let s:ghost_popup_id = popup_atcursor(split(a:text, "\n"), {
            \ 'highlight': 'Comment',
            \ 'padding': [0, 1, 0, 1],
            \ 'border': [],
            \ 'moved': 'any',
            \ })
    endif
endfunction

function! fim_ollama#ui#hide(...) abort
    let l:bufnr = a:0 >= 1 ? a:1 : s:ghost_bufnr

    if s:ghost_prop_id >= 0 && s:has_textprop
        try
            if exists('*prop_id_exists')
                if prop_id_exists(s:ghost_prop_id, l:bufnr)
                    call prop_remove({ 'id': s:ghost_prop_id, 'bufnr': l:bufnr })
                endif
            else
                " Vim 8: just try to remove and ignore errors.
                call prop_remove({ 'id': s:ghost_prop_id, 'bufnr': l:bufnr })
            endif
        catch
        endtry
    endif

    if exists('s:ghost_popup_id') && s:ghost_popup_id > 0
        try
            call popup_close(s:ghost_popup_id)
        catch
        endtry
        unlet s:ghost_popup_id
    endif

    let s:ghost_text = ''
    let s:ghost_prop_id = -1
endfunction

function! fim_ollama#ui#accept() abort
    if empty(s:ghost_text)
        return ''
    endif

    let l:text = s:ghost_text
    call fim_ollama#ui#hide()
    return l:text
endfunction

function! fim_ollama#ui#dismiss() abort
    call fim_ollama#ui#hide()
endfunction

function! fim_ollama#ui#is_visible() abort
    return !empty(s:ghost_text)
endfunction

function! fim_ollama#ui#get_ghost_text() abort
    return s:ghost_text
endfunction
