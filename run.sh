#!/usr/bin/env bash
# ./run.sh [play] [low|medium|high|full]   play (optionally lock the quality level)
# ./run.sh test       headless smoke tests + self-test + a --safe launch check (no network, no quota)
# ./run.sh safe       play with no MIDI, OSC, camera or microphone (--safe)
# ./run.sh capture    screenshot every screen into out/
# ./run.sh import     (re)import assets headlessly
# ./run.sh templates  write TouchOSC / Launchpad / APC mini templates into docs/controllers
# ./run.sh check      capture the deterministic reference shots and pixel-diff them (exit 1 on regression)
# ./run.sh reference  re-record the reference shots (after an intentional visual change)
# ./run.sh clip [s]   render the autosaved stage state offline to out/clip-*.avi (Movie Maker, 60 fps)
# ./run.sh keycard    regenerate docs/key-card.png + docs/KEYS.md from src/keys.gd (windowed)
# ./run.sh export     build out/Video Toy.app (macOS, ad-hoc signed, privacy strings) and self-test the bundle
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
  safe)    audio_override; exec "$G" --path . -- --safe ;;
  test)    "$G" --headless --path . --import >/dev/null 2>&1 || true
           # perl alarm = portable timeout: a script that errors before quit() would hang forever
           perl -e 'alarm 120; exec @ARGV' "$G" --headless --path . -s tests/smoke.gd \
             && perl -e 'alarm 120; exec @ARGV' "$G" --headless --path . -- --selftest \
             && { out="$(perl -e 'alarm 60; exec @ARGV' "$G" --headless --path . -- --safe --safecheck 2>&1)"
                  echo "$out" | grep "^SAFECHECK"
                  echo "$out" | grep -q "SAFECHECK active=true midi_inputs=0 osc_listening=false mic=false webcam=off log=true" || { echo "FAIL safe mode" >&2; exit 1; }; } ;;
  capture) audio_override; mkdir -p out; exec "$G" --path . -- --capture "$(pwd)/out" ${2:+--only "$2"} ;;
  import)  exec "$G" --headless --path . --import ;;
  templates) exec "$G" --headless --path . -- --templates "$(pwd)/docs/controllers" ;;
  keycard) audio_override; exec perl -e 'alarm 120; exec @ARGV' "$G" --path . -- --keycard "$(pwd)/docs" ;;
  diff)    exec "$G" --headless --path . -s tests/diff.gd ;;
  export)  # macOS .app into out/, ad-hoc signed, with the privacy strings; then prove the bundle runs
           printf '{"version":"1.0.0","hash":"%s","date":"%s"}\n' "$(git rev-parse --short=12 HEAD 2>/dev/null || echo nogit)" "$(date +%Y-%m-%d)" > build.json
           mkdir -p out; rm -rf "out/Video Toy.app"
           "$G" --headless --path . --export-release "macOS" "out/Video Toy.app" 2>&1 | grep -iE "error|warn|DONE" | grep -v "copy symlink" || true
           app="out/Video Toy.app"
           test -x "$app/Contents/MacOS/Video Toy" || { echo "export failed: no binary" >&2; exit 1; }
           # Godot copies Syphon.framework with its symlinks resolved, which breaks the seal
           # (macOS then SIGKILLs the app). Put a faithful copy back and re-sign ad hoc.
           rm -rf "$app/Contents/Frameworks/Syphon.framework"
           ditto addons/godot-syphon/bin/Syphon.framework "$app/Contents/Frameworks/Syphon.framework"
           for f in "$app"/Contents/Frameworks/*.dylib "$app/Contents/Frameworks/Syphon.framework"; do
             codesign --force --sign - "$f" 2>&1 | grep -v "replacing existing signature" || true
           done
           codesign --force --sign - --entitlements export/macos.entitlements "$app" 2>&1 | grep -v "replacing existing signature" || true
           codesign --verify --deep --strict "$app" && echo "codesign: valid" || { echo "codesign: INVALID" >&2; exit 1; }
           echo "plist: mic='$(/usr/libexec/PlistBuddy -c 'Print :NSMicrophoneUsageDescription' "$app/Contents/Info.plist" 2>/dev/null)'"
           echo "plist: cam='$(/usr/libexec/PlistBuddy -c 'Print :NSCameraUsageDescription' "$app/Contents/Info.plist" 2>/dev/null)'"
           echo "frameworks: $(ls "$app/Contents/Frameworks" 2>/dev/null | tr '\n' ' ')"
           codesign -dv "$app" 2>&1 | grep -E "Signature|Identifier" | head -2 || true
           echo "size: $(du -sh "$app" | cut -f1)"
           echo "selftest from the bundle:"
           st="$(perl -e 'alarm 240; exec @ARGV' "$app/Contents/MacOS/Video Toy" --headless -- --selftest 2>&1 || true)"
           echo "  PASS blocks: $(grep -c '^PASS' <<<"$st" || true)   errors: $(grep -cE 'ERROR|FAIL' <<<"$st" || true)"
           grep -E "^FAIL|ERROR" <<<"$st" | head -3 || true
           echo "$app" ;;
  clip)    # render the autosaved state (the last thing on stage) to an AVI: ./run.sh clip [seconds]
           audio_override; out="$(pwd)/out/clip-$(date +%Y%m%d-%H%M%S).avi"; mkdir -p out
           "$G" --path . --write-movie "$out" --fixed-fps 60 -- --clip "${2:-20}" >/dev/null 2>&1
           echo "$out" ;;
  check)   # capture the reference shots, then compare them with tests/reference
           audio_override; mkdir -p out
           "$G" --path . -- --capture "$(pwd)/out" --only start,settings,menu,attribution,search,ref_stage,ref_crt,ref_panel,ref_help >/dev/null 2>&1
           exec "$G" --headless --path . -s tests/diff.gd ;;
  reference) # (re)record the reference shots from the current build
           audio_override; mkdir -p out tests/reference
           "$G" --path . -- --capture "$(pwd)/out" --only start,settings,menu,attribution,search,ref_stage,ref_crt,ref_panel,ref_help >/dev/null 2>&1
           for f in start settings menu attribution search ref_stage ref_crt ref_panel ref_help; do
             cp "out/$f.png" "tests/reference/$f.png"
             sips -z 540 960 "tests/reference/$f.png" --out "tests/reference/$f.png" >/dev/null 2>&1 || true   # half size keeps the repo small; the diff compares at 240x135
           done
           echo "reference shots updated: $(ls tests/reference)" ;;
  *) echo "usage: $0 [play|test|capture [shot]|import|templates|check|reference|diff]" >&2; exit 2 ;;
esac
