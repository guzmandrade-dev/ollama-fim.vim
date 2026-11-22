# AGENTS.md — ollama-fim.vim

Vim plugin for inline FIM (fill-in-the-middle) code completions powered by
Ollama / OpenAI-compatible endpoints. Suggestions render as ghost text in a
`popup_atcursor` popup (never modifying the buffer) and are accepted with
`Tab` (whole suggestion) or `Ctrl-Right` (word-by-word partial accept).

Requires Vim 8.2+ with `+popupwin` and `curl` in `$PATH`. No Python/Node/LSP
agent needed.

## Layout

```
plugin/fim_ollama.vim            entry point: defaults, commands, <Plug> mappings
autoload/fim_ollama/
  core.vim                       orchestration: debounce, accept/accept_word, locks
  client.vim                     async curl HTTP client, retry, logging
  prompt.vim                     FIM prompt building per model family
  complete.vim                   trim() + split_next_word() (pure string logic)
  context.vim                    file context / scope extraction (optional ctags)
  indent.vim                     indent normalization to buffer's tab/space style
  tags.vim                       optional Universal Ctags symbol context
  ui.vim                         popup show/hide/accept (ghost text state)
doc/fim_ollama.txt               Vim help doc (keep in sync with README)
tests/                           headless test suite (see below)
scripts/                           test.sh, lint.sh, dist.sh (release artifacts),
                                   release_files.vim (shipped-file list, shared with
                                   mkvimball.vim and the release workflow), mkzip.py
Makefile                           wraps them: make test / make lint / make dist
.github/workflows/release.yml    builds the .vmb for vim.org on tag push: runtime
                                 files only (plugin/, autoload/, doc/, README,
                                 LICENSE); never ship tests/, scripts/, AGENTS.md.
                                 No CI test workflow — verify locally (make test,
                                 make lint) before pushing.
```

## Verify before pushing

```bash
make test    # headless suite: vim -Nu tests/minimal.vim -n -es -S tests/run_tests.vim
make lint    # vint .  (needs: pip install vim-vint "setuptools<81")
make dist    # build/ollama-fim-<version>.vmb + .zip (version = latest git tag;
             # override: make dist VERSION=1.4.1). The .zip is for the vim.org
             # upload form; the .vmb matches the GitHub release asset.
```

`make test` exits nonzero and prints per-test results on failure. To test
against a specific Vim: `VIM=/path/to/vim make test`. Tests must not hit the
network; they drive `fim_ollama#ui#*` / `fim_ollama#core#*` directly with
`popup_atcursor` (works headless under `vim -es`).

When adding a feature: add tests under `tests/test_*.vim` (register with
`RegisterTest(name, Fn)`), update README + `doc/fim_ollama.txt`, and add a
CHANGELOG entry under `[Unreleased]`.

## Conventions

- Vim script, single quotes preferred; keep functions `abort`; script-local
  state in `s:` vars declared at the top of the file.
- User options are `g:fim_ollama_*` with defaults set in
  `plugin/fim_ollama.vim`; read them via `s:get()` in core.
- Mappings are `<Plug>(Fim*)` with opt-out `g:fim_ollama_map_*` flags; accept
  handlers are `<expr>` and must pass the key through (e.g. `return
  "\<C-Right>"`) when no suggestion is visible.
- Suggestions are stored as one string in `ui.vim`'s `s:ghost_text`; accept
  paths live in `core.vim` and must keep `s:last_accepted_text`, the accept
  lock, and `s:pending_remainder` (partial accept) consistent.
- Run `vint .` clean; `scriptencoding utf-8` first line in files with
  multibyte chars.
