# choudaima.vim

`choudaima.vim` rewrites a line range with Codex while keeping you inside Vim. Select some text (any Visual mode) or put the cursor in a paragraph, open a short prompt buffer, and use `:write` to submit. The Codex response replaces the range as one linewise edit.

## Requirements

- Vim 9.1 with `+job`, `+channel`, `+timers`, and `+textprop`
- [Codex CLI](https://learn.chatgpt.com/docs/developer-commands?surface=cli)
- A Codex login using either ChatGPT subscription access or an API key

Install this directory with your Vim package/plugin manager, then choose mappings:

```vim
nmap <leader>cr <Plug>(choudaima-rewrite)
xmap <leader>cr <Plug>(choudaima-rewrite)
```

Choudaima defaults to subscription-only authentication. Run `codex login` and complete the ChatGPT browser flow before using it. API-key authentication is separately billed; to require it instead:

```vim
let g:choudaima_use_subscription = v:false
```

## Workflow

1. Invoke `<Plug>(choudaima-rewrite)` or `:Choudaima`.
2. Enter a multiline instruction in the bottom scratch split.
3. Use `:write` or `:wq` to submit. Use `:q!` to cancel the draft.
4. Continue editing while Codex works asynchronously.

Visual selections are expanded to complete lines. Without a range, Choudaima uses the contiguous nonblank paragraph under the cursor, or the next paragraph when the cursor is on blank lines.

Each request is assigned an ID. Non-overlapping requests in the same buffer may run concurrently and return in any order. If the target changes before a response returns, Choudaima preserves the candidate in `[Choudaima Result #ID]` instead of overwriting newer work.

## Commands

- `:Choudaima` opens a prompt for the current/next paragraph.
- `:{range}Choudaima` opens a prompt for a line range.
- `:ChoudaimaRequests` lists active request IDs.
- `:ChoudaimaCancel {id}` cancels one request.
- `:ChoudaimaCancel all` cancels requests targeting the current buffer.
- `:ChoudaimaHealth` checks the executable and required authentication mode.

## Configuration

```vim
let g:choudaima_codex_command = 'codex'
let g:choudaima_model = ''                  " Empty inherits Codex configuration
let g:choudaima_use_subscription = v:true   " v:false requires API-key login
let g:choudaima_prompt_height = 7
let g:choudaima_context_max_bytes = 256 * 1024
let g:choudaima_context_lines = 100
```

For buffers at or below the byte cap, Choudaima sends the complete in-memory buffer. Larger buffers send the target and the configured number of surrounding lines. Named, modified, and unnamed buffers are supported.

Codex runs with an ephemeral session and a read-only sandbox. Choudaima does not read or manage Codex credential files.

## Development

Run the headless test suite with:

```sh
./test/run.sh
```
