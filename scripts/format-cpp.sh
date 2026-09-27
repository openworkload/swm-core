#!/usr/bin/env bash
# Format (or check) C++ sources under c_src/ with clang-format.
# Prefer clang-format-14 so results match skyport-dev and CI (same as swm-sched).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

MODE="${1:-format}"
case "$MODE" in
  format|check) ;;
  -h|--help)
    echo "Usage: $0 [format|check]"
    echo "  format  Rewrite c_src/ in place (default)"
    echo "  check   Exit non-zero if any file would change"
    exit 0
    ;;
  *)
    echo "Unknown mode: $MODE (use format or check)" >&2
    exit 2
    ;;
esac

pick_clang_format() {
  local candidate
  if [[ -n "${CLANG_FORMAT:-}" ]]; then
    if command -v "$CLANG_FORMAT" >/dev/null 2>&1; then
      echo "$CLANG_FORMAT"
      return 0
    fi
    echo "CLANG_FORMAT=$CLANG_FORMAT not found on PATH" >&2
    return 1
  fi
  # Pin to 14 when available (skyport-dev / CI). Avoid mixing major versions.
  for candidate in clang-format-14 clang-format-15 clang-format-16 clang-format-17 clang-format-18 clang-format; do
    if command -v "$candidate" >/dev/null 2>&1; then
      echo "$candidate"
      return 0
    fi
  done
  return 1
}

CF="$(pick_clang_format)" || {
  echo "clang-format not found. Install clang-format-14 (e.g. apt install clang-format-14) or set CLANG_FORMAT." >&2
  exit 1
}

mapfile -t FILES < <(find c_src -type f \( -name '*.cpp' -o -name '*.h' -o -name '*.hpp' -o -name '*.cc' \) | sort)
if [[ ${#FILES[@]} -eq 0 ]]; then
  echo "No C++ sources found under c_src/"
  exit 0
fi

echo "Using $($CF --version)"

if [[ "$MODE" == "check" ]]; then
  "$CF" --dry-run --Werror "${FILES[@]}"
  echo "All ${#FILES[@]} files match .clang-format"
else
  "$CF" -i "${FILES[@]}"
  echo "Formatted ${#FILES[@]} files"
fi
