#!/usr/bin/env bash

set -euo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
BACKUP_STAMP="$(date +%Y%m%d-%H%M%S)"
DESTINATIONS=()

info() {
  printf '%s\n' "$*"
}

warn() {
  printf 'aviso: %s\n' "$*" >&2
}

die() {
  printf 'erro: %s\n' "$*" >&2
  exit 1
}

configure_destinations() {
  local include_legacy_codex="${1:-0}"

  DESTINATIONS=(
    "$HOME/.agents/skills"
    "$HOME/.claude/skills"
  )

  if [[ "$include_legacy_codex" == "1" ]]; then
    DESTINATIONS+=("$HOME/.codex/skills")
  fi
}

prepare_destination() {
  local destination="$1"
  local resolved=""

  if [[ -L "$destination" ]]; then
    resolved="$(readlink -f -- "$destination" 2>/dev/null || true)"
    case "$resolved" in
      "$REPO_ROOT"|"$REPO_ROOT"/*)
        die "$destination aponta para dentro deste repositorio ($resolved); remova esse link antes de continuar"
        ;;
    esac
  fi

  mkdir -p -- "$destination"
}

backup_target() {
  local target="$1"
  local destination_root
  local backup_dir

  destination_root="$(basename -- "$(dirname -- "$(dirname -- "$target")")")"
  backup_dir="$HOME/.agent-skills-backups/$BACKUP_STAMP/$destination_root"
  mkdir -p -- "$backup_dir"
  mv -- "$target" "$backup_dir/$(basename -- "$target")"
  info "backup: $target -> $backup_dir/$(basename -- "$target")"
}

link_skill() {
  local source_dir="$1"
  local destination="$2"
  local replace_existing="${3:-0}"
  local name
  local target
  local source_resolved
  local target_resolved=""

  [[ -f "$source_dir/SKILL.md" ]] || die "SKILL.md nao encontrado em $source_dir"

  source_resolved="$(cd -- "$source_dir" && pwd -P)"
  name="$(basename -- "$source_dir")"
  target="$destination/$name"

  if [[ -L "$target" ]]; then
    target_resolved="$(readlink -f -- "$target" 2>/dev/null || true)"
    if [[ "$target_resolved" == "$source_resolved" ]]; then
      info "ok: $target ja aponta para $source_resolved"
      return 0
    fi
  fi

  if [[ -e "$target" || -L "$target" ]]; then
    if [[ "$replace_existing" != "1" ]]; then
      warn "$target ja existe; mantido sem alteracao (use --replace para criar backup e substituir)"
      return 0
    fi
    backup_target "$target"
  fi

  ln -s -- "$source_resolved" "$target"
  info "link: $target -> $source_resolved"
}

is_link_to() {
  local target="$1"
  local source_dir="$2"
  local target_resolved=""
  local source_resolved

  [[ -L "$target" ]] || return 1
  target_resolved="$(readlink -f -- "$target" 2>/dev/null || true)"
  source_resolved="$(cd -- "$source_dir" && pwd -P)"
  [[ "$target_resolved" == "$source_resolved" ]]
}

remove_link_to() {
  local target="$1"
  local source_dir="$2"

  if is_link_to "$target" "$source_dir"; then
    unlink -- "$target"
    info "removido: $target"
    return 0
  fi

  if [[ -e "$target" || -L "$target" ]]; then
    warn "$target nao aponta para $source_dir; mantido sem alteracao"
  else
    info "ausente: $target"
  fi
}
