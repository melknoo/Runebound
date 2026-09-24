"""RUNEBOUND sound effect synthesizer.

Layered procedural SFX (noise, sines, sweeps, envelopes) written as 16-bit
mono WAVs to assets/sfx/. Naming: <key>_<nn>.wav — Sfx autoload groups
variants by prefix. Deterministic (seeded).

Run:  python tools/sfxgen/generate.py
"""
from __future__ import annotations

import os
import wave
import numpy as np

SR = 32000
ROOT = os.path.normpath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT = os.path.join(ROOT, "assets", "sfx")

rng = np.random.default_rng(88)


def t(dur: float) -> np.ndarray:
    return np.arange(int(SR * dur)) / SR


def env_exp(dur: float, decay: float, attack: float = 0.004) -> np.ndarray:
    x = t(dur)
    e = np.exp(-x / decay)
    a = np.clip(x / max(attack, 1e-4), 0, 1)
    return e * a


def noise(dur: float) -> np.ndarray:
    return rng.standard_normal(int(SR * dur))


def lowpass(sig: np.ndarray, alpha: float) -> np.ndarray:
    out = np.empty_like(sig)
    acc = 0.0
    for i, s in enumerate(sig):
        acc += alpha * (s - acc)
        out[i] = acc
    return out


def highpass(sig: np.ndarray, alpha: float) -> np.ndarray:
    return sig - lowpass(sig, alpha)


def sine_sweep(dur: float, f0: float, f1: float) -> np.ndarray:
    x = t(dur)
    freq = np.linspace(f0, f1, len(x))
    phase = 2 * np.pi * np.cumsum(freq) / SR
    return np.sin(phase)


def normalize(sig: np.ndarray, peak: float = 0.85) -> np.ndarray:
    m = np.max(np.abs(sig))
    return sig * (peak / m) if m > 0 else sig


def save(sig: np.ndarray, name: str) -> None:
    os.makedirs(OUT, exist_ok=True)
    data = (np.clip(normalize(sig), -1, 1) * 32767).astype(np.int16)
    with wave.open(os.path.join(OUT, f"{name}.wav"), "wb") as f:
        f.setnchannels(1)
        f.setsampwidth(2)
        f.setframerate(SR)
        f.writeframes(data.tobytes())
    print(f"  {name}.wav ({len(sig)/SR:.2f}s)")


def pad(*sigs: np.ndarray) -> np.ndarray:
    n = max(len(s) for s in sigs)
    return sum(np.pad(s, (0, n - len(s))) for s in sigs)


def delay(sig: np.ndarray, seconds: float) -> np.ndarray:
    return np.pad(sig, (int(SR * seconds), 0))


# --- sounds ------------------------------------------------------------------

def footstep(i):
    thump = sine_sweep(0.09, 95 - i * 6, 55) * env_exp(0.09, 0.03)
    grit = lowpass(noise(0.07), 0.25) * env_exp(0.07, 0.02) * 0.4
    save(pad(thump, grit), f"footstep_{i:02d}")


def swing(i):
    dur = 0.22
    n = noise(dur)
    body = lowpass(n, 0.12 + i * 0.03) * 1.6
    x = t(dur)
    sweep_env = np.sin(np.pi * x / dur) ** 2
    save(highpass(body, 0.02) * sweep_env, f"swing_{i:02d}")


def impact_flesh(i):
    thump = sine_sweep(0.12, 160, 60) * env_exp(0.12, 0.04)
    crunch = lowpass(noise(0.09), 0.35) * env_exp(0.09, 0.025) * 0.8
    snap = highpass(noise(0.02), 0.4) * env_exp(0.02, 0.008) * 0.5
    save(pad(thump * 1.2, crunch, snap), f"impact_flesh_{i:02d}")


