#!/usr/bin/env python3
"""Composes and renders the soundtrack (Josh: "a soundtrack like CIV").

Original music, synthesized from instruments of the age: a plucked lyre or harp (Karplus-Strong
strings), a double-reed pipe like the aulos, a drone, frame drums and war drums, and bronze horn
calls, in a hall's reverb. Each realm has its own mode and rhythm; there is a title theme and a
war theme. Melodies are composed from seeded motifs (a phrase, its answer, a contrasting
phrase, the return), so the same files come out every run.

Writes 32 kHz stereo WAVs to the scratch folder given (default build/music) and converts them
to AAC .m4a in AncientHegemon/Resources/Music with afconvert.

    python3 tools/make_music.py [scratch-dir]
"""
import math
import os
import random
import struct
import subprocess
import sys
import wave
from array import array

RATE = 32000
HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "AncientHegemon", "Resources", "Music")
SCRATCH = sys.argv[1] if len(sys.argv) > 1 else os.path.join(HERE, "..", "build", "music")

# Modes as semitones above the tonic.
DORIAN = [0, 2, 3, 5, 7, 9, 10]
PHRYGIAN = [0, 1, 3, 5, 7, 8, 10]
MIXOLYDIAN = [0, 2, 4, 5, 7, 9, 10]
DOUBLE_HARMONIC = [0, 1, 4, 5, 7, 8, 11]
PHRYGIAN_DOMINANT = [0, 1, 4, 5, 7, 8, 10]
AEOLIAN = [0, 2, 3, 5, 7, 8, 10]


# MARK: Instruments

def zeros(n):
    return array("d", bytes(8 * n))


def pluck(freq, dur, rng, bright=0.6, ring=2.5):
    """A plucked string: Karplus-Strong with a fractional-delay allpass, so it stays in tune."""
    n = int(RATE * dur)
    period = RATE / freq
    length = int(period - 0.5)
    d = period - 0.5 - length
    if d < 0.1:
        length -= 1
        d += 1
    c = (1 - d) / (1 + d)
    buf = [rng.uniform(-1, 1) for _ in range(length)]
    for i in range(1, length):  # a softer pluck has fewer high partials
        buf[i] = buf[i] * bright + buf[i - 1] * (1 - bright)
    # Loop gain so the note falls 60 dB in about `ring` seconds.
    decay = 10 ** (-3 / (ring * freq))
    out = zeros(n)
    idx = 0
    last = 0.0
    ax = ay = 0.0
    for i in range(n):
        x = buf[idx]
        lp = 0.5 * (x + last)
        last = x
        ap = c * lp + ax - c * ay
        ax = lp
        ay = ap
        buf[idx] = decay * ap
        out[i] = x
        idx += 1
        if idx == length:
            idx = 0
    for i in range(min(64, n)):
        out[n - 1 - i] *= i / 64
    return out


def table(harmonics, size=2048):
    """One cycle of a tone from its harmonics' amplitudes."""
    t = array("d", [0.0]) * size
    for k, a in enumerate(harmonics, start=1):
        if a:
            for i in range(size):
                t[i] += a * math.sin(2 * math.pi * k * i / size)
    peak = max(abs(v) for v in t)
    for i in range(size):
        t[i] /= peak
    return t


# Double reed (aulos): strong odd harmonics, a nasal buzz. Ney/flute: soft, few harmonics.
AULOS = table([1, 0.45, 0.7, 0.25, 0.45, 0.18, 0.28, 0.1, 0.15, 0.06])
NEY = table([1, 0.2, 0.12, 0.05, 0.03])
DRONE = table([1, 0.6, 0.45, 0.32, 0.24, 0.18, 0.12, 0.08, 0.05])
HORN = table([1, 0.55, 0.35, 0.18, 0.08])


def blown(freq, dur, rng, tone=AULOS, attack=0.05, release=0.12, vibrato=5.0, depth=0.006, breath=0.04):
    """A blown note: wavetable tone with a breathy attack, a little vibrato coming in late."""
    n = int(RATE * dur)
    out = zeros(n)
    size = len(tone)
    phase = rng.random() * size
    step = freq * size / RATE
    lp = 0.0
    for i in range(n):
        t = i / RATE
        vib = 1 + depth * min(1, t / 0.35) * math.sin(2 * math.pi * vibrato * t)
        phase += step * vib
        if phase >= size:
            phase -= size
        v = tone[int(phase)]
        noise = rng.uniform(-1, 1)
        lp += 0.2 * (noise - lp)
        env = min(1, t / attack) * min(1, (dur - t) / release)
        out[i] = (v + breath * lp * (1 + 3 * max(0, 1 - t / 0.08))) * max(0, env)
    return out


