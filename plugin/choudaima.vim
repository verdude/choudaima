if exists('g:loaded_choudaima')
  finish
endif

if v:version < 901 || !has('job') || !has('channel') || !has('timers') || !has('textprop')
  echohl ErrorMsg
  echomsg '[choudaima] Vim 9.1+ with +job, +channel, +timers, and +textprop is required'
  echohl None
  finish
endif

let g:loaded_choudaima = 1

let g:choudaima_codex_command = get(g:, 'choudaima_codex_command', 'codex')
let g:choudaima_model = get(g:, 'choudaima_model', '')
let g:choudaima_use_subscription = get(g:, 'choudaima_use_subscription', v:true)
let g:choudaima_prompt_height = get(g:, 'choudaima_prompt_height', 7)
let g:choudaima_context_max_bytes = get(g:, 'choudaima_context_max_bytes', 256 * 1024)
let g:choudaima_context_lines = get(g:, 'choudaima_context_lines', 100)

command! -range=0 Choudaima call choudaima#start(<line1>, <line2>, <range>)
command! -nargs=1 -complete=customlist,choudaima#complete_cancel ChoudaimaCancel call choudaima#cancel(<q-args>)
command! -nargs=0 ChoudaimaRequests call choudaima#requests()
command! -nargs=0 ChoudaimaHealth call choudaima#health()

nnoremap <silent> <Plug>(choudaima-rewrite) <Cmd>Choudaima<CR>
xnoremap <silent> <Plug>(choudaima-rewrite) :<C-U>call choudaima#start(line("'<"), line("'>"), 1)<CR>

augroup choudaima_prompt_buffers
  autocmd!
  autocmd BufWipeout * call choudaima#discard_prompt(str2nr(expand('<abuf>')))
augroup END
