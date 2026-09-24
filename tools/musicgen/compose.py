"""RUNEBOUND procedural music (M06 audio track): compositions as data,
rendered with a small vectorised numpy synth into seamless stereo loops.

  assets/music/<zone>_explore.wav   exploration layer
  assets/music/<zone>_combat.wav    combat layer: same key, tempo and length,
                                    played in sync ON TOP of the exploration
                                    layer and faded in by MusicDirector

Instruments are additive / FM (no per-sample Python loops, no scipy):
  pluck  harp-like additive partials, higher partials decay faster
  pad    soft additive chord voice, detuned pair spread L/R
  bell   2-operator FM with a decaying index
  drone  root + fifth with a loop-synchronous swell
  drum   frame drum: pitch-dropping sine + noise skin
  shaker short bright noise tick
Reverb: FFT convolution with a synthetic decaying-noise impulse response.
Loops are seamless: every tail (notes and reverb) past the loop end is added
back onto the start. Deterministic (seeded).

Run: python tools/musicgen/compose.py
"""
from __future__ import annotations

import os
import wave

import numpy as np

SR = 32000
ROOT = os.path.normpath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT = os.path.join(ROOT, "assets", "music")

NOTE = {"C": 0, "C#": 1, "D": 2, "D#": 3, "Eb": 3, "E": 4, "F": 5, "F#": 6, "G": 7, "G#": 8, "Ab": 8,
        "A": 9, "A#": 10, "Bb": 10, "B": 11}


def midi(name: str) -> int:
    """'D3' -> 50; accidentals like 'Bb2', 'C#4'."""
    return 12 * (int(name[-1]) + 1) + NOTE[name[:-1]]


def freq(m: float) -> float:
    return 440.0 * 2 ** ((m - 69) / 12.0)


def tvec(dur: float) -> np.ndarray:
    return np.arange(int(dur * SR)) / SR


# --- instruments (mono, return a float array) -------------------------------

def pluck(f: float, vel: float, ring: float = 2.4, partials: int = 8, rng=None) -> np.ndarray:
    t = tvec(ring)
    out = np.zeros_like(t)
    for k in range(1, partials + 1):
        tau = 1.6 / k ** 0.85
        phase = rng.uniform(0, 2 * np.pi) if rng is not None else 0.0
        out += (1.0 / k ** 1.1) * np.exp(-t / tau) * np.sin(2 * np.pi * k * f * t + phase)
    out *= np.clip(t / 0.003, 0, 1)                      # 3 ms attack
    return out * vel


def pad_voice(f: float, dur: float, attack: float = 1.4, release: float = 1.8) -> np.ndarray:
    t = tvec(dur + release)
    env = np.clip(t / attack, 0, 1) * np.clip((dur + release - t) / release, 0, 1)
    tone = sum(w * np.sin(2 * np.pi * k * f * t) for k, w in ((1, 1.0), (2, 0.35), (3, 0.16), (4, 0.07)))
    return tone * env ** 1.5


def bell(f: float, vel: float) -> np.ndarray:
    t = tvec(3.5)
    index = 3.5 * np.exp(-t / 0.45)
    out = np.sin(2 * np.pi * f * t + index * np.sin(2 * np.pi * 3.5 * f * t))
    return out * np.exp(-t / 1.1) * np.clip(t / 0.002, 0, 1) * vel


def drum(f0: float, vel: float, rng) -> np.ndarray:
    t = tvec(0.9)
    sweep = f0 * (1.0 + 0.7 * np.exp(-t / 0.04))
    body = np.sin(2 * np.pi * np.cumsum(sweep) / SR) * np.exp(-t / 0.22)
    skin = rng.standard_normal(len(t)) * np.exp(-t / 0.015)
    skin = np.diff(skin, prepend=0.0)                    # brighter slap
    return (body + 0.25 * skin) * vel