def enemy_hurt(i):
    tone = sine_sweep(0.12, 300 + i * 40, 140) * env_exp(0.12, 0.05)
    gr = lowpass(noise(0.1), 0.3) * env_exp(0.1, 0.03) * 0.5
    save(pad(tone, gr), f"enemy_hurt_{i:02d}")


def enemy_death(i):
    fall = sine_sweep(0.35, 260, 50) * env_exp(0.35, 0.13)
    burst = lowpass(noise(0.25), 0.28) * env_exp(0.25, 0.07)
    sparkle = highpass(noise(0.3), 0.55) * env_exp(0.3, 0.12) * 0.25
    save(pad(fall, burst, delay(sparkle, 0.04)), f"enemy_death_{i:02d}")


def dodge(i):
    dur = 0.16
    n = highpass(noise(dur), 0.15)
    x = t(dur)
    e = np.sin(np.pi * x / dur) ** 1.5
    save(n * e, f"dodge_{i:02d}")


def ember_cast(i):
    sizzle = highpass(noise(0.15), 0.35) * env_exp(0.15, 0.08) * 0.6
    rise = sine_sweep(0.15, 300, 700 + i * 100) * env_exp(0.15, 0.09) * 0.5
    save(pad(sizzle, rise), f"ember_cast_{i:02d}")


def ember_fire(i):
    whoosh = lowpass(noise(0.2), 0.2) * env_exp(0.2, 0.07)
    zip_ = sine_sweep(0.12, 900, 380) * env_exp(0.12, 0.05) * 0.45
    crackle = highpass(noise(0.15), 0.5) * env_exp(0.15, 0.06) * 0.3
    save(pad(whoosh, zip_, crackle), f"ember_fire_{i:02d}")


def ember_impact(i):
    boom = sine_sweep(0.3, 150, 45) * env_exp(0.3, 0.09)
    fire = lowpass(noise(0.35), 0.3) * env_exp(0.35, 0.11)
    crackle = np.zeros(int(SR * 0.4))
    for _ in range(14):
        pos = rng.integers(0, len(crackle) - 200)
        crackle[pos:pos + 160] += highpass(noise(0.005), 0.4) * rng.random() * 0.9
    save(pad(boom * 1.3, fire * 0.9, crackle * 0.5), f"ember_impact_{i:02d}")


def earthbreaker_windup():
    rumble = lowpass(noise(0.45), 0.06) * np.linspace(0.15, 1.0, int(SR * 0.45)) ** 2
    rise = sine_sweep(0.45, 60, 160) * np.linspace(0.1, 0.8, int(SR * 0.45))
    save(pad(rumble * 1.4, rise * 0.5), "earthbreaker_windup_01")


def earthbreaker_impact(i):
    sub = sine_sweep(0.5, 90, 28) * env_exp(0.5, 0.16)
    slam = lowpass(noise(0.3), 0.35) * env_exp(0.3, 0.06)
    debris = np.zeros(int(SR * 0.6))
    for _ in range(20):
        pos = rng.integers(int(SR * 0.05), len(debris) - 400)
        debris[pos:pos + 300] += lowpass(noise(0.0094), 0.3)[:300] * rng.random() * 0.7
    save(pad(sub * 1.6, slam, debris * 0.4), f"earthbreaker_impact_{i:02d}")


def telegraph():
    a = sine_sweep(0.1, 520, 520) * env_exp(0.1, 0.05)
    b = sine_sweep(0.14, 390, 390) * env_exp(0.14, 0.06)
    save(pad(a, delay(b, 0.09)) * 0.7, "telegraph_01")


def caster_charge():
    dur = 0.8
    x = t(dur)
    vib = np.sin(2 * np.pi * (500 + 350 * x / dur + 30 * np.sin(2 * np.pi * 9 * x)) * x)
    shimmer = highpass(noise(dur), 0.6) * 0.25
    e = np.linspace(0.2, 1.0, len(x)) ** 1.5
    save(pad(vib * 0.6, shimmer) * e, "caster_charge_01")


