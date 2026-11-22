" Single source of truth for the files shipped in release artifacts
" (vimball and zip).  Runtime files only: plugin/, autoload/, doc/,
" README, LICENSE.  Dev files (tests/, scripts/, AGENTS.md, Makefile,
" CI configs) are never shipped.
"
" Used by scripts/mkvimball.vim, scripts/dist.sh, and the release workflow.

function! ReleaseFiles() abort
    return sort(glob('plugin/*.vim', 0, 1)
        \ + glob('autoload/*/*.vim', 0, 1)
        \ + glob('doc/*.txt', 0, 1)
        \ + ['README.md', 'LICENSE'])
endfunction