def horn(freq, dur, rng):
    """A bronze horn: the lip settles onto the note, then a swell."""
    n = int(RATE * dur)
    out = zeros(n)
    size = len(HORN)
    phase = 0.0
    for i in range(n):
        t = i / RATE
        f = freq * (1 - 0.03 * math.exp(-t * 18)) * (1 + 0.004 * math.sin(2 * math.pi * 4.5 * t))
        phase += f * size / RATE
        if phase >= size:
            phase -= size
        env = min(1, t / 0.09) * min(1, (dur - t) / 0.3) * (0.8 + 0.2 * min(1, t / 0.5))
        out[i] = HORN[int(phase)] * max(0, env)
    return out


def dum(rng, big=False):
    """The low stroke of a frame drum (or a war drum): a falling thump."""
    dur = 0.9 if big else 0.45
    n = int(RATE * dur)
    out = zeros(n)
    f0, f1 = (75, 42) if big else (120, 70)
    phase = 0.0
    for i in range(n):
        t = i / RATE
        f = f1 + (f0 - f1) * math.exp(-t * 18)
        phase += 2 * math.pi * f / RATE
        out[i] = math.sin(phase) * math.exp(-t * (4.5 if big else 9)) + rng.uniform(-1, 1) * 0.15 * math.exp(-t * 60)
    return out


def tek(rng, bright=1.0):
    """The rim stroke: a short bright slap."""
    n = int(RATE * 0.09)
    out = zeros(n)
    a = b = 0.0
    for i in range(n):
        t = i / RATE
        x = rng.uniform(-1, 1)
        a += 0.55 * (x - a)
        b += 0.08 * (a - b)
        out[i] = (a - b) * math.exp(-t * 45) * bright
    return out


# MARK: Mixing

class Mix:
    def __init__(self, seconds):
        self.n = int(RATE * seconds)
        self.l = zeros(self.n)
        self.r = zeros(self.n)

    def add(self, sound, at, gain=1.0, pan=0.0):
        start = int(at * RATE)
        gl = gain * math.cos((pan + 1) * math.pi / 4)
        gr = gain * math.sin((pan + 1) * math.pi / 4)
        l, r = self.l, self.r
        end = min(self.n, start + len(sound))
        for i in range(start, end):
            v = sound[i - start]
            l[i] += v * gl
            r[i] += v * gr


def reverb(mix, wet=0.28):
    """A hall: Schroeder combs and allpasses on the mono sum, spread across the two sides."""
    n = mix.n
    mono = array("d", (0.5 * (a + b) for a, b in zip(mix.l, mix.r)))
    acc = zeros(n)
    for delay, fb in [(1557, 0.82), (1617, 0.81), (1491, 0.83), (1422, 0.82)]:
        d = int(delay * RATE / 44100)
        buf = [0.0] * d
        idx = 0
        damp = 0.0
        for i in range(n):
            y = buf[idx]
            damp = y * 0.6 + damp * 0.4
            buf[idx] = mono[i] + damp * fb
            acc[i] += y
            idx += 1
            if idx == d:
                idx = 0
    for delay in (225, 556):
        d = int(delay * RATE / 44100)
        buf = [0.0] * d
        idx = 0
        for i in range(n):
            b = buf[idx]
            x = acc[i]
            y = -x + b
            buf[idx] = x + b * 0.5
            acc[i] = y
            idx += 1
            if idx == d:
                idx = 0
    spread = int(0.013 * RATE)
    for i in range(n):
        mix.l[i] += wet * 0.25 * acc[i]
        mix.r[i] += wet * 0.25 * (acc[i - spread] if i >= spread else 0.0)


def write(mix, path):
    peak = max(max(abs(v) for v in mix.l), max(abs(v) for v in mix.r), 1e-9)
    gain = 0.89 / peak
    frames = bytearray()
    for a, b in zip(mix.l, mix.r):
        frames += struct.pack("<hh", int(32767 * math.tanh(a * gain * 1.1) / math.tanh(1.1)),
                              int(32767 * math.tanh(b * gain * 1.1) / math.tanh(1.1)))
    with wave.open(path, "wb") as w:
        w.setnchannels(2)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(bytes(frames))


# MARK: Composition

