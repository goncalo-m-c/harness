#!/usr/bin/env bash
# Print review rule files that apply to a worktree diff (one path per line).
set -euo pipefail

RULES_DIR="${HOME}/.agents/skills/review-rules/rules"

rule_for_file() {
  local file="$1"
  case "${file}" in
    *.py|*.pyi) echo python ;;
    *.sh|*.bash|*.zsh) echo bash ;;
    *.tf|*.tfvars|*.hcl) echo terraform ;;
    *) return 0 ;;
  esac
}

main() {
  local worktree="$1" base="$2"
  printf '%s\n' "${RULES_DIR}/common.md"
  git -C "${worktree}" diff --name-only --diff-filter=d "${base}...HEAD" \
    | while read -r file; do rule_for_file "${file}"; done \
    | sort -u \
    | while read -r lang; do
        [[ -n "${lang}" && -f "${RULES_DIR}/${lang}.md" ]] && printf '%s\n' "${RULES_DIR}/${lang}.md"
      done
}

main "$@"
