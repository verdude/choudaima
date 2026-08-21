set nocompatible
set nomore
set hidden
set shortmess+=I
set rtp^=.
runtime plugin/choudaima.vim

let s:tmp = tempname()
call mkdir(s:tmp, 'p')
let $CHOUDAIMA_FAKE_RESPONSES_DIR = s:tmp
let $CHOUDAIMA_FAKE_AUTH = 'chatgpt'
let $CHOUDAIMA_FAKE_AUTH_DELAY = ''
let $CHOUDAIMA_FAKE_AUTH_LOG = ''
let g:choudaima_codex_command = fnamemodify('test/fake_codex.sh', ':p')
let g:choudaima_use_subscription = v:true
let g:choudaima_prompt_height = 2

" Loading Choudaima must not intercept writes to ordinary file buffers.
let s:ordinary_path = s:tmp . '/ordinary.txt'
call writefile(['before'], s:ordinary_path)
execute 'edit ' . fnameescape(s:ordinary_path)
call setline(1, 'after')
write
call assert_equal(['after'], readfile(s:ordinary_path))
bwipeout!

function! s:write_response(id, lines, ...) abort
  let delay = a:0 ? a:1 : 0
  call writefile([json_encode({'replacement_lines': a:lines})], s:tmp . '/' . a:id . '.json')
  if delay > 0
    call writefile([string(delay)], s:tmp . '/' . a:id . '.delay')
  endif
endfunction

function! s:submit(source, start_line, end_line, prompt) abort
  execute 'buffer ' . a:source
  call choudaima#start(a:start_line, a:end_line, 1)
  let prompt_buf = bufnr('%')
  call setline(1, a:prompt)
  call choudaima#submit_prompt(prompt_buf)
  sleep 20m
  return prompt_buf
endfunction

function! s:wait_for_buffer_line(bufnr, line_number, expected, timeout_ms) abort
  let waited = 0
  while waited < a:timeout_ms
    if getbufline(a:bufnr, a:line_number) ==# [a:expected]
      return v:true
    endif
    sleep 10m
    let waited += 10
  endwhile
  return v:false
endfunction

function! s:wait_for_result(id, timeout_ms) abort
  let waited = 0
  let name = '[Choudaima Result #' . a:id . ']'
  while waited < a:timeout_ms
    for result in range(1, bufnr('$'))
      if bufexists(result) && bufname(result) ==# name
        return result
      endif
    endfor
    sleep 10m
    let waited += 10
  endwhile
  return -1
endfunction

function! s:wait_for_message(pattern, timeout_ms) abort
  let waited = 0
  while waited < a:timeout_ms
    if execute('messages') =~# a:pattern
      return v:true
    endif
    sleep 10m
    let waited += 10
  endwhile
  return v:false
endfunction

call assert_equal(2, exists(':Choudaima'))
call assert_equal(2, exists(':ChoudaimaCancel'))
call assert_match('Choudaima', maparg('<Plug>(choudaima-rewrite)', 'n'))
call assert_match('choudaima#start', maparg('<Plug>(choudaima-rewrite)', 'x'))

