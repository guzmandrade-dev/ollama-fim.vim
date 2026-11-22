" Minimal vimrc for running the test suite headlessly:
"   vim -Nu tests/minimal.vim -n -es -S tests/run_tests.vim
set noswapfile
" Load the plugin from the repo root, but keep it disabled so no autocmds
" or network requests fire during tests; tests call functions directly.
let g:fim_ollama_enabled = 0
let &runtimepath = expand('<sfile>:p:h:h') . ',' . &runtimepath
set loadplugins
