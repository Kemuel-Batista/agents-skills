#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"

replace_existing=0
include_legacy_codex=0

usage() {
  cat <<'EOF'
Uso: ./scripts/install.sh [opcoes]

Cria links para todas as skills proprias encontradas em skills/.

Opcoes:
  --replace       Faz backup de um destino conflitante antes de substitui-lo.
  --legacy-codex  Tambem instala em ~/.codex/skills (local legado).
  -h, --help      Mostra esta ajuda.
EOF
}

while (($#)); do
  case "$1" in
    --replace)
      replace_existing=1
      ;;
    --legacy-codex)
      include_legacy_codex=1
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      die "opcao desconhecida: $1"
      ;;
  esac
  shift
done

configure_destinations "$include_legacy_codex"
for destination in "${DESTINATIONS[@]}"; do
  prepare_destination "$destination"
done

mapfile -d '' skill_files < <(
  find "$REPO_ROOT/skills" -mindepth 2 -type f -name SKILL.md -print0 | sort -z
)

if ((${#skill_files[@]} == 0)); then
  info "Nenhuma skill propria encontrada em $REPO_ROOT/skills."
  info "Crie skills/<nome>/SKILL.md e execute este script novamente."
  exit 0
fi

declare -A seen_names=()
for skill_file in "${skill_files[@]}"; do
  skill_dir="$(dirname -- "$skill_file")"
  skill_name="$(basename -- "$skill_dir")"
  if [[ -n "${seen_names[$skill_name]:-}" ]]; then
    die "duas skills proprias usam o nome '$skill_name': ${seen_names[$skill_name]} e $skill_dir"
  fi
  seen_names[$skill_name]="$skill_dir"
done

for skill_file in "${skill_files[@]}"; do
  skill_dir="$(dirname -- "$skill_file")"
  for destination in "${DESTINATIONS[@]}"; do
    link_skill "$skill_dir" "$destination" "$replace_existing"
  done
done

info "Concluido. Edicoes dentro de skills/ passam a valer imediatamente pelos links."