" Request #1: normal-mode blank-line skipping, full context, and one-step undo.
enew!
let s:source1 = bufnr('%')
call setline(1, ['first', 'second', '', 'third', 'fourth'])
setlocal filetype=text
call cursor(3, 1)
call s:write_response(1, ['THIRD', 'FOURTH', 'FIFTH'])
call choudaima#start(0, 0, 0)
let s:prompt1 = bufnr('%')
call setline(1, 'uppercase and add a line')
let s:auth_log1 = s:tmp . '/auth-1.log'
let $CHOUDAIMA_FAKE_AUTH_LOG = s:auth_log1
let $CHOUDAIMA_FAKE_AUTH_DELAY = '0.50'
let s:auth_started = reltime()
write
call assert_true(reltimefloat(reltime(s:auth_started)) < 0.35)
call assert_equal(0, getbufvar(s:prompt1, '&modifiable'))
call assert_true(getbufvar(s:prompt1, 'choudaima_auth_pending'))
write
call assert_true(s:wait_for_buffer_line(s:source1, 4, 'THIRD', 2000))
call assert_equal(['check'], readfile(s:auth_log1))
let $CHOUDAIMA_FAKE_AUTH_LOG = ''
let $CHOUDAIMA_FAKE_AUTH_DELAY = ''
call assert_equal(['first', 'second', '', 'THIRD', 'FOURTH', 'FIFTH'], getbufline(s:source1, 1, '$'))
let s:context1 = json_decode(join(readfile(s:tmp . '/1.stdin'), "\n"))
call assert_equal('whole_buffer', s:context1.context.mode)
call assert_equal(['third', 'fourth'], s:context1.target_lines)
let s:args1 = readfile(s:tmp . '/1.args')
call assert_match('User request:', join(s:args1, "\n"))
call assert_true(index(s:args1, '--ephemeral') >= 0)
call assert_true(index(s:args1, '--output-schema') >= 0)
call assert_true(index(s:args1, 'read-only') >= 0)
execute 'buffer ' . s:source1
undo
call assert_equal(['first', 'second', '', 'third', 'fourth'], getbufline(s:source1, 1, '$'))
redo
call assert_equal(['first', 'second', '', 'THIRD', 'FOURTH', 'FIFTH'], getbufline(s:source1, 1, '$'))

" Request #2: context fallback around the selected range.
enew!
let s:source2 = bufnr('%')
call setline(1, map(range(1, 12), '"line-" . v:val'))
let g:choudaima_context_max_bytes = 10
let g:choudaima_context_lines = 1
call s:write_response(2, ['middle'])
call s:submit(s:source2, 6, 7, 'condense')
call assert_true(s:wait_for_buffer_line(s:source2, 6, 'middle', 2000))
let s:context2 = json_decode(join(readfile(s:tmp . '/2.stdin'), "\n"))
call assert_equal('local_window', s:context2.context.mode)
call assert_equal(5, s:context2.context.start_line)
call assert_equal(8, s:context2.context.end_line)
call assert_equal(4, s:context2.context.omitted_before)
call assert_equal(4, s:context2.context.omitted_after)
let g:choudaima_context_max_bytes = 256 * 1024
let g:choudaima_context_lines = 100

" Requests #3 and #4: out-of-order non-overlapping edits track shifted lines.
enew!
let s:source3 = bufnr('%')
call setline(1, ['early', '', 'middle', '', 'late'])
call s:write_response(3, ['LATE'], 0.20)
call s:write_response(4, ['EARLY-A', 'EARLY-B'], 0.02)
call s:submit(s:source3, 5, 5, 'uppercase late')
call s:submit(s:source3, 1, 1, 'expand early')
call assert_true(s:wait_for_buffer_line(s:source3, 1, 'EARLY-A', 2000))
call assert_true(s:wait_for_buffer_line(s:source3, 6, 'LATE', 2000))
call assert_equal(['EARLY-A', 'EARLY-B', '', 'middle', '', 'LATE'], getbufline(s:source3, 1, '$'))

" Request #5: stale target is not overwritten and candidate is preserved.
enew!
let s:source4 = bufnr('%')
call setline(1, ['keep', 'target', 'tail'])
call s:write_response(5, ['candidate'], 0.15)
call s:submit(s:source4, 2, 2, 'replace target')
call setbufline(s:source4, 2, 'manual edit')
let s:result5 = s:wait_for_result(5, 2000)
call assert_true(s:result5 > 0)
call assert_equal(['manual edit'], getbufline(s:source4, 2))
call assert_equal(['candidate'], getbufline(s:result5, 1, '$'))

" Auth mode mismatch leaves the draft open and does not allocate a request.
execute 'buffer ' . s:source4
let $CHOUDAIMA_FAKE_AUTH = 'apikey'
call choudaima#start(1, 1, 1)
let s:auth_prompt = bufnr('%')
call setline(1, 'should not submit')
call choudaima#submit_prompt(s:auth_prompt)
let s:waited = 0
while !getbufvar(s:auth_prompt, '&modifiable') && s:waited < 2000
  sleep 10m
  let s:waited += 10