RHYTHMS = [[1, 1, 1, 1], [2, 1, 1], [1, 1, 2], [1.5, 0.5, 2], [0.5, 0.5, 1, 2], [3, 1], [1, 0.5, 0.5, 2]]
ENDINGS = [[2, 2], [3, 1], [4]]


def phrase(rng, start, end, low, high, bars=2, rhythms=RHYTHMS):
    """A melodic phrase over `bars` bars of 4 beats: mostly steps, the odd leap, landing on
    the scale degree `end`."""
    notes = []
    deg = start
    for bar in range(bars):
        cells = rng.choice(ENDINGS) if bar == bars - 1 else rng.choice(rhythms)
        for k, beats in enumerate(cells):
            last = bar == bars - 1 and k == len(cells) - 1
            if last:
                deg = end
            elif notes:
                step = rng.choices([-3, -2, -1, 0, 1, 2, 3, 4], [1, 2, 6, 1, 6, 2, 1, 0.5])[0]
                deg = max(low, min(high, deg + step))
            notes.append((deg, beats))
    return notes


def vary(rng, notes):
    """The same phrase, sung again with a passing note or two."""
    out = []
    for deg, beats in notes:
        if beats >= 1 and rng.random() < 0.3:
            out += [(deg, beats / 2), (deg + rng.choice([-1, 1]), beats / 2)]
        else:
            out.append((deg, beats))
    return out


class Track:
    def __init__(self, name, tonic, mode, bpm, seed, lead, strings, drums, progression_a, progression_b,
                 horns=False, drone=True, lead_gain=0.32, string_gain=0.3, drone_gain=0.07, pattern="arp"):
        self.__dict__.update(locals())
        del self.__dict__["self"]

    def freq(self, deg, octave=0):
        o, d = divmod(deg, 7)
        return self.tonic * 2 ** ((self.mode[d] + 12 * (o + octave)) / 12)


DRUMS = {
    # Eighth-note slots across a bar: D low stroke, T rim, B big war drum, '.' rest.
    "light": "D..T..T.",
    "frame": "D.T.DDT.",
    "maqsum": "DT.TD.T.",
    "war": "B.BTB.BT",
    "slow": "D...T...",
}


