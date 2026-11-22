" Tests for full and partial (word-by-word) accept, driving the real UI and
" core functions headlessly (popup_atcursor works under `vim -es`).

function! s:fresh_buffer() abort
    enew!
    call setline(1, ['let x = '])
    call cursor(1, 8)
    call fim_ollama#core#cleanup()
endfunction

function! s:t_full_accept() abort
    call s:fresh_buffer()
    call fim_ollama#ui#show(bufnr('%'), 1, 8, 'foo bar')
    call assert_true(fim_ollama#ui#is_visible())
    let l:text = fim_ollama#core#accept()
    call assert_equal('foo bar', l:text)
    call assert_false(fim_ollama#ui#is_visible())
    call assert_equal('', fim_ollama#ui#get_ghost_text())
endfunction

function! s:t_passthrough_when_no_suggestion() abort
    call s:fresh_buffer()
    call assert_equal("\<C-Right>", fim_ollama#core#accept_word())
    call assert_equal("\<Tab>", fim_ollama#core#accept())
endfunction

function! s:t_accept_word_chunks() abort
    call s:fresh_buffer()
    call fim_ollama#ui#show(bufnr('%'), 1, 8, 'foo bar baz')

    let l:chunk = fim_ollama#core#accept_word()
    call assert_equal('foo', l:chunk)
    " Popup is hidden until the cursor-move event re-shows the remainder.
    call assert_false(fim_ollama#ui#is_visible())

    " Simulate the CursorMovedI that fires after the inserted chunk.
    call cursor(1, 11)
    call fim_ollama#core#dismiss_if_moved()
    call assert_true(fim_ollama#ui#is_visible())
    call assert_equal(' bar baz', fim_ollama#ui#get_ghost_text())

    let l:chunk = fim_ollama#core#accept_word()
    call assert_equal(' bar', l:chunk)
    call cursor(1, 15)
    call fim_ollama#core#dismiss_if_moved()
    call assert_equal(' baz', fim_ollama#ui#get_ghost_text())

    let l:chunk = fim_ollama#core#accept_word()
    call assert_equal(' baz', l:chunk)
    call fim_ollama#core#dismiss_if_moved()
    " Remainder exhausted: stays dismissed.
    call assert_false(fim_ollama#ui#is_visible())
endfunction

function! s:t_accept_word_punctuation() abort
    call s:fresh_buffer()
    call fim_ollama#ui#show(bufnr('%'), 1, 8, '.getName()')
    call assert_equal('.', fim_ollama#core#accept_word())
    call fim_ollama#core#dismiss_if_moved()
    call assert_equal('getName()', fim_ollama#ui#get_ghost_text())
endfunction

function! s:t_accept_word_multiline() abort
    call s:fresh_buffer()
    call fim_ollama#ui#show(bufnr('%'), 1, 8, "\n    doThing();")
    call assert_equal("\n", fim_ollama#core#accept_word())
    call fim_ollama#core#dismiss_if_moved()
    call assert_equal('    doThing();', fim_ollama#ui#get_ghost_text())
endfunction

function! s:t_pending_remainder_cleared_on_dismiss() abort
    call s:fresh_buffer()
    call fim_ollama#ui#show(bufnr('%'), 1, 8, 'foo bar')
    call assert_equal('foo', fim_ollama#core#accept_word())
    call fim_ollama#core#dismiss()
    " A later cursor move must not resurrect the stale remainder.
    call fim_ollama#core#dismiss_if_moved()
    call assert_false(fim_ollama#ui#is_visible())
endfunction

function! s:t_pending_remainder_not_overriding_fresh_suggestion() abort
    call s:fresh_buffer()
    call fim_ollama#ui#show(bufnr('%'), 1, 8, 'foo bar')
    call assert_equal('foo', fim_ollama#core#accept_word())
    " A new suggestion arrives before the cursor-move event: it wins.
    call fim_ollama#ui#show(bufnr('%'), 1, 11, 'something else')
    call fim_ollama#core#dismiss_if_moved()
    call assert_equal('something else', fim_ollama#ui#get_ghost_text())
endfunction

call RegisterTest('accept: full accept', function('s:t_full_accept'))
call RegisterTest('accept: key passthrough when empty', function('s:t_passthrough_when_no_suggestion'))
call RegisterTest('accept_word: chunks word by word', function('s:t_accept_word_chunks'))
call RegisterTest('accept_word: punctuation one symbol at a time', function('s:t_accept_word_punctuation'))
call RegisterTest('accept_word: multiline remainder', function('s:t_accept_word_multiline'))
call RegisterTest('accept_word: dismiss clears pending remainder', function('s:t_pending_remainder_cleared_on_dismiss'))
call RegisterTest('accept_word: fresh suggestion wins over pending', function('s:t_pending_remainder_not_overriding_fresh_suggestion'))