def bolt_fire(i):
    zap = sine_sweep(0.15, 1100, 300) * env_exp(0.15, 0.05)
    n = highpass(noise(0.1), 0.5) * env_exp(0.1, 0.03) * 0.4
    save(pad(zap, n), f"bolt_fire_{i:02d}")


def bolt_impact(i):
    pop = sine_sweep(0.1, 500, 120) * env_exp(0.1, 0.035)
    fizz = highpass(noise(0.14), 0.45) * env_exp(0.14, 0.05) * 0.5
    save(pad(pop, fizz), f"bolt_impact_{i:02d}")


def player_hurt(i):
    thud = sine_sweep(0.18, 130, 55) * env_exp(0.18, 0.06)
    grunt = lowpass(noise(0.12), 0.2) * env_exp(0.12, 0.04) * 0.6
    save(pad(thud * 1.3, grunt), f"player_hurt_{i:02d}")


def storm_step(i):
    crack = highpass(noise(0.06), 0.5) * env_exp(0.06, 0.015)
    boom = sine_sweep(0.3, 120, 40) * env_exp(0.3, 0.08)
    fizz = highpass(noise(0.25), 0.4) * env_exp(0.25, 0.09) * 0.4
    save(pad(crack * 1.2, delay(boom, 0.02), delay(fizz, 0.03)), f"storm_step_{i:02d}")


def chain_spark(i):
    zap = sine_sweep(0.16, 1400 - i * 150, 250) * env_exp(0.16, 0.04)
    crackle = np.zeros(int(SR * 0.22))
    for _ in range(10):
        pos = rng.integers(0, len(crackle) - 150)
        crackle[pos:pos + 120] += highpass(noise(0.004), 0.5)[:120] * rng.random()
    thump = sine_sweep(0.12, 200, 80) * env_exp(0.12, 0.04) * 0.6
    save(pad(zap, crackle * 0.7, thump), f"chain_spark_{i:02d}")


def rune_place():
    chime = np.sin(2 * np.pi * 880 * t(0.2)) * env_exp(0.2, 0.07)
    chime2 = np.sin(2 * np.pi * 1320 * t(0.15)) * env_exp(0.15, 0.05) * 0.5
    hum = np.sin(2 * np.pi * 220 * t(0.3)) * env_exp(0.3, 0.12) * 0.3
    save(pad(chime, delay(chime2, 0.05), hum), "rune_place_01")


def rune_detonate(i):
    shatter = np.zeros(int(SR * 0.35))
    for _ in range(16):
        pos = rng.integers(0, len(shatter) - 250)
        f = rng.uniform(1200, 3200)
        seg = np.sin(2 * np.pi * f * t(0.006)) * env_exp(0.006, 0.003)
        shatter[pos:pos + len(seg)] += seg * rng.random()
    boom = sine_sweep(0.3, 140, 50) * env_exp(0.3, 0.08)
    mist = highpass(noise(0.3), 0.3) * env_exp(0.3, 0.1) * 0.35
    save(pad(boom * 1.2, shatter * 0.8, mist), f"rune_detonate_{i:02d}")


def pickup(i):
    a = np.sin(2 * np.pi * (520 + i * 60) * t(0.07)) * env_exp(0.07, 0.03)
    b = np.sin(2 * np.pi * (780 + i * 60) * t(0.1)) * env_exp(0.1, 0.04)
    save(pad(a, delay(b, 0.05)) * 0.7, f"pickup_{i:02d}")


def equip():
    clunk = sine_sweep(0.12, 220, 90) * env_exp(0.12, 0.045)
    click = highpass(noise(0.03), 0.4) * env_exp(0.03, 0.01) * 0.5
    save(pad(clunk, click), "equip_01")


