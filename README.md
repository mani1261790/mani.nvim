# mani.nvim

`mani.nvim` は、`init.lua` 1 ファイルを中心に構成した、導入しやすい Neovim 設定です。  
ファイルツリー、補完、LSP、ターミナル、ノートブック操作までまとめて使えるようにしてあります。

## 特徴

- `init.lua` 中心のシンプルな構成
- 左側にファイルツリー、右側に編集エリアという分かりやすい画面構成
- 下部ターミナルでコマンド実行をしながら編集できる
- LSP による補完、定義ジャンプ、診断表示に対応
- `ipynb` を開いて扱いやすくするノートブック向け機能を用意
- Git のブランチや差分を Neovim 上で確認しやすい

## 必要環境

- Neovim 0.11 以上
- `git`
- Nerd Font 対応フォント
- `python3`

ノートブック機能も使いたい場合は、Jupyter 関連の Python パッケージも必要です。

## インストール

既存の設定を残したい場合は、先に `~/.config/nvim` を退避してください。

最短で試すだけなら、`init.lua` だけを `~/.config/nvim/` に置けば動きます。

```bash
mkdir -p ~/.config/nvim
curl -L https://raw.githubusercontent.com/mani1261790/mani.nvim/main/init.lua -o ~/.config/nvim/init.lua
nvim
```

設定をそのまま再現したい場合は、リポジトリごと入れる方法が向いています。

```bash
git clone https://github.com/mani1261790/mani.nvim.git ~/.config/nvim
nvim
```

初回起動時に `lazy.nvim` 経由でプラグインが自動インストールされます。  
インストール完了後、Neovim を開き直すと安定して使い始めやすいです。

## 同梱ファイル

- `init.lua`: メインの設定ファイルです
- `lazy-lock.json`: プラグインのバージョンを固定し、環境差分を減らします
- `terminal-hooks.zsh`: Neovim 内ターミナルで作業ディレクトリ連携や `open` の補助を行います

## 画面構成

- 左: ファイルツリーとターミナル一覧
- 右上: エディタ
- 右下: 共通ターミナル

VS Code に近い感覚で、ファイルを開きながらターミナルも併用できます。

## 基本キー

- `F1`: ファイルツリーへ移動
- `F2`: エディタへ移動
- `F3`: 下部ターミナルへ移動
- `F4`: ターミナル一覧へ移動
- `F7`: 現在の作業ディレクトリのまま Neovim を再起動
- `F8`: 次のパネルへ移動
- `Shift-F8`: 前のパネルへ移動

## ノートブックを使う場合

`.ipynb` をそのまま扱うための設定を入れています。  
セル実行まで使いたい場合は、Python 側で Jupyter 関連パッケージを入れてください。

例:

```bash
python3 -m pip install --user pynvim jupyter_client nbformat jupytext ipykernel
```

環境によっては、Neovim 側でリモートプラグインの更新が必要です。

```bash
nvim --headless "+UpdateRemotePlugins" +qa
```

## この設定でできること

- ファイルを開く、検索する、編集する
- 補完を使いながらコードを書く
- 定義ジャンプや診断確認を行う
- ターミナルでコマンドを実行しながら作業する
- Git の差分を確認する
- Jupyter ノートブックを編集しやすい形で扱う

Neovim をこれから使い始める人でも、最低限のセットアップでそのまま開発に入りやすい構成を目指しています。
