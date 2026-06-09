autoload -Uz add-zsh-hook 2>/dev/null

__nvim_emit_osc7() {
  printf '\033]7;file://%s%s\033\\' "$HOST" "$PWD"
}

__nvim_open_in_editor() {
  printf '\033]51;open:file://%s%s\033\\' "$HOST" "$1"
}

open() {
  if (( $# == 0 || $# > 1 )); then
    command open "$@"
    return
  fi

  case "$1" in
    -*)
      command open "$@"
      return
      ;;
    http://*|https://*|mailto:*|file://*)
      command open "$@"
      return
      ;;
  esac

  local target="${1:A}"
  if [[ -e "$target" ]]; then
    __nvim_open_in_editor "$target"
    return
  fi

  command open "$@"
}

add-zsh-hook -d chpwd __nvim_emit_osc7 2>/dev/null
add-zsh-hook -d precmd __nvim_emit_osc7 2>/dev/null
add-zsh-hook chpwd __nvim_emit_osc7
add-zsh-hook precmd __nvim_emit_osc7
__nvim_emit_osc7
