" Headless test runner.  Sources every tests/test_*.vim file; each registers
" tests with RegisterTest(name, Funcref).  Assert failures land in v:errors
" and are attributed to the running test.  Results are written to
" test_results.txt in the working directory; exits nonzero on any failure.

let g:__tests = []

function! RegisterTest(name, Fn) abort
    call add(g:__tests, [a:name, a:Fn])
endfunction

let s:dir = expand('<sfile>:p:h')
for s:file in sort(glob(s:dir . '/test_*.vim', 0, 1))
    execute 'source' fnameescape(s:file)
endfor

let s:passed = 0
let s:failed = 0
let s:results = []

for [s:name, s:Fn] in g:__tests
    let s:before = len(v:errors)
    try
        call s:Fn()
    catch
        call add(v:errors, s:name . ' threw: ' . v:exception . ' @ ' . v:throwpoint)
    endtry
    if len(v:errors) > s:before
        let s:failed += 1
        call add(s:results, 'FAIL ' . s:name)
        call extend(s:results, map(copy(v:errors[s:before :]), '"    " . v:val'))
    else
        let s:passed += 1
        call add(s:results, 'PASS ' . s:name)
    endif
endfor

call add(s:results, printf('== %d passed, %d failed ==', s:passed, s:failed))
call writefile(s:results, 'test_results.txt')

if s:failed > 0
    cquit
endif
qa!
