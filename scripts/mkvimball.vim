" Build the vimball build/ollama-fim-<version>.vmb from the runtime files.
" Version comes from $VERSION.  Run from the repo root:
"   VERSION=1.4.0 vim -u NONE -N -n -es -c 'source scripts/mkvimball.vim' -c 'quit'

source scripts/release_files.vim

let s:version = $VERSION
if empty(s:version)
    let s:version = '0.0.0'
endif

call mkdir('build', 'p')
let s:vmb = 'build/ollama-fim-' . s:version . '.vmb'

" Vimball header.
call writefile([
    \ '" Vimball Archiver by GitHub Action',
    \ 'UseVimball',
    \ 'finish',
    \ ], s:vmb)

" Append each file as a vimball record: path, line count, content.
for s:f in ReleaseFiles()
    let s:content = readfile(s:f)
    call writefile([s:f, len(s:content)] + s:content, s:vmb, 'a')
endfor

call writefile(['Built ' . s:vmb . ' (' . len(ReleaseFiles()) . ' files)'], 'build/.dist-log.txt')
