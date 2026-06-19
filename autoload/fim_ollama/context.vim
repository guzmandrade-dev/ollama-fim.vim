" Extract file-level context and current scope for richer FIM prompts.
" Mirrors src/context.ts.

let s:max_context_lines = 50
let s:default_max_context_chars = 3000

let s:import_patterns = {
    \ 'javascript': '^import\s',
    \ 'typescript': '^import\s',
    \ 'python':     '^(import\s|from\s)',
    \ 'java':       '^import\s',
    \ 'go':         '^(import\s|package\s)',
    \ 'rust':       '^(use\s|extern\s|mod\s)',
    \ 'c':          '^#include',
    \ 'cpp':        '^#include',
    \ 'csharp':     '^using\s',
    \ 'php':        '^use\s',
    \ 'ruby':       '^require',
    \ }

" Common structural definition patterns.
let s:structural_patterns = [
    \ '^(class|interface|struct|enum|trait|type)\s',
    \ '^(public|private|protected|static|async|export|def|fn|func|function)\s',
    \ '^(const|let|var|val)\s\+\w\+\s*[:=]',
    \ '^\w\+\s*[=:]\s*(function|=\u003e|()',
    \ '^\s*@(Component|Service|Controller|Module|Injectable|Entity|Repository)',
    \ '^\s*(async\s\+)?(function\|def\|fn\|func)\s\+\w\+',
    \ ]

" Language-specific structural patterns.
let s:lang_structural_patterns = {
    \ 'python': [
        \ '^(class|def)\s',
        \ '^\s\+def\s\+\w\+\s*(',
        \ '^\w\+\s*:\s*(str\|int\|float\|bool\|list\|dict\|tuple\|Any\|Optional\|Union)\s*=',
        \ ],
    \ 'typescript': [
        \ '^(export\s\+)?(type\|interface\|class\|enum\|function\|const\|let\|var)\s\+\w\+',
        \ '^(export\s\+)?default\s\+',
        \ ],
    \ 'javascript': [
        \ '^(export\s\+)?(class\|function\|const\|let\|var)\s\+\w\+',
        \ '^(module\.)?exports\.',
        \ ],
    \ 'java': [
        \ '^(public\|private\|protected\|static\|final\|abstract)?\s*(class\|interface\|enum\|void\|int\|String\|boolean\|double\|float\|long\|short\|byte)\s\+\w\+',
        \ ],
    \ 'go': [
        \ '^(func\|type\|var\|const)\s',
        \ '^package\s',
        \ ],
    \ 'rust': [
        \ '^(fn\|struct\|enum\|trait\|impl\|type\|const\|static\|pub)\s',
        \ ],
    \ 'ruby': [
        \ '^(class\|module\|def)\s',
        \ ],
    \ }

" ---------------------------------------------------------------------------
" Public API
" ---------------------------------------------------------------------------

function! fim_ollama#context#extract_file_context(bufnr, cursor_line, max_chars) abort
    let l:max_chars = a:max_chars > 0 ? a:max_chars : s:default_max_context_chars
    let l:lines = getbufline(a:bufnr, 1, a:cursor_line)
    let l:lang = getbufvar(a:bufnr, '&filetype')

    let l:context_lines = []
    let l:import_pattern = get(s:import_patterns, l:lang, '')
    let l:in_import_block = v:false

    " Pass 1: capture imports and structural definitions.
    let l:i = 0
    while l:i < len(l:lines)
        let l:line = l:lines[l:i]
        let l:trimmed = trim(l:line)

        if empty(l:context_lines) && l:trimmed ==# ''
            let l:i += 1
            continue
        endif

        if l:import_pattern !=# '' && l:trimmed =~# l:import_pattern
            call add(l:context_lines, l:line)
            let l:in_import_block = v:true
            let l:i += 1
            continue
        endif

        if l:in_import_block
            call add(l:context_lines, l:line)
            if l:trimmed =~# ')' || (l:trimmed !~# '\\$' && l:trimmed !~# ',$')
                let l:in_import_block = v:false
            endif
            let l:i += 1
            continue
        endif

        if s:is_structural_definition(l:trimmed, l:lang)
            if empty(l:context_lines) || l:context_lines[-1] !=# l:line
                call add(l:context_lines, l:line)
            endif
        endif

        let l:i += 1
    endwhile

    " Pass 2: capture recent context lines (excluding immediate prefix duplicates).
    let l:recent_start = max([0, a:cursor_line - s:max_context_lines])
    let l:i = l:recent_start
    while l:i < a:cursor_line
        let l:line = l:lines[l:i]
        let l:trimmed = trim(l:line)

        if index(l:context_lines, l:line) >= 0
            let l:i += 1
            continue
        endif

        " Include comments and docstrings.
        if l:trimmed =~# '^\(/\*\|//\|#\|\*\|"""\|'''\)'
            call add(l:context_lines, l:line)
            let l:i += 1
            continue
        endif

        " Include significant lines.
        if s:is_significant_line(l:trimmed)
            call add(l:context_lines, l:line)
        endif

        let l:i += 1
    endwhile

    " Join, truncate from the end if too long, starting at a line boundary.
    let l:context = join(l:context_lines, "\n")
    if len(l:context) > l:max_chars
        let l:context = strpart(l:context, len(l:context) - l:max_chars)
        let l:nl = stridx(l:context, "\n")
        if l:nl > 0
            let l:context = strpart(l:context, l:nl + 1)
        endif
    endif

    return l:context
