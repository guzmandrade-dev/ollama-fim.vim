" Async HTTP client using curl.
" Calls Ollama /api/generate with the built FIM prompt.

let s:pending_job = v:null
let s:pending_request_id = 0
let s:output_buffer = ''
let s:err_output_buffer = ''
let s:request_log = {}
let s:last_error_msg = ''
let s:last_error_time = 0

" Build a JSON payload for the configured backend.
" When backend is 'openai', shape matches OpenAI's /v1/chat/completions.
" Otherwise (default 'ollama'), shape matches Ollama /api/generate.
function! fim_ollama#client#build_payload(model, prompt, stop_tokens, max_tokens, temperature, ...) abort
    let l:backend = a:0 >= 3 && !empty(a:3) ? a:3 : 'ollama'
    let l:seed = a:0 >= 1 && !empty(a:1) ? a:1 : v:null
    let l:raw = a:0 >= 2 && !empty(a:2) ? a:2 : v:false

    if l:backend ==# 'openai'
        let l:system_prompt = fim_ollama#prompt#chat_system_prompt()
        let l:payload = {
            \ 'model': a:model,
            \ 'messages': [
            \   {'role': 'system', 'content': l:system_prompt},
            \   {'role': 'user', 'content': a:prompt},
            \ ],
            \ 'max_tokens': a:max_tokens,
            \ 'temperature': a:temperature,
            \ 'stop': a:stop_tokens,
            \ }
        if !empty(l:seed)
            let l:payload.seed = l:seed
        endif
        return l:payload
    endif

    let l:options = {
        \ 'num_predict': a:max_tokens,
        \ 'temperature': a:temperature,
        \ 'stop': a:stop_tokens,
        \ }

    " Optional seed (for reproducible/different suggestions on cycle).
    if !empty(l:seed)
        let l:options.seed = l:seed
    endif

    let l:payload = {
        \ 'model': a:model,
        \ 'prompt': a:prompt,
        \ 'stream': v:false,
        \ 'options': l:options,
        \ }

    " Optional raw mode (bypass the model's chat template).
    " Needed for Mistral-family SPM FIM.
    if !empty(l:raw)
        let l:payload.raw = v:true
    endif

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

" Return the configured log file path, if any.
function! s:log_file() abort
    if exists('g:fim_ollama_log_file') && !empty(g:fim_ollama_log_file)
        return g:fim_ollama_log_file
    endif
    return ''
endfunction

" Append a timestamped line to the log file.
function! s:log(msg) abort
    let l:file = s:log_file()
    if empty(l:file)
        return
    endif
    let l:line = strftime('%Y-%m-%d %H:%M:%S') . ' ' . a:msg
    call writefile([l:line], l:file, 'a')
endfunction

" Public logging entry point so other modules can log to the same file.
function! fim_ollama#client#log(msg) abort
    call s:log(a:msg)
endfunction

" Show a throttled user-visible error message.
function! s:notify_error(msg) abort
    let l:last = get(s:, 'last_error_msg', '')
    let l:last_time = get(s:, 'last_error_time', 0)
    let l:now = reltimefloat(reltime())
    " Avoid spamming the same message more than once every 10 seconds.
    if a:msg ==# l:last && l:now - l:last_time < 10
        return
    endif
    let s:last_error_msg = a:msg
    let s:last_error_time = l:now
    echohl ErrorMsg
    echom '[fim-ollama] ' . a:msg
    echohl None
endfunction

" Main entry: request a completion.
function! fim_ollama#client#request(request_id, config, callback) abort
    call fim_ollama#client#cancel()

    let s:pending_request_id = a:request_id
    let s:output_buffer = ''
    let s:err_output_buffer = ''
    let s:request_log = {
        \ 'request_id': a:request_id,
        \ 'callback': a:callback,
        \ 'config': a:config,
        \ 'retries': 0,
        \ }

    let l:seed = get(a:config, 'seed', v:null)
    let l:raw = get(a:config, 'raw', v:false)
    let l:payload = fim_ollama#client#build_payload(
        \ a:config.model,
        \ a:config.prompt,
        \ a:config.stop_tokens,
        \ a:config.max_tokens,
        \ a:config.temperature,
        \ l:seed,
        \ l:raw,
        \ get(a:config, 'backend', 'ollama'),
        \ )

    let l:body = fim_ollama#client#json_encode(l:payload)
    let l:tmpfile = tempname()
    call writefile([l:body], l:tmpfile)

    let l:cmd = s:build_curl_cmd(a:config.url, get(a:config, 'path', '/api/generate'), l:tmpfile)
    call s:log('REQUEST #' . a:request_id . ' model=' . a:config.model)
    call s:log('CMD ' . s:redact_cmd(l:cmd))
    call s:log('BODY ' . l:body)

    if has('job')
        let l:jobopts = {
            \ 'out_mode': 'raw',
            \ 'err_mode': 'raw',
            \ 'callback': function('s:job_output', [a:callback, a:request_id]),
            \ 'err_cb': function('s:job_error', [a:callback, a:request_id]),
            \ 'close_cb': function('s:job_close', [a:callback, a:request_id, l:tmpfile]),
            \ }
        let s:pending_job = job_start(l:cmd, l:jobopts)
    else
        " Synchronous fallback for very old Vim (blocks UI, not recommended).
        let l:output = system(l:cmd)
        call delete(l:tmpfile)
        call s:handle_output(l:output, '', a:callback, a:request_id)
    endif
endfunction

