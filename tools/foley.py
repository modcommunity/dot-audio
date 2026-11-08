"""Self-synthesised foley primitives (numpy/scipy only): damped-resonance "modal" strikes, filtered-noise bursts,
friction slides, thuds, rattles and cloth. No recordings are used, so everything built from these is original
(CC0, see stock/CREDITS.md). Shared by make_reload_cues.py and make_impact_cues.py.

Every function returns a float64 mono array at RATE; `mix` lays events on a timeline.
"""
import subprocess
import numpy as np
from scipy import signal

RATE = 44100

# Partial ratios and decay seconds (before scaling) of the few materials the cues are made of. Ratios are the inharmonic
# series of a struck bar/plate, which is what makes a click sound like metal rather than a beep.
MATERIALS = {
    "steel":   ([1.0, 2.76, 5.40, 8.93], [0.060, 0.040, 0.025, 0.015], [1.0, 0.7, 0.45, 0.25]),
    "alu":     ([1.0, 2.40, 4.70, 7.10], [0.045, 0.030, 0.020, 0.012], [1.0, 0.6, 0.4, 0.2]),
    "plastic": ([1.0, 1.83, 3.10],       [0.018, 0.012, 0.008],        [1.0, 0.55, 0.3]),
    "brass":   ([1.0, 2.32, 4.18, 6.70], [0.110, 0.070, 0.045, 0.025], [1.0, 0.8, 0.5, 0.3]),
    "wood":    ([1.0, 1.59, 2.31],       [0.025, 0.015, 0.010],        [1.0, 0.6, 0.3]),
}


def n_samples(sec):
    return max(1, int(round(sec * RATE)))


def t_axis(sec):
    return np.arange(n_samples(sec)) / RATE


def bandpass(x, lo, hi, order=2):
    lo = max(20.0, lo)
    hi = min(RATE / 2 - 200, hi)
    sos = signal.butter(order, [lo, hi], btype="band", fs=RATE, output="sos")
    return signal.sosfilt(sos, x)


def lowpass(x, hz, order=2):
    return signal.sosfilt(signal.butter(order, min(hz, RATE / 2 - 200), btype="low", fs=RATE, output="sos"), x)


def highpass(x, hz, order=2):
    return signal.sosfilt(signal.butter(order, hz, btype="high", fs=RATE, output="sos"), x)


def env_exp(n, tau_s, attack_s=0.0004):
    t = np.arange(n) / RATE
    e = np.exp(-t / max(tau_s, 1e-4))
    a = max(1, int(attack_s * RATE))
    e[:a] *= np.linspace(0, 1, a)
    return e


def noise_burst(rng, dur, lo, hi, tau, gain=1.0):
    """Band-limited noise with an exponential decay: the 'click' transient of a mechanical contact."""
    n = n_samples(dur)
    x = bandpass(rng.standard_normal(n), lo, hi)
    x /= max(np.max(np.abs(x)), 1e-9)
    return gain * x * env_exp(n, tau)


def strike(rng, material, f0, dur=0.25, gain=1.0, damp=1.0, hardness=0.5):
    """A struck object: a short noise excitation exciting the material's damped partials.

    `damp` scales the decay times (bigger = rings longer); `hardness` sets how bright the excitation is."""
    ratios, decays, amps = MATERIALS[material]
    n = n_samples(dur)
    t = np.arange(n) / RATE
    out = np.zeros(n)
    for r, d, a in zip(ratios, decays, amps):
        f = f0 * r * (1 + rng.uniform(-0.012, 0.012))
        if f > RATE / 2 - 1000:
            continue
        out += a * np.sin(2 * np.pi * f * t + rng.uniform(0, 6.28)) * np.exp(-t / (d * damp))
    exc = noise_burst(rng, 0.004, 800 + 5000 * hardness, 14000, 0.0008, 1.0)
    out[:len(exc)] += exc * (0.6 + 0.8 * hardness)
    return gain * out / max(np.max(np.abs(out)), 1e-9)


def thud(rng, f_hi=140.0, f_lo=55.0, dur=0.22, tau=0.05, gain=1.0, grit=0.25):
    """Low impact: a falling sine plus a lowpassed noise body (a magazine on a floor, a cover on its stop)."""
    n = n_samples(dur)
    t = np.arange(n) / RATE
    f = f_lo + (f_hi - f_lo) * np.exp(-t / 0.035)
    ph = 2 * np.pi * np.cumsum(f) / RATE
    body = np.sin(ph) * np.exp(-t / tau)
    gr = lowpass(rng.standard_normal(n), 900) * np.exp(-t / (tau * 0.5)) * grit
    out = body + gr
    return gain * out / max(np.max(np.abs(out)), 1e-9)


