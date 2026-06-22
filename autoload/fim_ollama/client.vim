" Async HTTP client using curl.
" Calls Ollama /api/generate with the built FIM prompt.

let s:pending_job = v:null
let s:pending_request_id = 0
let s:output_buffer = ''

" Build a JSON payload for Ollama /api/generate.
function! fim_ollama#client#build_payload(model, prompt, stop_tokens, max_tokens, temperature, ...) abort
    let l:options = {
        \ 'num_predict': a:max_tokens,
        \ 'temperature': a:temperature,
        \ 'stop': a:stop_tokens,
        \ }

    " Optional seed (for reproducible/different suggestions on cycle).
    if a:0 >= 1 && !empty(a:1)
        let l:options.seed = a:1
    endif

    let l:payload = {
        \ 'model': a:model,
        \ 'prompt': a:prompt,
        \ 'stream': v:false,
        \ 'options': l:options,
        \ }

    return l:payload
endfunction

" Encode a value to JSON. Falls back to manual building for older Vim.
function! fim_ollama#client#json_encode(value) abort
    if exists('*json_encode')
        return json_encode(a:value)
    endif

    if type(a:value) == v:t_dict
        let l:items = []
        for [l:k, l:v] in items(a:value)
            call add(l:items, string(l:k) . ':' . fim_ollama#client#json_encode(l:v))
        endfor
        return '{' . join(l:items, ',') . '}'
    elseif type(a:value) == v:t_list
        let l:items = []
        for l:v in a:value
            call add(l:items, fim_ollama#client#json_encode(l:v))
        endfor
        return '[' . join(l:items, ',') . ']'
    elseif type(a:value) == v:t_string
        return s:json_string_escape(a:value)
    elseif type(a:value) == v:t_number
        return string(a:value)
    elseif type(a:value) == v:t_bool
        return a:value ? 'true' : 'false'
    endif
    return 'null'
endfunction

" Escape a string for JSON encoding.
function! s:json_string_escape(str) abort
    let l:str = a:str
    let l:str = substitute(l:str, '\\', '\\\\\\\\', 'g')
    let l:str = substitute(l:str, '"', '\\\\"', 'g')
    let l:str = substitute(l:str, "\n", '\\n', 'g')
    let l:str = substitute(l:str, "\r", '\\r', 'g')
    let l:str = substitute(l:str, "\t", '\\t', 'g')
    return '"' . l:str . '"'
endfunction

" Main entry: request a completion.
function! fim_ollama#client#request(request_id, config, callback) abort
    call fim_ollama#client#cancel()

    let s:pending_request_id = a:request_id
    let s:output_buffer = ''

    let l:seed = get(a:config, 'seed', v:null)
    let l:payload = fim_ollama#client#build_payload(
        \ a:config.model,
        \ a:config.prompt,
        \ a:config.stop_tokens,
        \ a:config.max_tokens,
        \ a:config.temperature,
        \ l:seed,
        \ )

    let l:body = fim_ollama#client#json_encode(l:payload)
    let l:tmpfile = tempname()
    call writefile([l:body], l:tmpfile)

    let l:cmd = s:build_curl_cmd(a:config.url, l:tmpfile)

    if has('job')
        let l:jobopts = {
            \ 'out_mode': 'raw',
            \ 'err_mode': 'raw',
            \ 'callback': function('s:job_output', [a:callback, a:request_id]),
            \ 'close_cb': function('s:job_close', [a:callback, a:request_id, l:tmpfile]),
            \ }
        let s:pending_job = job_start(l:cmd, l:jobopts)
    else
        " Synchronous fallback for very old Vim (blocks UI, not recommended).
        let l:output = system(l:cmd)
        call delete(l:tmpfile)
        call s:handle_output(l:output, a:callback, a:request_id)
    endif
endfunction

function! s:build_curl_cmd(url, body_file) abort
    let l:headers = ['Content-Type: application/json']

    if exists('g:fim_ollama_api_key') && !empty(g:fim_ollama_api_key)
        call add(l:headers, 'Authorization: Bearer ' . g:fim_ollama_api_key)
    elseif !empty($OLLAMA_API_KEY)
        call add(l:headers, 'Authorization: Bearer ' . $OLLAMA_API_KEY)
    endif

    let l:cmd = ['curl', '-sS', '-X', 'POST', a:url . '/api/generate']
    for l:h in l:headers
        call add(l:cmd, '-H')
        call add(l:cmd, l:h)
    endfor
    call add(l:cmd, '-d')
    call add(l:cmd, '@' . a:body_file)

    return l:cmd
endfunction

function! fim_ollama#client#cancel() abort
    if s:pending_job isnot# v:null
        try
            if job_status(s:pending_job) ==# 'run'
                call job_stop(s:pending_job)
            endif
        catch
            " ignore
        endtry
        let s:pending_job = v:null
    endif
    let s:output_buffer = ''
endfunction

function! s:job_output(callback, request_id, ch, msg) abort
    let s:output_buffer .= a:msg
endfunction

function! s:job_close(callback, request_id, tmpfile, ch) abort
    let l:output = s:output_buffer
    let s:output_buffer = ''
    call delete(a:tmpfile)
    let s:pending_job = v:null
    call s:handle_output(l:output, a:callback, a:request_id)
endfunction

function! s:handle_output(output, callback, request_id) abort
    let l:trimmed = trim(a:output)
    if empty(l:trimmed)
        return
    endif

    if exists('*json_decode')
        try
            let l:resp = json_decode(l:trimmed)
        catch
            let l:resp = {}
        endtry
    else
        let l:resp = s:manual_json_parse(l:trimmed)
    endif

    let l:text = get(l:resp, 'response', '')
    if type(l:text) == v:t_string && !empty(trim(l:text))
        call call(a:callback, [a:request_id, l:text])
    endif
endfunction

" Minimal JSON parse for response object when json_decode unavailable.
" Only extracts the 'response' string key.
function! s:manual_json_parse(str) abort
    " Match "response": "..."  (non-greedy content, no unescaped quotes)
    let l:match = matchstr(a:str, '"response"\s*:\s*"\zs\([^"]*\)"')
    if empty(l:match)
        let l:match = matchstr(a:str, "'response'\s*:\s*'\zs\([^']*\)'")
    endif
    return { 'response': l:match }
endfunction