def shaker(vel: float, rng) -> np.ndarray:
    t = tvec(0.12)
    n = rng.standard_normal(len(t))
    n = np.diff(np.diff(n, prepend=0.0), prepend=0.0)    # high-passed
    return n * np.exp(-t / 0.025) * np.clip(t / 0.004, 0, 1) * vel * 0.25


# --- rendering ----------------------------------------------------------------

class Track:
    """Stereo loop buffer; events wrap around the loop end."""

    def __init__(self, length_s: float):
        self.n = int(length_s * SR)
        self.buf = np.zeros((2, self.n))

    def add(self, start_s: float, sig: np.ndarray, pan: float = 0.0, gain: float = 1.0) -> None:
        left = np.cos((pan + 1) * np.pi / 4) * gain
        right = np.sin((pan + 1) * np.pi / 4) * gain
        i0 = int(start_s * SR) % self.n
        pos = 0
        while pos < len(sig):                           # wrap tails onto the start
            take = min(len(sig) - pos, self.n - i0)
            self.buf[0, i0:i0 + take] += sig[pos:pos + take] * left
            self.buf[1, i0:i0 + take] += sig[pos:pos + take] * right
            pos += take
            i0 = 0

    def reverb(self, wet: float, rt60: float, seed: int) -> None:
        rng = np.random.default_rng(seed)
        t = tvec(rt60 * 1.1)
        dry = self.buf.copy()
        for ch in range(2):
            ir = rng.standard_normal(len(t)) * np.exp(-t * 6.9 / rt60)
            ir *= np.clip((t - 0.018) / 0.01, 0, 1)      # 18 ms pre-delay
            ir = np.convolve(ir, np.ones(6) / 6, mode="same")  # darker tail
            ir /= np.sqrt(np.sum(ir ** 2))
            size = 1 << int(np.ceil(np.log2(self.n + len(ir))))
            spec = np.fft.rfft(dry[ch], size) * np.fft.rfft(ir, size)
            wet_sig = np.fft.irfft(spec, size)[: self.n + len(ir)]
            wrapped = wet_sig[: self.n].copy()
            tail = wet_sig[self.n:]
            wrapped[: len(tail)] += tail                 # seamless reverb loop
            self.buf[ch] = dry[ch] * (1.0 - wet) + wrapped * wet

    def save(self, name: str, peak: float = 0.45) -> None:
        os.makedirs(OUT, exist_ok=True)
        m = np.max(np.abs(self.buf))
        data = self.buf * (peak / m) if m > 0 else self.buf
        pcm = (np.clip(data, -1, 1) * 32767).astype(np.int16).T.copy()
        path = os.path.join(OUT, name + ".wav")
        with wave.open(path, "wb") as f:
            f.setnchannels(2)
            f.setsampwidth(2)
            f.setframerate(SR)
            f.writeframes(pcm.tobytes())
        print("  music/%s.wav (%.1f s)" % (name, self.n / SR))


# --- compositions (data) -------------------------------------------------------

HIGHLANDS = {
    "tempo": 72,
    "bars": 16,
    # two bars per chord: D minor, dark and wide; A major (C#) turns it round
    "chords": [["D3", "F3", "A3"], ["Bb2", "D3", "F3"], ["F3", "A3", "C4"], ["C3", "E3", "G3"],
               ["D3", "F3", "A3"], ["G2", "Bb2", "D3"], ["Bb2", "D3", "F3"], ["A2", "C#3", "E3"]],
    # arpeggio over each chord in eighths (index into chord + octave), None = rest
    "arp": [0, 1, 2, 3, None, 2, 1, None, 0, 2, 3, 4, None, 3, 2, 1],
    "bells_every_bars": 4,
    "drone": ["D2", "A2"],
    # combat groove per bar in eighths: (kind, velocity)
    "groove": [("low", 1.0), ("shk", 0.5), ("mid", 0.6), ("shk", 0.4),
               ("low", 0.85), ("shk", 0.5), ("mid", 0.8), ("mid", 0.5)],
}