def slide(rng, dur, lo, hi, gain=1.0, rough=120.0, sweep=(1.0, 1.0), shape="hump"):
    """Friction of one part along another: bandpassed noise, amplitude-modulated by a rough stick-slip rate.
    `sweep` scales the centre band from start to end; `shape` is the loudness curve."""
    n = n_samples(dur)
    x = rng.standard_normal(n)
    # Time-varying band: crossfade between a few fixed bands (cheap and artefact free).
    out = np.zeros(n)
    steps = 6
    for i in range(steps):
        k = i / (steps - 1)
        s = sweep[0] + (sweep[1] - sweep[0]) * k
        band = bandpass(x, lo * s, hi * s)
        w = np.exp(-0.5 * ((np.linspace(0, 1, n) - k) / (0.6 / steps)) ** 2)
        out += band * w
    t = np.arange(n) / RATE
    stick = 0.55 + 0.45 * np.clip(np.sin(2 * np.pi * rough * t + rng.uniform(0, 6) + 3 * lowpass(rng.standard_normal(n), 30)), -1, 1)
    u = np.linspace(0, 1, n)
    if shape == "hump":
        e = np.sin(np.pi * u) ** 0.8
    elif shape == "ramp_up":
        e = u ** 1.4
    elif shape == "ramp_down":
        e = (1 - u) ** 1.2 * np.minimum(1, u * 30)
    else:
        e = np.ones(n)
    out = out * stick * e
    return gain * out / max(np.max(np.abs(out)), 1e-9)


def rattle(rng, count, span, material="steel", f0=3000.0, gain=1.0):
    """A handful of small clinks at random times in `span` seconds (loose rounds, brass, a belt)."""
    n = n_samples(span + 0.12)
    out = np.zeros(n)
    times = np.sort(rng.uniform(0, span, count))
    for i, tm in enumerate(times):
        s = strike(rng, material, f0 * rng.uniform(0.7, 1.5), dur=0.09, gain=rng.uniform(0.3, 1.0) * (0.85 ** i), damp=0.5, hardness=0.8)
        a = int(tm * RATE)
        out[a:a + len(s)] += s[:n - a]
    return gain * out / max(np.max(np.abs(out)), 1e-9)


def cloth(rng, dur, gain=1.0, centre=1800.0):
    """Soft fabric/pouch rustle: lowpassed noise, grainy amplitude."""
    n = n_samples(dur)
    x = bandpass(rng.standard_normal(n), 300, centre * 2)
    t = np.arange(n) / RATE
    grain = np.clip(lowpass(rng.standard_normal(n), 45) * 5, 0, None)
    u = np.linspace(0, 1, n)
    e = np.sin(np.pi * u) ** 1.2
    out = x * grain * e
    return gain * out / max(np.max(np.abs(out)), 1e-9)


def whine(rng, dur, f_start, f_end, gain=1.0, tremolo=0.0):
    """Energy-cell hum/charge: a swept saw-ish tone (3 harmonics) with a gentle tremolo."""
    n = n_samples(dur)
    t = np.arange(n) / RATE
    f = np.linspace(f_start, f_end, n)
    ph = 2 * np.pi * np.cumsum(f) / RATE
    x = np.sin(ph) + 0.4 * np.sin(2 * ph) + 0.18 * np.sin(3 * ph)
    x *= 1 - tremolo * (0.5 + 0.5 * np.sin(2 * np.pi * 14 * t))
    u = np.linspace(0, 1, n)
    x *= np.minimum(1, u * 12) * np.minimum(1, (1 - u) * 10)
    return gain * x / max(np.max(np.abs(x)), 1e-9)


def mix(events, total):
    """events: [(time_s, array, gain_db)]. Returns the sum, `total` seconds long."""
    out = np.zeros(n_samples(total))
    for tm, x, g in events:
        a = int(round(tm * RATE))
        if a >= len(out):
            continue
        seg = x[:len(out) - a] * 10 ** (g / 20)
        out[a:a + len(seg)] += seg
    return out


def finish(x, peak_db=-3.0, fade_ms=14.0, head_ms=0.0):
    """Remove DC, fade the tail so nothing clicks, trim leading silence, scale to a peak."""
    x = x - np.mean(x)
    pk = np.max(np.abs(x))
    if pk <= 0:
        return x
    onset = int(np.argmax(np.abs(x) > pk * 10 ** (-40 / 20)))
    keep = max(0, onset - int(0.0015 * RATE))
    x = x[keep:]
    # last audible sample: drop the inaudible tail
    nz = np.nonzero(np.abs(x) > pk * 10 ** (-60 / 20))[0]
    if len(nz):
        x = x[:min(len(x), nz[-1] + int(0.01 * RATE))]
    f = min(len(x) // 2, int(fade_ms / 1000 * RATE))
    if f > 1:
        x[-f:] *= 0.5 * (1 + np.cos(np.linspace(0, np.pi, f)))
    return x * 10 ** (peak_db / 20) / np.max(np.abs(x))


def to_ogg(x, path, quality=3):
    """Mono Ogg Vorbis at 44.1 kHz through ffmpeg's libvorbis."""
    raw = np.clip(x, -1, 1).astype("<f4").tobytes()
    subprocess.run(["ffmpeg", "-v", "error", "-y", "-f", "f32le", "-ar", str(RATE), "-ac", "1", "-i", "-",
                    "-c:a", "libvorbis", "-q:a", str(quality), str(path)], input=raw, check=True)