def legendary_drop():
    notes = [392.0, 523.25, 659.25, 783.99]  # rising major arpeggio
    parts = []
    for n, f in enumerate(notes):
        tone = np.sin(2 * np.pi * f * t(0.35)) * env_exp(0.35, 0.14)
        tone += np.sin(2 * np.pi * f * 2 * t(0.35)) * env_exp(0.35, 0.1) * 0.3
        parts.append(delay(tone, n * 0.09))
    shimmer = highpass(noise(0.7), 0.6) * env_exp(0.7, 0.3) * 0.15
    save(pad(*parts, shimmer) * 0.8, "legendary_drop_01")


def _loopable(sig: np.ndarray, fade: float = 0.25) -> np.ndarray:
    """Crossfade the tail into the head so LOOP_FORWARD plays seamlessly."""
    n = int(SR * fade)
    out = sig[:-n].copy()
    ramp = np.linspace(0, 1, n)
    out[:n] = out[:n] * ramp + sig[-n:] * (1 - ramp)
    return out


def wind_loop():
    dur = 6.0
    base = lowpass(noise(dur), 0.04)
    x = t(dur)
    swell = 0.55 + 0.45 * np.sin(2 * np.pi * x / dur * 2 + 1.0)
    gust = lowpass(noise(dur), 0.12) * (0.3 + 0.2 * np.sin(2 * np.pi * x / dur * 3))
    save(_loopable(pad(base * swell, gust * 0.5), 0.5), "wind_loop_01")


def campfire_loop():
    dur = 4.0
    bed = lowpass(noise(dur), 0.08) * 0.5
    crackle = np.zeros(int(SR * dur))
    for _ in range(46):
        pos = rng.integers(0, len(crackle) - 400)
        seg = highpass(noise(0.008), 0.35) * env_exp(0.008, 0.004) * rng.random()
        crackle[pos:pos + len(seg)] += seg
    save(_loopable(pad(bed, crackle * 0.8), 0.3), "campfire_loop_01")


def portal_hum():
    dur = 3.0
    x = t(dur)
    hum = np.sin(2 * np.pi * 110 * x) * 0.5 + np.sin(2 * np.pi * 165 * x + 0.5) * 0.3
    shimmer = highpass(noise(dur), 0.55) * 0.12 * (0.6 + 0.4 * np.sin(2 * np.pi * x / dur * 4))
    save(_loopable(pad(hum, shimmer), 0.4), "portal_hum_01")


def portal_travel():
    sweep = sine_sweep(0.6, 200, 900) * env_exp(0.6, 0.25)
    rush = highpass(noise(0.6), 0.25) * env_exp(0.6, 0.2) * 0.6
    save(pad(sweep, rush), "portal_travel_01")


def chest_open():
    creak = sine_sweep(0.2, 180, 320) * env_exp(0.2, 0.09) * 0.5
    latch = highpass(noise(0.03), 0.4) * env_exp(0.03, 0.01)
    chime = np.sin(2 * np.pi * 660 * t(0.25)) * env_exp(0.25, 0.09) * 0.4
    chime2 = np.sin(2 * np.pi * 990 * t(0.2)) * env_exp(0.2, 0.07) * 0.25
    save(pad(latch, creak, delay(chime, 0.12), delay(chime2, 0.2)), "chest_open_01")


def boss_roar():
    dur = 0.9
    x = t(dur)
    growl = np.sin(2 * np.pi * (70 + 25 * np.sin(2 * np.pi * 13 * x)) * x)
    growl += np.sin(2 * np.pi * (48 + 10 * np.sin(2 * np.pi * 7 * x)) * x) * 0.7
    rasp = lowpass(noise(dur), 0.3) * 0.55
    e = np.sin(np.pi * np.clip(x / dur, 0, 1) ** 0.7) ** 0.8
    save(pad(growl, rasp) * e, "boss_roar_01")


def charge_horn():
    a = sine_sweep(0.5, 160, 240) * env_exp(0.5, 0.3)
    b = sine_sweep(0.5, 242, 361) * env_exp(0.5, 0.28) * 0.5
    grit = lowpass(noise(0.5), 0.2) * env_exp(0.5, 0.2) * 0.3
    save(pad(a, b, grit), "charge_horn_01")