RUNEHOLD = {
    # safe haven: F major, slower, harp in gentle eighths, no minor turn-around
    "tempo": 66,
    "bars": 16,
    "chords": [["F3", "A3", "C4"], ["C3", "E3", "G3"], ["D3", "F3", "A3"], ["Bb2", "D3", "F3"],
               ["F3", "A3", "C4"], ["A2", "C3", "E3"], ["Bb2", "D3", "F3"], ["C3", "E3", "G3"]],
    "arp": [0, None, 1, 2, None, 3, 2, None, 1, None, 2, 4, None, 3, None, None],
    "arp_gain": 0.2,
    "arp_pan": -0.25,
    "bells_every_bars": 8,
    "drone": ["F2", "C3"],
    "drone_gain": 0.22,
    "pad_gain": 0.15,
    "reverb": (0.42, 3.2),
    "seed": 3301,
    # training-yard drums: calmer than the Highlands, still a pulse to spar to
    "groove": [("low", 0.9), ("shk", 0.35), ("shk", 0.3), ("mid", 0.55),
               ("low", 0.7), ("shk", 0.35), ("mid", 0.6), ("shk", 0.3)],
    "combat_reverb": (0.22, 1.8),
}


SPIRE = {
    # the Shattered Spire: D Phrygian dark, slow, cathedral reverb, sparse bells
    "tempo": 60,
    "bars": 16,
    "chords": [["D3", "F3", "A3"], ["Eb3", "G3", "Bb3"], ["C3", "Eb3", "G3"], ["D3", "F#3", "A3"],
               ["Bb2", "D3", "F3"], ["Eb3", "G3", "Bb3"], ["G2", "Bb2", "D3"], ["A2", "C#3", "E3"]],
    "arp": [0, None, None, 2, None, None, 1, None, 4, None, None, 3, None, None, None, None],
    "arp_gain": 0.18,
    "arp_pan": 0.2,
    "bells_every_bars": 2,
    "drone": ["D2", "A2"],
    "drone_gain": 0.36,
    "pad_gain": 0.13,
    "reverb": (0.5, 4.2),
    "seed": 5903,
    "groove": [("low", 1.0), ("shk", 0.3), ("mid", 0.5), ("shk", 0.3),
               ("low", 0.8), ("low", 0.6), ("mid", 0.7), ("shk", 0.4)],
    "combat_reverb": (0.3, 2.4),
}


def render_stinger() -> None:
    """Victory stinger (boss down): rising harp run into a bell chord, D major,
    ~4.5 s with its reverb tail; one-shot, not looped."""
    rng = np.random.default_rng(77)
    t = Track(4.6)
    run = ["D4", "F#4", "A4", "D5", "F#5", "A5"]
    for i, n in enumerate(run):
        t.add(0.09 * i, pluck(freq(midi(n)), 0.7 + 0.05 * i, rng=rng), -0.3 + 0.12 * i, 0.3)
    for n, pan in (("D4", -0.4), ("A4", 0.0), ("F#5", 0.4)):
        t.add(0.62, bell(freq(midi(n)), 0.6), pan, 0.22)
        t.add(0.62, pad_voice(freq(midi(n)), 1.6, attack=0.08, release=2.2), -pan, 0.14)
    t.add(0.62, drum(62.0, 0.9, rng), 0.0, 0.5)
    t.reverb(wet=0.4, rt60=2.6, seed=31)
    # not a loop: fade the wrapped tail away instead of letting it land on the start
    fade = np.clip(np.linspace(1.5, -0.2, t.n), 0.0, 1.0)
    head = int(0.05 * SR)
    t.buf[:, :head] *= np.linspace(0.0, 1.0, head)
    t.buf *= fade
    t.save("stinger_victory", peak=0.5)


def render_spire() -> None:
    render_zone("spire", SPIRE)


def render_highlands() -> None:
    render_zone("highlands", HIGHLANDS)


def render_runehold() -> None:
    render_zone("runehold", RUNEHOLD)


