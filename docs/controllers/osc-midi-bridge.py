#!/usr/bin/env python3
"""Video Toy -> MIDI bridge.

Listens for the toy's outgoing OSC (Settings -> OSC out, default UDP 9001)
and turns /vt/midi/note_on, /vt/midi/note_off and /vt/midi/cc into MIDI on
a virtual port called "Video Toy" (macOS / Linux; on Windows point it at a
loopMIDI port with --port). Everything else (/vt/event/*) is printed.

    pip install mido python-rtmidi
    python3 osc-midi-bridge.py [--listen 9001] [--port "Video Toy"]

Then pick "Video Toy" as a MIDI input in the synth / DAW.
"""
import argparse
import socket
import struct
import sys

try:
    import mido
except ImportError:  # pragma: no cover
    sys.exit("pip install mido python-rtmidi")


def _read_string(data, pos):
    end = data.index(b"\0", pos)
    s = data[pos:end].decode("utf-8", "replace")
    pos = end + 1
    pos += (4 - pos % 4) % 4
    return s, pos


def parse(data):
    """One OSC message (or the messages of a #bundle) -> [(address, [args])]."""
    if data.startswith(b"#bundle"):
        out, pos = [], 16
        while pos + 4 <= len(data):
            (size,) = struct.unpack(">i", data[pos:pos + 4])
            pos += 4
            out += parse(data[pos:pos + size])
            pos += size
        return out
    address, pos = _read_string(data, 0)
    tags, pos = _read_string(data, pos) if pos < len(data) and data[pos:pos + 1] == b"," else (",", pos)
    args = []
    for t in tags[1:]:
        if t == "i":
            (v,) = struct.unpack(">i", data[pos:pos + 4]); pos += 4
        elif t == "f":
            (v,) = struct.unpack(">f", data[pos:pos + 4]); pos += 4
        elif t == "s":
            v, pos = _read_string(data, pos)
        elif t == "T":
            v = True
        elif t == "F":
            v = False
        else:
            v = None
        args.append(v)
    return [(address, args)]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--listen", type=int, default=9001, help="UDP port the toy sends to")
    ap.add_argument("--port", default="Video Toy", help="MIDI port name (virtual on macOS / Linux)")
    ap.add_argument("--no-virtual", action="store_true", help="open an existing port instead of creating one")
    a = ap.parse_args()
    out = mido.open_output(a.port) if a.no_virtual else mido.open_output(a.port, virtual=True)
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.bind(("0.0.0.0", a.listen))
    print(f"listening on UDP {a.listen} -> MIDI '{a.port}'  (Ctrl+C stops)")
    while True:
        data, _ = sock.recvfrom(4096)
        for address, args in parse(data):
            try:
                if address == "/vt/midi/note_on":
                    ch, note, vel = (int(x) for x in args[:3])
                    out.send(mido.Message("note_on", channel=ch - 1, note=note, velocity=vel))
                elif address == "/vt/midi/note_off":
                    ch, note = (int(x) for x in args[:2])
                    out.send(mido.Message("note_off", channel=ch - 1, note=note, velocity=0))
                elif address == "/vt/midi/cc":
                    ch, cc, val = (int(x) for x in args[:3])
                    out.send(mido.Message("control_change", channel=ch - 1, control=cc, value=val))
                else:
                    print(address, args)
            except (ValueError, IndexError) as e:
                print("bad message", address, args, e)


if __name__ == "__main__":
    main()