def spire_drone_loop():
    dur = 8.0
    x = t(dur)
    drone = np.sin(2 * np.pi * 55 * x) * 0.5 + np.sin(2 * np.pi * 82.5 * x + 1.0) * 0.3
    drone *= 0.7 + 0.3 * np.sin(2 * np.pi * x / dur * 2)
    whisper = highpass(noise(dur), 0.5) * 0.06 * (0.5 + 0.5 * np.sin(2 * np.pi * x / dur * 3 + 2))
    save(_loopable(pad(drone, whisper), 0.6), "spire_drone_loop_01")


def boss_blink(i):
    out_ = sine_sweep(0.15, 900, 200) * env_exp(0.15, 0.05)
    in_ = sine_sweep(0.12, 250, 1100) * env_exp(0.12, 0.05) * 0.8
    sparkle = highpass(noise(0.2), 0.55) * env_exp(0.2, 0.07) * 0.35
    save(pad(out_, delay(in_, 0.08), sparkle), f"boss_blink_{i:02d}")


def vessel_roar():
    dur = 1.1
    x = t(dur)
    # crystalline scream: detuned high partials over a deep groan
    scream = np.sin(2 * np.pi * (620 + 140 * np.sin(2 * np.pi * 6 * x)) * x) * 0.4
    scream += np.sin(2 * np.pi * (935 + 90 * np.sin(2 * np.pi * 9 * x)) * x) * 0.25
    groan = np.sin(2 * np.pi * (60 + 18 * np.sin(2 * np.pi * 4 * x)) * x) * 0.8
    shatter = highpass(noise(dur), 0.5) * 0.3
    e = np.sin(np.pi * np.clip(x / dur, 0, 1) ** 0.6) ** 0.7
    save(pad(scream, groan, shatter) * e, "vessel_roar_01")


def shatter_burst():
    burst = np.zeros(int(SR * 0.6))
    for _ in range(28):
        pos = rng.integers(0, len(burst) - 300)
        f = rng.uniform(1500, 4200)
        seg = np.sin(2 * np.pi * f * t(0.008)) * env_exp(0.008, 0.004)
        burst[pos:pos + len(seg)] += seg * rng.random()
    boom = sine_sweep(0.5, 160, 40) * env_exp(0.5, 0.14)
    save(pad(boom * 1.3, burst * 0.9), "shatter_burst_01")


def ui_denied():
    a = np.sin(2 * np.pi * 220 * t(0.07)) * env_exp(0.07, 0.03)
    b = np.sin(2 * np.pi * 180 * t(0.09)) * env_exp(0.09, 0.04)
    save(pad(a, delay(b, 0.08)) * 0.5, "ui_denied_01")


# --- M07 (appended last: the shared rng keeps every earlier sound identical) ---

def level_up():
    """Rising pentatonic run into a held bell pair: brighter and longer than
    the legendary drop, never mistaken for a pickup."""
    notes = [523.25, 587.33, 659.25, 783.99, 880.0, 1046.5]
    parts = []
    for n, f in enumerate(notes):
        tone = np.sin(2 * np.pi * f * t(0.4)) * env_exp(0.4, 0.16)
        tone += np.sin(2 * np.pi * f * 3.01 * t(0.4)) * env_exp(0.4, 0.06) * 0.18   # bell partial
        parts.append(delay(tone, n * 0.065))
    hold = (np.sin(2 * np.pi * 1046.5 * t(1.1)) + 0.6 * np.sin(2 * np.pi * 1318.5 * t(1.1))) * env_exp(1.1, 0.45)
    shimmer = highpass(noise(1.0), 0.65) * env_exp(1.0, 0.35) * 0.12
    save(pad(*parts, delay(hold, 0.36), delay(shimmer, 0.3)) * 0.75, "level_up_01")


