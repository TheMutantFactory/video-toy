#!/usr/bin/env bash
# ./run.sh [play] [low|medium|high|full]   play (optionally lock the quality level)
# ./run.sh test       headless smoke tests (no network, no quota)
# ./run.sh capture    screenshot every screen into out/
# ./run.sh import     (re)import assets headlessly
# ./run.sh templates  write TouchOSC / Launchpad / APC mini templates into docs/controllers
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

# Godot 4.7 needs audio/driver/enable_input=true for the microphone, but on a
# machine with NO input device that setting makes CoreAudio fail and Godot falls
# back to a silent dummy driver (no file playback either). On macOS, detect that
# and write a gitignored override.cfg turning input off; remove it otherwise.
audio_override() {
  if [[ "$(uname)" == "Darwin" ]]; then
    if system_profiler SPAudioDataType 2>/dev/null | grep -q "Input Channels"; then
      rm -f override.cfg
    else
      printf '[audio]\ndriver/enable_input=false\n' > override.cfg
      echo "note: no audio input device found; microphone disabled (override.cfg)" >&2
    fi
  fi
}

case "${1:-play}" in
  play)    audio_override; exec "$G" --path . -- ${2:+--quality "$2"} ;;
  test)    "$G" --headless --path . --import >/dev/null 2>&1 || true
           # perl alarm = portable timeout: a script that errors before quit() would hang forever
           perl -e 'alarm 120; exec @ARGV' "$G" --headless --path . -s tests/smoke.gd \
             && perl -e 'alarm 120; exec @ARGV' "$G" --headless --path . -- --selftest ;;
  capture) audio_override; mkdir -p out; exec "$G" --path . -- --capture "$(pwd)/out" ${2:+--only "$2"} ;;
  import)  exec "$G" --headless --path . --import ;;
  templates) exec "$G" --headless --path . -- --templates "$(pwd)/docs/controllers" ;;
  *) echo "usage: $0 [play|test|capture|import]" >&2; exit 2 ;;
esac