endfunction

function! fim_ollama#context#format_file_context(context, file_name, language_id) abort
    let l:context = trim(a:context)
    if empty(l:context)
        return ''
    endif

    let l:ext = fnamemodify(a:file_name, ':e')
    if empty(l:ext)
        let l:ext = a:language_id
    endif

    return '<|file_context|>File: ' . a:file_name . "\n```" . l:ext . "\n" . l:context . "\n```<|end_file_context|>\n\n"
endfunction

function! fim_ollama#context#extract_current_scope(bufnr, cursor_line) abort
    let l:lines = getbufline(a:bufnr, 1, a:cursor_line)
    let l:lang = getbufvar(a:bufnr, '&filetype')
    let l:scope_stack = []

    let l:i = 0
    while l:i < a:cursor_line
        let l:line = l:lines[l:i]
        let l:trimmed = trim(l:line)
        let l:indent = len(l:line) - len(trim(l:line))

        let l:entry = s:match_scope_entry(l:trimmed)
        if !empty(l:entry)
            " Pop scopes at same or deeper indentation (Python-style nesting).
            while !empty(l:scope_stack) && l:scope_stack[-1].indent >= l:indent
                call remove(l:scope_stack, -1)
            endwhile
            call add(l:scope_stack, { 'type': l:entry.type, 'name': l:entry.name, 'indent': l:indent })
        endif

        " For C-style languages, adjust stack based on braces.
        if index(['javascript', 'typescript', 'java', 'c', 'cpp', 'csharp', 'go'], l:lang) >= 0
            let l:open = count_chars(l:line, '{')
            let l:close = count_chars(l:line, '}')
            let l:net = l:open - l:close
            if l:net < 0
                let l:j = 0
                while l:j < abs(l:net) && !empty(l:scope_stack)
                    call remove(l:scope_stack, -1)
                    let l:j += 1
                endwhile
            endif
        endif

        let l:i += 1
    endwhile

    if empty(l:scope_stack)
        return ''
    endif

    let l:parts = []
    for l:item in l:scope_stack
        call add(l:parts, l:item.type . ' ' . l:item.name)
    endfor

    return join(l:parts, ' > ')
endfunction

" ---------------------------------------------------------------------------
" Helpers
" ---------------------------------------------------------------------------

function! s:is_structural_definition(line, language_id) abort
    let l:patterns = copy(s:structural_patterns)
    let l:lang_patterns = get(s:lang_structural_patterns, a:language_id, [])
    let l:patterns += l:lang_patterns

    for l:pat in l:patterns
        if a:line =~# l:pat
            return v:true
        endif
    endfor
    return v:false
endfunction

function! s:is_significant_line(line) abort
    if empty(a:line) | return v:false | endif
    if len(a:line) < 3 | return v:false | endif
    if trim(a:line) =~# '^[{}\[\]()]$' | return v:false | endif
    if len(trim(a:line)) < 2 | return v:false | endif
    return v:true
endfunction

function! s:match_scope_entry(line) abort
    let l:patterns = [
        \ { 'pat': 'class\s\+(\w\+)', 'type': 'class' },
        \ { 'pat': 'interface\s\+(\w\+)', 'type': 'interface' },
        \ { 'pat': 'struct\s\+(\w\+)', 'type': 'struct' },
        \ { 'pat': 'enum\s\+(\w\+)', 'type': 'enum' },
        \ { 'pat': 'trait\s\+(\w\+)', 'type': 'trait' },
        \ { 'pat': 'module\s\+(\w\+)', 'type': 'module' },
        \ { 'pat': 'def\s\+(\w\+)\s*(', 'type': 'function' },
        \ { 'pat': 'fn\s\+(\w\+)\s*(', 'type': 'function' },
        \ { 'pat': 'func\s\+(\w\+)\s*(', 'type': 'function' },
        \ { 'pat': 'function\s\+(\w\+)\s*(', 'type': 'function' },
        \ { 'pat': '(\w\+)\s*:\s*function\s*(', 'type': 'method' },
        \ { 'pat': '(\w\+)\s*[=:]\s*([^)]*)\)\s*=>', 'type': 'function' },
        \ ]

    for l:item in l:patterns
        let l:match = matchlist(a:line, l:item.pat)
        if !empty(l:match)
            return { 'type': l:item.type, 'name': l:match[1] }
        endif
    endfor

    return {}
endfunction

function! count_chars(str, char) abort
    let l:cnt = 0
    let l:i = 0
    while l:i < len(a:str)
        if a:str[l:i] ==# a:char
            let l:cnt += 1
        endif
        let l:i += 1
    endwhile
    return l:cnt
endfunction

if exists('*trim')
    " Vim 8.0+ has built-in trim().
    finish
endif

function! trim(str) abort
    return substitute(a:str, '^\s\+\|\s\+$', '', 'g')
endfunction
