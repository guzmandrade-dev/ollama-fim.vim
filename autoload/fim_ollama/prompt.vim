" FIM prompt construction for different model families.
" Mirrors src/client.ts buildFimPrompt and FIM_TOKENS.

let s:fim_tokens = {
    \ 'rnj-1':    { 'pre': '<|pre_fim|>',  'suf': '<|suf_fim|>',  'mid': '<|mid_fim|>'  },
    \ 'deepseek': { 'pre': '<|fim_begin|>', 'suf': '<|fim_hole|>', 'mid': '<|fim_end|>'  },
    \ 'qwen':     { 'pre': '<|fim_prefix|>', 'suf': '<|fim_suffix|>', 'mid': '<|fim_middle|>' },
    \ 'gemma':    { 'pre': '<|fim_prefix|>', 'suf': '<|fim_suffix|>', 'mid': '<|fim_middle|>' },
    \ 'mistral':  { 'pre': '<|fim_prefix|>', 'suf': '<|fim_suffix|>', 'mid': '<|fim_middle|>' },
    \ }

let s:default_stop_tokens = [
    \ "\n\n",
    \ '```',
    \ '<|endoftext|>',
    \ '// Note:',
    \ '// Notes:',
    \ '/* Note:',
    \ '/* Notes:',
    \ '# Note:',
    \ '# Notes:',
    \ ]

function! fim_ollama#prompt#supported_models() abort
    return keys(s:fim_tokens)
endfunction

function! fim_ollama#prompt#default_stop_tokens() abort
    " Return a copy so callers don't mutate shared state.
    return copy(s:default_stop_tokens)
endfunction

function! fim_ollama#prompt#build_fim_prompt(prefix, suffix, model_type) abort
    if !has_key(s:fim_tokens, a:model_type)
        let l:model_type = 'rnj-1'
    else
        let l:model_type = a:model_type
    endif

    let l:tokens = s:fim_tokens[l:model_type]
    let l:has_suffix = type(a:suffix) == v:t_string && a:suffix !=# ''

    if l:model_type ==# 'gemma'
        " Gemma: <|fim_prefix|>prefix<|fim_middle|>suffix<|fim_suffix|>
        if l:has_suffix
            return l:tokens.pre . a:prefix . l:tokens.mid . a:suffix . l:tokens.suf
        else
            return l:tokens.pre . a:prefix . l:tokens.mid
        endif
    else
        " Standard: <pre>prefix<suf>suffix<mid>
        if l:has_suffix
            return l:tokens.pre . a:prefix . l:tokens.suf . a:suffix . l:tokens.mid
        else
            return l:tokens.pre . a:prefix . l:tokens.mid
        endif
    endif
endfunction

function! fim_ollama#prompt#model_stop_tokens(model_type) abort
    if !has_key(s:fim_tokens, a:model_type)
        let l:model_type = 'rnj-1'
    else
        let l:model_type = a:model_type
    endif
    let l:tokens = s:fim_tokens[l:model_type]
    return [l:tokens.pre, l:tokens.suf, l:tokens.mid]
endfunction

function! fim_ollama#prompt#all_stop_tokens(model_type) abort
    let l:model = fim_ollama#prompt#model_stop_tokens(a:model_type)
    return l:model + copy(s:default_stop_tokens)
endfunction