endwhile
call assert_true(bufexists(s:auth_prompt))
call assert_equal(1, getbufvar(s:auth_prompt, '&modifiable'))
call assert_equal(1, getbufvar(s:auth_prompt, '&modified'))
call choudaima#discard_prompt(s:auth_prompt)
execute 'silent! bwipeout! ' . s:auth_prompt
let $CHOUDAIMA_FAKE_AUTH = 'chatgpt'

" Cancelling a prompt while authentication is pending stops before request #6.
execute 'buffer ' . s:source4
let $CHOUDAIMA_FAKE_AUTH_DELAY = '0.30'
call choudaima#start(1, 1, 1)
let s:cancel_auth_prompt = bufnr('%')
call setline(1, 'never submit')
call choudaima#submit_prompt(s:cancel_auth_prompt)
call assert_equal(0, getbufvar(s:cancel_auth_prompt, '&modifiable'))
quit!
sleep 400m
call assert_false(bufexists(s:cancel_auth_prompt))
call assert_false(filereadable(s:tmp . '/6.stdin'))
call assert_equal(['keep'], getbufline(s:source4, 1))
let $CHOUDAIMA_FAKE_AUTH_DELAY = ''

" Request #6: cancellation by ID prevents application.
execute 'buffer ' . s:source4
call s:write_response(6, ['cancelled output'], 1)
call s:submit(s:source4, 1, 1, 'slow request')
call choudaima#cancel('6')
sleep 100m
call assert_equal(['keep'], getbufline(s:source4, 1))

" Request #7: malformed output is retained as diagnostics.
call writefile(['not json'], s:tmp . '/7.json')
call s:submit(s:source4, 3, 3, 'bad output')
let s:result7 = s:wait_for_result(7, 2000)
call assert_true(s:result7 > 0)
call assert_match('invalid JSON', join(getbufline(s:result7, 1, '$'), "\n"))

" Request #8: an empty replacement deletes the selected lines.
call s:write_response(8, [])
call s:submit(s:source4, 3, 3, 'delete tail')
let s:waited = 0
while len(getbufline(s:source4, 1, '$')) != 2 && s:waited < 2000
  sleep 10m
  let s:waited += 10
endwhile
call assert_equal(['keep', 'manual edit'], getbufline(s:source4, 1, '$'))

" Requests #9 and #10: real :write and :wq prompt submission paths.
enew!
let s:source5 = bufnr('%')
call setline(1, ['write-path', '', 'wq-path'])
call s:write_response(9, ['WRITE'])
call choudaima#start(1, 1, 1)
let s:write_prompt = bufnr('%')
call setline(1, 'submit with write')
write
call assert_true(s:wait_for_buffer_line(s:source5, 1, 'WRITE', 2000))
sleep 20m
call assert_false(bufexists(s:write_prompt))

execute 'buffer ' . s:source5
call s:write_response(10, ['WQ'])
let $CHOUDAIMA_FAKE_AUTH_DELAY = '0.20'
call choudaima#start(3, 3, 1)
let s:wq_prompt = bufnr('%')
call setline(1, 'submit with wq')
wq
call assert_true(s:wait_for_buffer_line(s:source5, 3, 'WQ', 2000))
call assert_false(bufexists(s:wq_prompt))
let $CHOUDAIMA_FAKE_AUTH_DELAY = ''

" Request #11: API-key-only mode accepts API-key auth.
let $CHOUDAIMA_FAKE_AUTH = 'apikey'
let g:choudaima_use_subscription = v:false
call s:write_response(11, ['API'])
call s:submit(s:source5, 1, 1, 'api mode')
call assert_true(s:wait_for_buffer_line(s:source5, 1, 'API', 2000))
let $CHOUDAIMA_FAKE_AUTH = 'chatgpt'
let g:choudaima_use_subscription = v:true

" Request #12: nonzero Codex exits retain stderr diagnostics.
call writefile(['23'], s:tmp . '/12.exit')
call s:submit(s:source5, 1, 1, 'forced failure')
let s:result12 = s:wait_for_result(12, 2000)
call assert_true(s:result12 > 0)
call assert_match('status 23', join(getbufline(s:result12, 1, '$'), "\n"))
call assert_match('forced fake Codex failure', join(getbufline(s:result12, 1, '$'), "\n"))

