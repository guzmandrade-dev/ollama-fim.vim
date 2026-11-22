" Unit tests for fim_ollama#complete (pure string logic, no UI needed).

function! s:t_split_next_word() abort
    " Plain word.
    call assert_equal(['foo', ' bar baz'], fim_ollama#complete#split_next_word('foo bar baz'))
    " Leading whitespace is part of the next chunk.
    call assert_equal([' bar', ' baz'], fim_ollama#complete#split_next_word(' bar baz'))
    " Punctuation is consumed one symbol at a time.
    call assert_equal(['.', 'getName()'], fim_ollama#complete#split_next_word('.getName()'))
    call assert_equal(['  .', 'x'], fim_ollama#complete#split_next_word('  .x'))
    call assert_equal(['(', ')'], fim_ollama#complete#split_next_word('()'))
    " A newline is its own chunk and is never merged with a word.
    call assert_equal(["\n", 'foo'], fim_ollama#complete#split_next_word("\nfoo"))
    call assert_equal(["\n", "\nfoo"], fim_ollama#complete#split_next_word("\n\nfoo"))
    " Keyword characters include underscore.
    call assert_equal(['_private', ' = 1'], fim_ollama#complete#split_next_word('_private = 1'))
    " Whole suggestion when there is no boundary.
    call assert_equal(['foo', ''], fim_ollama#complete#split_next_word('foo'))
    " Only whitespace left.
    call assert_equal(['   ', ''], fim_ollama#complete#split_next_word('   '))
    " Empty input.
    call assert_equal(['', ''], fim_ollama#complete#split_next_word(''))
endfunction

function! s:t_split_reassembles() abort
    " Repeatedly splitting must reassemble the original suggestion exactly.
    for l:text in ['foo bar baz', '.getName().trim()', "\n    doThing();", 'a = (b + c);']
        let l:rest = l:text
        let l:joined = ''
        while !empty(l:rest)
            let [l:chunk, l:rest] = fim_ollama#complete#split_next_word(l:rest)
            let l:joined .= l:chunk
        endwhile
        call assert_equal(l:text, l:joined)
    endfor
endfunction

function! s:t_trim_regression() abort
    " Existing behaviour of trim() must not regress.
    call assert_equal('foo();', fim_ollama#complete#trim('foo();'))
    call assert_equal('', fim_ollama#complete#trim(''))
endfunction

call RegisterTest('complete#split_next_word', function('s:t_split_next_word'))
call RegisterTest('complete#split_next_word reassembles', function('s:t_split_reassembles'))
call RegisterTest('complete#trim regression', function('s:t_trim_regression'))
