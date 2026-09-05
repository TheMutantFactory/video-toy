#!/usr/bin/env bash
# ./run.sh            play
# ./run.sh test       headless smoke tests (no network, no quota)
# ./run.sh capture    screenshot every screen into out/
# ./run.sh import     (re)import assets headlessly
set -euo pipefail
cd "$(dirname "$0")"

find_godot() {
  if [[ -n "${GODOT:-}" ]]; then echo "$GODOT"; return; fi
  for c in godot4 godot /Applications/Godot.app/Contents/MacOS/Godot \
           "$HOME/Applications/Godot.app/Contents/MacOS/Godot"; do
    if command -v "$c" >/dev/null 2>&1 || [[ -x "$c" ]]; then echo "$c"; return; fi
  done
  echo "Godot 4.7 not found; set GODOT=/path/to/godot" >&2; exit 1
}
G="$(find_godot)"

case "${1:-play}" in
  play)    exec "$G" --path . ;;
  test)    "$G" --headless --path . --import >/dev/null 2>&1 || true
           # perl alarm = portable timeout: a script that errors before quit() would hang forever
           perl -e 'alarm 120; exec @ARGV' "$G" --headless --path . -s tests/smoke.gd \
             && perl -e 'alarm 120; exec @ARGV' "$G" --headless --path . -- --selftest ;;
  capture) mkdir -p out; exec "$G" --path . -- --capture "$(pwd)/out" ;;
  import)  exec "$G" --headless --path . --import ;;
  *) echo "usage: $0 [play|test|capture|import]" >&2; exit 2 ;;
esac
