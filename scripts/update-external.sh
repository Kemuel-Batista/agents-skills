#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"

MANIFEST="$REPO_ROOT/external/repos.tsv"
EXTERNAL_ROOT="$REPO_ROOT/external"

[[ -f "$MANIFEST" ]] || die "manifesto nao encontrado: $MANIFEST"
mkdir -p -- "$EXTERNAL_ROOT"

declare -A updated_repositories=()

update_repository() {
  local name="$1"
  local path="$EXTERNAL_ROOT/$name"
  local branch=""

  if [[ ! -d "$path" ]] || ! git -C "$path" rev-parse --git-dir >/dev/null 2>&1; then
    return 1
  fi

  if [[ -n "$(git -C "$path" status --porcelain)" ]]; then
    warn "$name possui alteracoes locais; atualizacao ignorada"
    updated_repositories[$name]=1
    return 0
  fi

  branch="$(git -C "$path" symbolic-ref --quiet --short HEAD 2>/dev/null || true)"
  if [[ -z "$branch" ]]; then
    info "fetch: $name (HEAD destacado)"
    git -C "$path" fetch --all --prune
  else
    info "pull: $name ($branch)"
    git -C "$path" pull --ff-only
  fi
  updated_repositories[$name]=1
}

while IFS=$'\t' read -r name url extra; do
  [[ -n "$name" ]] || continue
  [[ "$name" == \#* ]] && continue
  [[ -n "$url" ]] || die "URL ausente para '$name' em $MANIFEST"
  [[ -z "${extra:-}" ]] || die "linha invalida para '$name' em $MANIFEST; use nome<TAB>url"
  [[ "$name" =~ ^[A-Za-z0-9._-]+$ ]] || die "nome de diretorio invalido no manifesto: $name"

  path="$EXTERNAL_ROOT/$name"
  if [[ -e "$path" ]] && ! git -C "$path" rev-parse --git-dir >/dev/null 2>&1; then
    warn "$path existe, mas nao e um repositorio Git; mantido sem alteracao"
    updated_repositories[$name]=1
    continue
  fi

  if [[ ! -e "$path" ]]; then
    info "clone: $name"
    git clone --filter=blob:none -- "$url" "$path"
  fi
  update_repository "$name"
done < "$MANIFEST"

for path in "$EXTERNAL_ROOT"/*; do
  [[ -d "$path" ]] || continue
  name="$(basename -- "$path")"
  [[ -z "${updated_repositories[$name]:-}" ]] || continue
  if git -C "$path" rev-parse --git-dir >/dev/null 2>&1; then
    update_repository "$name"
  fi
done

info "Concluido. Skills ja instaladas refletem as atualizacoes pelos symlinks."