function! s:build_curl_cmd(url, path, body_file) abort
    let l:headers = ['Content-Type: application/json']

    if exists('g:fim_ollama_api_key') && !empty(g:fim_ollama_api_key)
        call add(l:headers, 'Authorization: Bearer ' . g:fim_ollama_api_key)
    elseif !empty($OLLAMA_API_KEY)
        call add(l:headers, 'Authorization: Bearer ' . $OLLAMA_API_KEY)
    endif

    let l:cmd = ['curl', '-sS', '-X', 'POST', a:url . a:path]
    for l:h in l:headers
        call add(l:cmd, '-H')
        call add(l:cmd, l:h)
    endfor
    call add(l:cmd, '-d')
    call add(l:cmd, '@' . a:body_file)
    " Capture HTTP status code in stdout for reliable parsing on all platforms.
    call add(l:cmd, '-w')
    call add(l:cmd, '\nHTTP_STATUS:%{http_code}\n')

    return l:cmd
endfunction

" Build a human-readable command string with secrets redacted.
function! s:redact_cmd(cmd) abort
    let l:result = []
    for l:part in a:cmd
        if l:part =~# '^Authorization: Bearer '
            call add(l:result, 'Authorization: Bearer <redacted>')
        else
            call add(l:result, l:part)
        endif
    endfor
    return join(l:result, ' ')
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
    let s:err_output_buffer = ''
endfunction

function! s:job_output(callback, request_id, ch, msg) abort
    let s:output_buffer .= a:msg
endfunction

function! s:job_error(callback, request_id, ch, msg) abort
    let s:err_output_buffer .= a:msg
endfunction

function! s:job_close(callback, request_id, tmpfile, ch) abort
    let l:output = s:output_buffer
    let l:stderr = s:err_output_buffer
    let s:output_buffer = ''
    let s:err_output_buffer = ''
    call delete(a:tmpfile)
    let s:pending_job = v:null
    call s:handle_output(l:output, l:stderr, a:callback, a:request_id)
endfunction

" Retry the last request with the same callback and a fresh seed.
function! s:retry_request() abort
    if empty(get(s:request_log, 'config', {}))
        return
    endif
    let s:request_log.retries += 1
    let s:request_counter += 1
    let l:request_id = s:request_counter
    let s:request_log.request_id = l:request_id
    let s:request_log.config.seed += 1
    call s:log('RETRY #' . s:request_log.retries . ' -> new request ' . l:request_id)
    call fim_ollama#client#request(l:request_id, s:request_log.config, s:request_log.callback)
endfunction

function! s:handle_output(output, stderr, callback, request_id) abort
    let l:trimmed = trim(a:output)
    let l:status = 0
    let l:body = l:trimmed

    " Extract HTTP status appended by curl -w. It may be on its own line
    " or immediately after the response body if the body has no trailing newline.
    if l:body =~# 'HTTP_STATUS:'
        let l:status_line = matchstr(l:body, 'HTTP_STATUS:\zs[0-9]*')
        let l:status = str2nr(l:status_line)
        let l:body = substitute(l:body, '\s*HTTP_STATUS:[0-9]*\s*$', '', '')
        let l:body = trim(l:body)
    endif

    call s:log('RESPONSE #' . a:request_id . ' status=' . l:status)
    call s:log('STDOUT ' . l:body)
    if !empty(a:stderr)
        call s:log('STDERR ' . a:stderr)
    endif

    " Surface transport-level errors first.
    if !empty(a:stderr) && l:status == 0
        call s:notify_error('curl error: ' . strpart(a:stderr, 0, 200))
        return
    endif

    " Surface HTTP errors from the server.
    if l:status >= 400
        let l:msg = 'HTTP ' . l:status
        if !empty(l:body)
            let l:msg .= ': ' . strpart(l:body, 0, 200)
        endif
        call s:notify_error(l:msg)
        " Retry transient server errors once, unless the user has moved on.
        if l:status >= 500 && get(s:request_log, 'retries', 0) < 1
            call s:log('Retrying 5xx error')
            call s:retry_request()
        endif
        return
    endif

    if empty(l:body)
        call s:notify_error('empty response from API')
        return
    endif

    if exists('*json_decode')
        try
            let l:resp = json_decode(l:body)
        catch
            call s:notify_error('invalid JSON response: ' . strpart(l:body, 0, 100))
            return
        endtry
    else
        let l:resp = s:manual_json_parse(l:body)
    endif

    if type(l:resp) != v:t_dict
        call s:notify_error('unexpected response type')
        return
    endif

    let l:backend = get(get(s:request_log, 'config', {}), 'backend', 'ollama')

    if has_key(l:resp, 'error') && !empty(l:resp.error)
        let l:err = type(l:resp.error) == v:t_string ? l:resp.error : string(l:resp.error)
        call s:notify_error('API error: ' . l:err)
        " Retry transient model errors once.
        if get(s:request_log, 'retries', 0) < 1
            call s:log('Retrying API error')
            call s:retry_request()
        endif
        return
    endif

    let l:text = s:extract_response_text(l:resp, l:backend)
    if type(l:text) == v:t_string && !empty(trim(l:text))
        call call(a:callback, [a:request_id, l:text])
    else
        call s:notify_error('empty response text from API')
    endif
endfunction

" Extract the generated text from an API response based on backend.
function! s:extract_response_text(resp, backend) abort
    if a:backend ==# 'openai'
        let l:choices = get(a:resp, 'choices', [])
        if type(l:choices) == v:t_list && !empty(l:choices)
            let l:choice = l:choices[0]
            if type(l:choice) == v:t_dict
                " OpenAI chat.completions returns {message:{content:...}}.
                " Fall back to legacy completions {text:...} if present.
                let l:message = get(l:choice, 'message', {})
                if type(l:message) == v:t_dict && has_key(l:message, 'content')
                    return get(l:message, 'content', '')
                endif
                return get(l:choice, 'text', '')
            endif
        endif
        return ''
    endif

    return get(a:resp, 'response', '')
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