" Requests #13 and #14: cancel all jobs for the current source buffer.
call s:write_response(13, ['never-13'], 1)
call s:write_response(14, ['never-14'], 1)
call s:submit(s:source5, 1, 1, 'slow one')
call s:submit(s:source5, 3, 3, 'slow two')
execute 'buffer ' . s:source5
call choudaima#cancel('all')
sleep 100m
call assert_equal(['API', '', 'WQ'], getbufline(s:source5, 1, '$'))

" Request #15: embedded newlines violate the line-array contract.
call writefile([json_encode({'replacement_lines': ["bad\nline"]})], s:tmp . '/15.json')
call s:submit(s:source5, 1, 1, 'bad line array')
let s:result15 = s:wait_for_result(15, 2000)
call assert_true(s:result15 > 0)
call assert_match('must not contain newline', join(getbufline(s:result15, 1, '$'), "\n"))

" Request #16: deleting an entire one-line buffer leaves Vim's empty line.
enew!
let s:source6 = bufnr('%')
call setline(1, 'only line')
call s:write_response(16, [])
call s:submit(s:source6, 1, 1, 'delete everything')
let s:waited = 0
while getbufline(s:source6, 1, '$') !=# [''] && s:waited < 2000
  sleep 10m
  let s:waited += 10
endwhile
call assert_equal([''], getbufline(s:source6, 1, '$'))

" Request #17: named modified buffers report filepath, filetype, and Git root.
let s:project = s:tmp . '/project'
call mkdir(s:project . '/.git', 'p')
enew!
execute 'file ' . fnameescape(s:project . '/sample.py')
let s:source7 = bufnr('%')
setlocal filetype=python
call setline(1, ['def example():', '    return 1'])
call s:write_response(17, ['def example():', '    return 2'])
call s:submit(s:source7, 1, 2, 'change return')
call assert_true(s:wait_for_buffer_line(s:source7, 2, '    return 2', 2000))
let s:context17 = json_decode(join(readfile(s:tmp . '/17.stdin'), "\n"))
call assert_equal(fnamemodify(s:project . '/sample.py', ':p'), s:context17.filepath)
call assert_equal('python', s:context17.filetype)
call assert_equal(fnamemodify(s:project, ':p'), fnamemodify(s:context17.project_root, ':p'))

" Health checks return immediately, deduplicate, and report asynchronously.
let s:health_auth_log = s:tmp . '/health-auth.log'
let $CHOUDAIMA_FAKE_AUTH_LOG = s:health_auth_log
let $CHOUDAIMA_FAKE_AUTH_DELAY = '0.50'
let s:health_started = reltime()
call choudaima#health()
call choudaima#health()
call assert_true(reltimefloat(reltime(s:health_started)) < 0.35)
call assert_match('authentication check already in progress', execute('messages'))
call assert_true(s:wait_for_message('healthy: Codex is authenticated with ChatGPT', 2000))
call assert_equal(['check'], readfile(s:health_auth_log))
let $CHOUDAIMA_FAKE_AUTH_LOG = ''
let $CHOUDAIMA_FAKE_AUTH_DELAY = ''

let s:invalid_health_log = s:tmp . '/invalid-health-auth.log'
let $CHOUDAIMA_FAKE_AUTH_LOG = s:invalid_health_log
let g:choudaima_use_subscription = 'invalid'
call choudaima#health()
sleep 20m
call assert_false(filereadable(s:invalid_health_log))
call assert_match('g:choudaima_use_subscription must be boolean', execute('messages'))
let g:choudaima_use_subscription = v:true
let $CHOUDAIMA_FAKE_AUTH_LOG = ''

let $CHOUDAIMA_FAKE_AUTH = 'none'
call choudaima#health()
call assert_true(s:wait_for_message('Codex authentication check failed: Not logged in', 2000))
let $CHOUDAIMA_FAKE_AUTH = 'chatgpt'

call delete(s:tmp, 'rf')

if !empty(v:errors)
  call writefile(v:errors, 'test/test-errors.log')
  cquit 1
endif
call delete('test/test-errors.log')
qa!
