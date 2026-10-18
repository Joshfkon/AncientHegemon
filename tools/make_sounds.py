#!/usr/bin/env python3
"""Synthesizes the battle sounds (placeholders until real recordings exist).

Writes 16-bit mono WAVs to AncientHegemon/Resources/Sounds/. Deterministic: same files every run.

    python3 tools/make_sounds.py
"""
import math
import os
import random
import struct
import wave

RATE = 44100
OUT = os.path.join(os.path.dirname(__file__), "..", "AncientHegemon", "Resources", "Sounds")


def write(name, samples, gain=0.8):
    peak = max(1e-9, max(abs(s) for s in samples))
    data = b"".join(struct.pack("<h", int(32767 * gain * s / peak)) for s in samples)
    with wave.open(os.path.join(OUT, name + ".wav"), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(data)


def fade(samples, ms=8):
    n = int(RATE * ms / 1000)
    for i in range(min(n, len(samples))):
        samples[i] *= i / n
        samples[-1 - i] *= i / n
    return samples


def horn_note(freq, length, attack=0.07, release=0.18, vibrato=4.5):
    """A bronze horn: a few harmonics, a soft attack, a slight swell and vibrato."""
    out = []
    phase = 0.0
    for i in range(int(RATE * length)):
        t = i / RATE
        bend = 1 - 0.03 * math.exp(-t * 18)  # the lip settles onto the note
        f = freq * bend * (1 + 0.004 * math.sin(2 * math.pi * vibrato * t))
        phase += 2 * math.pi * f / RATE
        tone = (math.sin(phase) + 0.55 * math.sin(2 * phase) + 0.35 * math.sin(3 * phase)
                + 0.18 * math.sin(4 * phase) + 0.08 * math.sin(5 * phase))
        env = min(1, t / attack) * min(1, (length - t) / release)
        out.append(tone * env * (0.85 + 0.15 * min(1, t / 0.4)))
    return out


def concat(*parts):
    out = []
    for p in parts:
        out += p
    return out


def clash(rng):
    """Bronze on bronze: inharmonic ringing partials over a short noise burst."""
    length = 0.55
    partials = [(523, 1.0, 0.16), (1247, 0.7, 0.10), (2131, 0.5, 0.07), (3389, 0.35, 0.05), (4610, 0.2, 0.03)]
    out = []
    for i in range(int(RATE * length)):
        t = i / RATE
        s = sum(a * math.sin(2 * math.pi * f * t) * math.exp(-t / tau) for f, a, tau in partials)
        s += (rng.random() * 2 - 1) * 1.4 * math.exp(-t / 0.012)
        out.append(s)
    # A second, softer blow a moment later: a line of shields, not one.
    delay = int(RATE * 0.07)
    for i in range(len(out) - delay):
        out[i + delay] += 0.5 * out[i]
    return fade(out)


def arrows(rng):
    """A volley: several filtered-noise whooshes, slightly staggered."""
    length = 0.7
    out = [0.0] * int(RATE * length)
    for k in range(6):
        start = int(RATE * (0.02 + 0.06 * k + rng.random() * 0.03))
        dur = 0.32 + rng.random() * 0.1
        low = 0.0
        for i in range(int(RATE * dur)):
            t = i / RATE
            cutoff = 0.05 + 0.25 * math.sin(math.pi * t / dur)  # the pitch rises and falls as it passes
            low += cutoff * ((rng.random() * 2 - 1) - low)
            env = math.sin(math.pi * t / dur) ** 2
            if start + i < len(out):
                out[start + i] += low * env * (0.6 + 0.4 * rng.random())
    return fade(out)


def main():
    os.makedirs(OUT, exist_ok=True)
    rng = random.Random(1200)
    # The call to battle: a rising horn call.
    write("horn", concat(horn_note(196, 0.45), horn_note(294, 0.95)), gain=0.6)
    write("clash", clash(rng), gain=0.55)
    write("arrows", arrows(rng), gain=0.5)
    # Victory: a bright arpeggio. Defeat: a falling, darker call.
    write("victory", concat(horn_note(294, 0.22), horn_note(370, 0.22), horn_note(440, 0.22), horn_note(587, 0.9)), gain=0.6)
    write("defeat", concat(horn_note(220, 0.5), horn_note(196, 0.5), horn_note(147, 1.1)), gain=0.55)
    print("wrote", sorted(os.listdir(OUT)))


if __name__ == "__main__":
    main()
