#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"

action="install"
replace_existing=0
include_legacy_codex=0
install_all=0
repo_filter=""
selectors=()
remove_selectors=()

usage() {
  cat <<'EOF'
Uso:
  ./scripts/install-external.sh                 # selecao interativa
  ./scripts/install-external.sh --list
  ./scripts/install-external.sh <skill> [...]
  ./scripts/install-external.sh --all [--repo <repositorio>]
  ./scripts/install-external.sh --remove <skill> [--remove <skill> ...]

O seletor pode ser o nome curto (quando unico), repositorio:nome ou o ID
completo mostrado por --list.

Opcoes:
  --list          Lista as skills externas descobertas.
  --installed     Lista somente as skills externas instaladas.
  --all           Instala todas as skills, opcionalmente filtradas por --repo.
  --repo <nome>   Restringe --list ou --all a um repositorio externo.
  --remove <id>   Remove apenas os links da skill informada.
  --replace       Faz backup de um destino conflitante antes de substitui-lo.
  --legacy-codex  Tambem gerencia ~/.codex/skills (local legado).
  -h, --help      Mostra esta ajuda.
EOF
}

while (($#)); do
  case "$1" in
    --list)
      action="list"
      ;;
    --installed)
      action="installed"
      ;;
    --all)
      install_all=1
      ;;
    --repo)
      (($# >= 2)) || die "--repo exige um nome"
      repo_filter="$2"
      shift
      ;;
    --remove)
      (($# >= 2)) || die "--remove exige um seletor"
      action="remove"
      remove_selectors+=("$2")
      shift
      ;;
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
    --)
      shift
      selectors+=("$@")
      break
      ;;
    -*)
      die "opcao desconhecida: $1"
      ;;
    *)
      selectors+=("$1")
      ;;
  esac
  shift
done

configure_destinations "$include_legacy_codex"
for destination in "${DESTINATIONS[@]}"; do
  prepare_destination "$destination"
done

EXTERNAL_ROOT="$REPO_ROOT/external"
mapfile -d '' external_skill_files < <(
  find "$EXTERNAL_ROOT" -mindepth 3 -type f -name SKILL.md -not -path '*/.git/*' -print0 | sort -z
)

if ((${#external_skill_files[@]} == 0)); then
  die "nenhuma skill externa encontrada; execute ./scripts/update-external.sh primeiro"
fi

external_ids=()
external_repos=()
external_names=()
external_dirs=()

for skill_file in "${external_skill_files[@]}"; do
  relative="${skill_file#"$EXTERNAL_ROOT/"}"
  repository="${relative%%/*}"
  skill_dir="$(dirname -- "$skill_file")"
  skill_rel_path="${skill_dir#"$EXTERNAL_ROOT/$repository/"}"
  skill_name="$(basename -- "$skill_dir")"

  external_ids+=("$repository:$skill_rel_path")
  external_repos+=("$repository")
  external_names+=("$skill_name")
  external_dirs+=("$skill_dir")
done

is_installed_index() {
  local index="$1"
  local destination
  local target

  for destination in "${DESTINATIONS[@]}"; do
    target="$destination/${external_names[$index]}"
    if is_link_to "$target" "${external_dirs[$index]}"; then
      return 0
    fi
  done
  return 1
}

print_index() {
  local index="$1"
  local status=" "
  if is_installed_index "$index"; then
    status="x"
  fi
  printf '[%s] %-24s %s\n' "$status" "${external_names[$index]}" "${external_ids[$index]}"
}

resolve_selector() {
  local selector="$1"
  local index
  local matches=()

  RESOLVED_INDEX=""
  for index in "${!external_ids[@]}"; do
    [[ -z "$repo_filter" || "${external_repos[$index]}" == "$repo_filter" ]] || continue
    if [[ "$selector" == "${external_ids[$index]}" \
      || "$selector" == "${external_repos[$index]}:${external_names[$index]}" \
      || "$selector" == "${external_names[$index]}" ]]; then
      matches+=("$index")
    fi
  done

  if ((${#matches[@]} == 0)); then
    warn "skill externa nao encontrada: $selector"
    return 1
  fi
  if ((${#matches[@]} > 1)); then
    warn "seletor ambiguo: $selector; use o ID completo mostrado por --list"
    return 1
  fi

  RESOLVED_INDEX="${matches[0]}"
}

if [[ "$action" == "list" || "$action" == "installed" ]]; then
  for index in "${!external_ids[@]}"; do
    [[ -z "$repo_filter" || "${external_repos[$index]}" == "$repo_filter" ]] || continue
    if [[ "$action" == "installed" ]] && ! is_installed_index "$index"; then
      continue
    fi
    print_index "$index"
  done
  exit 0
fi

if [[ "$action" == "remove" ]]; then
  ((${#remove_selectors[@]} > 0)) || die "informe ao menos uma skill para remover"
  for selector in "${remove_selectors[@]}"; do
    resolve_selector "$selector" || continue
    index="$RESOLVED_INDEX"
    for destination in "${DESTINATIONS[@]}"; do
      remove_link_to "$destination/${external_names[$index]}" "${external_dirs[$index]}"
    done
  done
  exit 0
fi

selected_indexes=()
if ((install_all)); then
  for index in "${!external_ids[@]}"; do
    [[ -z "$repo_filter" || "${external_repos[$index]}" == "$repo_filter" ]] || continue
    selected_indexes+=("$index")
  done
elif ((${#selectors[@]} > 0)); then
  for selector in "${selectors[@]}"; do
    if resolve_selector "$selector"; then
      selected_indexes+=("$RESOLVED_INDEX")
    fi
  done
else
  [[ -t 0 ]] || die "sem terminal interativo; informe uma skill, --all ou --list"
  info "Skills externas disponiveis (x = instalada):"
  visible_indexes=()
  display_number=0
  for index in "${!external_ids[@]}"; do
    [[ -z "$repo_filter" || "${external_repos[$index]}" == "$repo_filter" ]] || continue
    visible_indexes+=("$index")
    ((display_number += 1))
    printf '%3d. ' "$display_number"
    print_index "$index"
  done
  printf 'Numeros para instalar (separados por espaco ou virgula): '
  IFS= read -r answer
  answer="${answer//,/ }"
  for number in $answer; do
    [[ "$number" =~ ^[0-9]+$ ]] || die "selecao invalida: $number"
    ((number >= 1 && number <= ${#visible_indexes[@]})) || die "numero fora da lista: $number"
    selected_indexes+=("${visible_indexes[$((number - 1))]}")
  done
fi

((${#selected_indexes[@]} > 0)) || die "nenhuma skill selecionada"

declare -A installed_indexes=()
for index in "${selected_indexes[@]}"; do
  [[ -z "${installed_indexes[$index]:-}" ]] || continue
  installed_indexes[$index]=1
  for destination in "${DESTINATIONS[@]}"; do
    link_skill "${external_dirs[$index]}" "$destination" "$replace_existing"
  done
done

info "Concluido. Os links acompanham cada atualizacao dos repositorios externos."