def render(track):
    rng = random.Random(track.seed)
    beat = 60 / track.bpm
    bar = 4 * beat
    a1 = phrase(rng, 0, 4, -2, 7)
    a2 = a1[: len(a1) // 2] + phrase(rng, a1[len(a1) // 2][0], 0, -2, 7, bars=1)
    b1 = phrase(rng, 4, 4, 2, 9)
    b2 = phrase(rng, 6, 0, 0, 9)
    A = a1 + a2
    sections = [("intro", 4, None), ("A", 4, A), ("A", 4, vary(rng, A)), ("B", 4, b1 + b2),
                ("B", 4, vary(rng, b1 + b2)), ("A", 4, A), ("outro", 4, None)]
    total_bars = sum(s[1] for s in sections)
    mix = Mix(total_bars * bar + 4)

    t = 0.0
    bar_index = 0
    for name, bars, melody in sections:
        progression = track.progression_b if name == "B" else track.progression_a
        # The lead melody.
        if melody:
            at = t
            for deg, beats in melody:
                dur = beats * beat
                f = track.freq(deg, 1)
                if track.lead == "lyre":
                    mix.add(pluck(f, max(dur, 1.2), rng, bright=0.75, ring=2.0), at, track.lead_gain, 0.15)
                else:
                    tone = NEY if track.lead == "ney" else AULOS
                    mix.add(blown(f, dur * 0.97, rng, tone=tone, breath=0.09 if tone is NEY else 0.04),
                            at, track.lead_gain, 0.15)
                at += dur
        # Horn calls open each section of the title and war themes.
        if track.horns and name in ("intro", "B", "outro"):
            mix.add(horn(track.freq(0, 0), beat * 1.5, rng), t, 0.3, -0.2)
            mix.add(horn(track.freq(4, 0), beat * 2.5, rng), t + beat * 1.5, 0.3, -0.2)
        for b in range(bars):
            root = progression[b % len(progression)]
            bt = t + b * bar
            # Strings: an arpeggio on the bar's root, or the root ringing on each beat.
            # A harp rings longer and softer than a lyre.
            harp = track.strings == "harp"
            if track.pattern == "arp":
                for k, deg in enumerate([0, 4, 7, 4, 2, 4, 7, 4]):
                    f = track.freq(root + deg, -1)
                    mix.add(pluck(f, 2.4 if harp else 1.6, rng, bright=0.35 if harp else 0.5, ring=2.6 if harp else 1.6),
                            bt + k * beat / 2,
                            track.string_gain * (1.0 if k % 2 == 0 else 0.7), -0.3)
            else:
                for k in range(4):
                    f = track.freq(root + (0 if k % 2 == 0 else 4), -1)
                    mix.add(pluck(f, 1.2, rng, bright=0.65, ring=1.0), bt + k * beat,
                            track.string_gain * (1.0 if k == 0 else 0.75), -0.3)
            # Drums, softer in the intro and outro.
            if track.drums and not (name == "intro" and b < 2):
                soft = 0.6 if name in ("intro", "outro") else 1.0
                for k, stroke in enumerate(DRUMS[track.drums]):
                    at = bt + k * beat / 2 + rng.uniform(0, 0.006)
                    if stroke == "D":
                        mix.add(dum(rng), at, 0.5 * soft, 0.05)
                    elif stroke == "B":
                        mix.add(dum(rng, big=True), at, 0.75 * soft, 0.0)
                    elif stroke == "T":
                        mix.add(tek(rng), at, 0.32 * soft, 0.25)
            bar_index += 1
        t += bars * bar

    # The drone under it all: tonic and fifth, swelling and fading.
    if track.drone:
        length = t + 3
        for deg, pan in [(0, -0.4), (4, 0.4)]:
            f = track.freq(deg, -2 if track.tonic > 140 else -1)
            n = int(RATE * length)
            sound = zeros(n)
            size = len(DRONE)
            phase = 0.0
            step = f * size / RATE
            for i in range(n):
                x = i / RATE
                phase += step * (1 + 0.002 * math.sin(2 * math.pi * 0.23 * x))
                if phase >= size:
                    phase -= size
                env = min(1, x / 4) * min(1, (length - x) / 5) * (0.8 + 0.2 * math.sin(2 * math.pi * x / 9))
                sound[i] = DRONE[int(phase)] * env
            mix.add(sound, 0, track.drone_gain * (1 if deg == 0 else 0.6), pan)

    reverb(mix)
    return mix


TRACKS = [
    # The title: a slow hall, horns, the lyre and a drone.
    Track("title", 146.83, PHRYGIAN_DOMINANT, 58, 1200, "aulos", "lyre", "slow", [0, 0, 6, 0], [3, 3, 4, 4],
          horns=True, lead_gain=0.28),
    Track("greece", 146.83, DORIAN, 84, 1, "aulos", "lyre", "light", [0, 0, 3, 4], [6, 3, 4, 0]),
    Track("egypt", 164.81, DOUBLE_HARMONIC, 76, 2, "ney", "harp", "maqsum", [0, 1, 0, 1], [3, 4, 3, 1],
          lead_gain=0.36, string_gain=0.26),
    Track("mesopotamia", 146.83, PHRYGIAN, 64, 3, "aulos", "lyre", "frame", [0, 6, 0, 1], [3, 1, 6, 0],
          pattern="beats", drone_gain=0.09),
    Track("italia", 196.0, MIXOLYDIAN, 92, 4, "ney", "lyre", "light", [0, 3, 6, 0], [4, 3, 6, 4],
          lead_gain=0.34),
    # Expansion: the Hittites, after the Hurrian hymns of Ugarit (the oldest written music): a
    # plain lyre tune over horns and a frame drum.
    Track("hatti", 130.81, AEOLIAN, 70, 6, "aulos", "lyre", "frame", [0, 4, 5, 0], [3, 0, 4, 6],
          horns=True, lead_gain=0.3, drone_gain=0.08),
    # War: drums, horns and a hard-plucked ostinato.
    Track("war", 110.0, AEOLIAN, 108, 5, "aulos", "lyre", "war", [0, 0, 5, 6], [3, 4, 5, 4],
          horns=True, pattern="beats", string_gain=0.34, lead_gain=0.26, drone_gain=0.08),
]


def main():
    os.makedirs(SCRATCH, exist_ok=True)
    os.makedirs(OUT, exist_ok=True)
    only = set(os.environ.get("ONLY", "").split(",")) - {""}
    for track in TRACKS:
        if only and track.name not in only:
            continue
        wav = os.path.join(SCRATCH, track.name + ".wav")
        write(render(track), wav)
        m4a = os.path.join(OUT, track.name + ".m4a")
        subprocess.run(["afconvert", "-f", "m4af", "-d", "aac", "-b", "96000", wav, m4a], check=True)
        print("wrote", m4a)


if __name__ == "__main__":
    main()
