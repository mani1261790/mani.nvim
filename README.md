# nvim-single-file-config

Single-file Neovim configuration built around `init.lua`, with a VS Code-like layout:

- left column: file tree + terminal list
- right column: editor on top + one shared terminal panel on bottom

## Features

- single-file config centered on `init.lua`
- persistent terminal workflow with a terminal list in the sidebar
- one shared terminal panel that switches terminals instead of stacking splits
- cwd sync between terminal and file tree via OSC 7
- notebook-friendly setup with `jupytext`, `molten`, and `NotebookNavigator`
- direct panel navigation keys

## Direct keys

- `F1`: file tree
- `F2`: editor
- `F3`: terminal
- `F4`: terminal list
- `F7`: soft restart in the same working directory
- `F8`: next panel
- `Shift-F8`: previous panel

## Files tracked in this repo

- `init.lua`
- `lazy-lock.json`
- `terminal-hooks.zsh`
- `.gitignore`

## Why `.gitignore` is kept

This config creates or coexists with local-only files that should not be published:

- `plugged/`
- `.DS_Store`
- `.nvimlog`
- swap / backup / temp files

Keeping `.gitignore` in the repo prevents accidental pushes of local plugin installs and machine-specific noise.

## Requirements

- Neovim 0.11+
- `git`
- a terminal with function keys available to Neovim
- Nerd Font recommended

## Install

```bash
git clone https://github.com/mani1261790/nvim-single-file-config.git ~/.config/nvim
nvim
```

On first launch, plugins are installed automatically through `lazy.nvim`.

## Notes

- `Cmd`-based shortcuts are not relied on because many terminal apps intercept them before Neovim receives them.
- The restart command is a soft restart that rebuilds the layout in the current working directory.