def runic_guard():
    """A ward snapping shut: low whoomp, glassy rune partials, airy swell."""
    whoomp = sine_sweep(0.35, 190, 80) * env_exp(0.35, 0.12)
    glass = sum(np.sin(2 * np.pi * f * t(0.9)) * env_exp(0.9, d) * g
                for f, d, g in ((1210.0, 0.35, 0.35), (1815.0, 0.25, 0.22), (2420.0, 0.18, 0.12)))
    air = highpass(noise(0.6), 0.5) * np.clip(t(0.6) / 0.2, 0, 1) * env_exp(0.6, 0.25) * 0.25
    save(pad(whoomp, delay(glass, 0.03), air), "runic_guard_01")


def resonance_burst():
    """Heavy thump plus a bright chord bloom (the Resonance let go at once)."""
    thump = sine_sweep(0.5, 120, 40) * env_exp(0.5, 0.16)
    crack = highpass(noise(0.12), 0.35) * env_exp(0.12, 0.03) * 0.8
    chord = sum(np.sin(2 * np.pi * f * t(1.0)) * env_exp(1.0, 0.3) * 0.25 for f in (587.33, 739.99, 880.0, 1174.7))
    tail = lowpass(noise(0.9), 0.08) * env_exp(0.9, 0.3) * 0.6
    save(pad(thump, crack, delay(chord, 0.02), tail), "resonance_burst_01")


# --- M07b (appended: every synth above must keep its place in the shared RNG order) ---

def coin_pickup():
    """Two short bright metallic pings: a coin landing in the purse."""
    a = np.sin(2 * np.pi * 2093.0 * t(0.12)) * env_exp(0.12, 0.03)
    b = np.sin(2 * np.pi * 2637.0 * t(0.16)) * env_exp(0.16, 0.04)
    ring = np.sin(2 * np.pi * 5274.0 * t(0.16)) * env_exp(0.16, 0.02) * 0.3
    save(pad(a, delay(b, 0.05), delay(ring, 0.05)), "coin_pickup_01")


def ability_learned():
    """Rune chime pair plus a steel ring: a new ability committed to the blade."""
    chime = sum(np.sin(2 * np.pi * f * t(0.7)) * env_exp(0.7, 0.25) * 0.3 for f in (880.0, 1318.5))
    chime2 = sum(np.sin(2 * np.pi * f * t(0.6)) * env_exp(0.6, 0.2) * 0.25 for f in (1174.7, 1760.0))
    steel = highpass(noise(0.25), 0.3) * env_exp(0.25, 0.05) * 0.5
    ring = np.sin(2 * np.pi * 3520.0 * t(0.3)) * env_exp(0.3, 0.06) * 0.2
    save(pad(chime, delay(chime2, 0.12), delay(steel, 0.05), delay(ring, 0.05)), "ability_learned_01")


if __name__ == "__main__":
    print("Generating SFX:")
    for i in range(1, 4):
        footstep(i); swing(i); impact_flesh(i); enemy_hurt(i); ember_impact(i)
    for i in range(1, 3):
        enemy_death(i); dodge(i); ember_cast(i); ember_fire(i)
        earthbreaker_impact(i); bolt_fire(i); bolt_impact(i); player_hurt(i)
    for i in range(1, 3):
        storm_step(i); chain_spark(i); rune_detonate(i)
    for i in range(1, 3):
        pickup(i)
    earthbreaker_windup(); telegraph(); caster_charge(); ui_denied(); rune_place()
    equip(); legendary_drop()
    wind_loop(); campfire_loop(); portal_hum(); portal_travel()
    chest_open(); boss_roar(); charge_horn()
    spire_drone_loop(); vessel_roar(); shatter_burst()
    for i in range(1, 3):
        boss_blink(i)
    level_up(); runic_guard(); resonance_burst()
    coin_pickup(); ability_learned()
    print("done.")
