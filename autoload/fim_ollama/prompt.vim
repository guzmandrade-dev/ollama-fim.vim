" FIM prompt construction for different model families.
" Mirrors src/client.ts buildFimPrompt and FIM_TOKENS.
"
" Mistral-family models (Codestral/Ministral) expect a Suffix-Prefix-Middle
" (SPM) layout. When Ollama supports raw mode that is the cleanest path:
"     <s>[SUFFIX]{suffix}[PREFIX]{prefix}
" Ollama Cloud currently rejects raw mode for ministral-3, so for that
" family we embed the SPM markers inside a short instruction so the chat
" template still wraps it, but the model is told to output only code.

let s:fim_tokens = {
    \ 'rnj-1':    { 'pre': '<|pre_fim|>',  'suf': '<|suf_fim|>',  'mid': '<|mid_fim|>'  },
    \ 'deepseek': { 'pre': '<|fim_begin|>', 'suf': '<|fim_hole|>', 'mid': '<|fim_end|>'  },
    \ 'qwen':     { 'pre': '<|fim_prefix|>', 'suf': '<|fim_suffix|>', 'mid': '<|fim_middle|>' },
    \ 'gemma':    { 'pre': '<|fim_prefix|>', 'suf': '<|fim_suffix|>', 'mid': '<|fim_middle|>' },
    \ 'mistral':  { 'pre': '[PREFIX]',     'suf': '[SUFFIX]',     'mid': '',            'bos': '<s>', 'raw': 1 },
    \ 'ministral': { 'pre': '[PREFIX]',    'suf': '[SUFFIX]',     'mid': '',            'bos': '<s>', 'raw': 0 },
    \ }

let s:default_stop_tokens = [
    \ "\n\n",
    \ '```',
    \ '<|endoftext|>',
    \ '<|file_context|>',
    \ '<|end_file_context|>',
    \ '// Currently in:',
    \ '// Note:',
    \ '// Notes:',
    \ '/* Note:',
    \ '/* Notes:',
    \ '# Note:',
    \ '# Notes:',
    \ ]

let s:default_chat_system_prompt = "You are a code completion assistant. The user gives you a code file with a cursor gap marked by FIM tokens. Complete only the missing code between the existing prefix and suffix. Output raw code only, no markdown, no explanations, no comments like 'Here is'."

function! fim_ollama#prompt#supported_models() abort
    return keys(s:fim_tokens)
endfunction

function! fim_ollama#prompt#default_stop_tokens() abort
    " Return a copy so callers don't mutate shared state.
    return copy(s:default_stop_tokens)
endfunction

function! fim_ollama#prompt#chat_system_prompt() abort
    if exists('g:fim_ollama_system_prompt') && !empty(g:fim_ollama_system_prompt)
        return g:fim_ollama_system_prompt
    endif
    return s:default_chat_system_prompt
endfunction

function! fim_ollama#prompt#ministral_system_prompt() abort
    return fim_ollama#prompt#chat_system_prompt()
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
    elseif l:model_type ==# 'mistral' || l:model_type ==# 'ministral'
        " Mistral / Codestral / Ministral native SPM FIM.
        " <s>[SUFFIX]{suffix}[PREFIX]{prefix}
        let l:bos = get(l:tokens, 'bos', '<s>')
        if l:has_suffix
            let l:body = l:bos . l:tokens.suf . a:suffix . l:tokens.pre . a:prefix
        else
            " No suffix available: degrade to prefix-only continuation.
            let l:body = l:bos . l:tokens.pre . a:prefix
        endif
        if !get(l:tokens, 'raw', 0)
            " Ollama Cloud does not allow raw mode for this model, so wrap
            " the SPM body in a short instruction so the chat template still
            " produces a code completion instead of a conversation.
            let l:instruction = fim_ollama#prompt#ministral_system_prompt()
            return l:instruction . "\n\n" . l:body
        endif
        return l:body
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
    let l:stops = [l:tokens.pre, l:tokens.suf]
    if !empty(get(l:tokens, 'mid', ''))
        call add(l:stops, l:tokens.mid)
    endif
    if !empty(get(l:tokens, 'bos', ''))
        call add(l:stops, l:tokens.bos)
    endif
    return l:stops
endfunction

function! fim_ollama#prompt#all_stop_tokens(model_type) abort
    let l:model = fim_ollama#prompt#model_stop_tokens(a:model_type)
    return l:model + copy(s:default_stop_tokens)
endfunction

" Return 1 if the model family requires Ollama raw mode (no chat template).
" Users can override with g:fim_ollama_raw.
function! fim_ollama#prompt#requires_raw(model_type) abort
    if exists('g:fim_ollama_raw')
        return g:fim_ollama_raw ? 1 : 0
    endif

    " Qwen coder models understand raw FIM tokens; use raw mode on Ollama so
    " the chat template does not mangle the FIM prompt.
    if a:model_type ==# 'qwen'
        return 1
    endif

    if a:model_type !=# 'mistral' && a:model_type !=# 'ministral'
        return 0
    endif
    let l:tokens = s:fim_tokens[a:model_type]
    return get(l:tokens, 'raw', 0)
endfunction

" Return 1 if the model family needs an instruction prefix when raw mode is
" unavailable (e.g. Ollama Cloud Ministral).
function! fim_ollama#prompt#uses_instruction_prefix(model_type) abort
    if a:model_type !=# 'mistral' && a:model_type !=# 'ministral'
        return 0
    endif
    let l:tokens = s:fim_tokens[a:model_type]
    return !get(l:tokens, 'raw', 0)
endfunction
