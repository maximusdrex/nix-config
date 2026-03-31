#!/usr/bin/env bash
set -euo pipefail

# Lightweight recipient policy audit for sops/clan secret files.
#
# Policy knobs:
#   REQUIRED_OPERATOR_RECIPIENTS="age1... age1..."   (space-separated)
#   REQUIRED_RECOVERY_RECIPIENTS="age1..."           (space-separated)
#
# Exit code:
#   0 -> all checked files satisfy configured policy
#   2 -> one or more files missing required recipient classes

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

mapfile -t SECRET_FILES < <(find vars sops/secrets -type f -name secret 2>/dev/null | sort)

if [[ ${#SECRET_FILES[@]} -eq 0 ]]; then
  echo "No secret files found under vars/ or sops/secrets/."
  exit 0
fi

read -r -a OPERATOR_RECIPS <<< "${REQUIRED_OPERATOR_RECIPIENTS:-}"
read -r -a RECOVERY_RECIPS <<< "${REQUIRED_RECOVERY_RECIPIENTS:-}"

if [[ ${#OPERATOR_RECIPS[@]} -eq 0 && ${#RECOVERY_RECIPS[@]} -eq 0 ]]; then
  echo "NOTE: no REQUIRED_OPERATOR_RECIPIENTS or REQUIRED_RECOVERY_RECIPIENTS set; audit is informational only."
fi

fail=0
for f in "${SECRET_FILES[@]}"; do
  recips="$(grep -Eo '"recipient"\s*:\s*"age1[0-9a-z]+"' "$f" | sed -E 's/.*"(age1[0-9a-z]+)"/\1/' || true)"

  if [[ -z "$recips" ]]; then
    echo "[WARN] $f: no age recipients parsed"
    fail=1
    continue
  fi

  missing_operator=1
  if [[ ${#OPERATOR_RECIPS[@]} -gt 0 ]]; then
    for r in "${OPERATOR_RECIPS[@]}"; do
      if grep -qx "$r" <<< "$recips"; then
        missing_operator=0
        break
      fi
    done
  else
    missing_operator=0
  fi

  missing_recovery=1
  if [[ ${#RECOVERY_RECIPS[@]} -gt 0 ]]; then
    for r in "${RECOVERY_RECIPS[@]}"; do
      if grep -qx "$r" <<< "$recips"; then
        missing_recovery=0
        break
      fi
    done
  else
    missing_recovery=0
  fi

  if [[ $missing_operator -eq 1 || $missing_recovery -eq 1 ]]; then
    echo "[FAIL] $f"
    [[ $missing_operator -eq 1 ]] && echo "       missing required operator recipient(s)"
    [[ $missing_recovery -eq 1 ]] && echo "       missing required recovery recipient(s)"
    fail=1
  fi
done

if [[ $fail -eq 1 ]]; then
  echo
  echo "Recipient audit failed."
  echo "Hint: set REQUIRED_OPERATOR_RECIPIENTS and REQUIRED_RECOVERY_RECIPIENTS when running this script."
  exit 2
fi

echo "Recipient audit passed."