def render_zone(key: str, c: dict) -> None:
    """Exploration + combat layer of one composition (same key, tempo, length).
    Defaults reproduce the Highlands render exactly (same RNG order)."""
    beat = 60.0 / c["tempo"]
    eighth = beat / 2
    bar = beat * 4
    length = bar * c["bars"]
    rng = np.random.default_rng(c.get("seed", 1207))

    # --- exploration: drone, pad, harp arpeggios, bells ---
    ex = Track(length)
    t = tvec(length)
    swell = 0.75 + 0.25 * np.sin(2 * np.pi * 2 * t / length)          # 2 swells per loop
    drone = sum(np.sin(2 * np.pi * freq(midi(n)) * t) * g for n, g in zip(c["drone"], (1.0, 0.55)))
    drone += 0.2 * np.sin(2 * np.pi * 2 * freq(midi(c["drone"][0])) * t)
    ex.add(0.0, drone * swell, 0.0, c.get("drone_gain", 0.32))
    pad_gain = c.get("pad_gain", 0.16)
    for ci, chord in enumerate(c["chords"]):
        start = ci * 2 * bar
        for vi, note in enumerate(chord):
            f = freq(midi(note) + 12)
            detune = 2 ** (4 / 1200)
            ex.add(start, pad_voice(f, 2 * bar - 0.4), -0.55 + 0.35 * vi, pad_gain)
            ex.add(start, pad_voice(f * detune, 2 * bar - 0.4), 0.55 - 0.35 * vi, pad_gain)
        tones = [midi(n) + 12 for n in chord] + [midi(chord[0]) + 24, midi(chord[1]) + 24]
        for step, idx in enumerate(c["arp"]):                           # 16 eighths = 2 bars
            if idx is None or (ci % 2 == 1 and step >= 12):             # every 2nd chord breathes
                continue
            vel = 0.55 + 0.25 * rng.random() + (0.15 if step % 4 == 0 else 0.0)
            ex.add(start + step * eighth, pluck(freq(tones[idx]), vel, rng=rng), c.get("arp_pan", 0.35),
                   c.get("arp_gain", 0.22))
        if ci % (c["bells_every_bars"] // 2) == 0:
            ex.add(start, bell(freq(midi(chord[0]) + 24), 0.5), -0.6, 0.12)
    wet, rt60 = c.get("reverb", (0.38, 2.8))
    ex.reverb(wet=wet, rt60=rt60, seed=11)
    ex.save(key + "_explore")

    # --- combat: frame drums, driving bass pulse, low swells (same grid) ---
    cb = Track(length)
    for b in range(c["bars"]):
        chord = c["chords"][b // 2]
        root = midi(chord[0]) - 12 if midi(chord[0]) >= midi("C3") else midi(chord[0])
        for step, (kind, vel) in enumerate(c["groove"]):
            when = b * bar + step * eighth
            v = vel * (0.9 + 0.2 * rng.random())
            if kind == "low":
                cb.add(when, drum(62.0, v, rng), 0.0, 0.55)
            elif kind == "mid":
                cb.add(when, drum(118.0, v * 0.7, rng), 0.15, 0.4)
            else:
                cb.add(when, shaker(v, rng), 0.3, 1.0)
            if step % 2 == 0:                                            # bass pulse in quarters
                cb.add(when, pluck(freq(root), 0.8, ring=0.9, partials=5, rng=rng), 0.0, 0.3)
        if b % 2 == 0:
            for note in chord[:2]:
                cb.add(b * bar, pad_voice(freq(midi(note)), 2 * bar - 0.6, attack=0.7, release=1.0), 0.0, 0.14)
    wet, rt60 = c.get("combat_reverb", (0.2, 1.6))
    cb.reverb(wet=wet, rt60=rt60, seed=23)
    cb.save(key + "_combat")


if __name__ == "__main__":
    import sys
    only = sys.argv[1:]
    print("music:")
    for name, fn in (("highlands", render_highlands), ("runehold", render_runehold), ("spire", render_spire),
                     ("stinger", render_stinger)):
        if not only or name in only:
            fn()
