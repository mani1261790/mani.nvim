# Neovim Config

This repository contains a single-file Neovim setup centered on `init.lua`.

## Included

- `init.lua`
- `lazy-lock.json`
- `terminal-hooks.zsh`

## Excluded

The repository does not track local-only files such as:

- `plugged/`
- `.DS_Store`
- `.nvimlog`
- swap and temp files

## Requirements

- Neovim 0.11+
- `git`
- a Nerd Font-enabled terminal is recommended

## Install

```bash
mkdir -p ~/.config
git clone <your-repo-url> ~/.config/nvim
nvim
```

On first launch, plugins are installed automatically through `lazy.nvim`.

## Key points

- Left sidebar: file tree + terminal list
- Right side: editor on top, one shared terminal panel on bottom
- Terminal list can create, switch, and close terminals
- `F1` to `F4`: jump across panels
- `F7`: soft restart in the same working directory
- `F8` / `Shift-F8`: cycle panels forward/backward

## Publish

```bash
cd ~/.config/nvim
git init
git add init.lua lazy-lock.json terminal-hooks.zsh .gitignore README.md
git commit -m "Publish Neovim config"
```

Then create a GitHub repo and push:

```bash
git branch -M main
git remote add origin <your-github-repo-url>
git push -u origin main
```
