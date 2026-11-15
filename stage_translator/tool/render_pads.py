"""Worship pad, version 2: soft, dark, slowly breathing (near-pure tones, no
buzz), very wide. One perfectly seamless loop per key, in two voicings:
full (mixer / speaker) and light (phone speaker, an octave higher).
Everything is synthesized here, so the app owns the sound outright.

Seamless by construction: every tone and every slow swell completes a whole
number of cycles in the loop, and the reverb is applied "around the loop"."""
import numpy as np, subprocess, sys, os
SR = 44100
LOOP = 40.0
N = int(SR * LOOP)
t = np.arange(N) / SR

def q(f):                      # nearest frequency with whole cycles in the loop
    return round(f * LOOP) / LOOP

def tone(freq, rng):
    """One channel of a voice: three slightly detuned near-sine partials."""
    y = np.zeros(N)
    for cents in (-4, 0, 4):
        f = q(freq * 2 ** ((cents + rng.uniform(-1.5, 1.5)) / 1200))
        ph = rng.uniform(0, 2 * np.pi)
        y += np.sin(2 * np.pi * f * t + ph)
        y += 0.10 * np.sin(2 * np.pi * q(2 * f) * t + rng.uniform(0, 6.28))   # a little warmth
        y += 0.03 * np.sin(2 * np.pi * q(3 * f) * t + rng.uniform(0, 6.28))
    return y / 3

def swell(k, phase, depth):    # slow breathing, k whole cycles per loop
    return 1 - depth + depth * (0.5 + 0.5 * np.sin(2 * np.pi * k * t / LOOP + phase))

def visit(k, phase):           # a colour note that drifts in and out
    return np.maximum(0, np.sin(2 * np.pi * k * t / LOOP + phase)) ** 2

def reverb_ir(rng, seconds=5.0, cutoff=1400):
    n = int(seconds * SR); tt = np.arange(n) / SR
    ir = rng.standard_normal(n) * np.exp(-tt * 6.9 / seconds)      # -60 dB at the end
    F = np.fft.rfft(ir); f = np.fft.rfftfreq(n, 1 / SR)
    F *= 1 / (1 + (f / cutoff) ** 4)                                 # dark tail
    ir = np.fft.irfft(F, n); ir[:int(0.02 * SR)] *= np.linspace(0, 1, int(0.02 * SR))
    return ir / np.sqrt((ir ** 2).sum())

def circ_conv(x, ir):          # reverb that wraps around the loop
    return np.fft.irfft(np.fft.rfft(x) * np.fft.rfft(ir, N), N)

def render(semitone, voicing):
    rng = np.random.default_rng(100 + semitone * 2 + (voicing == 'light'))
    root = 48 + semitone if semitone <= 6 else 36 + semitone      # C3..F#3, G2..B2
    if voicing == 'light': root += 12
    # (semitones above root, level dB, swell cycles, swell depth)
    main = [(0, -11, 1, .5), (7, 0, 2, .6), (12, -1, 3, .6), (19, -9, 2, .7), (24, -17, 1, .8)]
    colour = [(14, -15, 1), (17, -13, 2), (21, -15, 1)]            # 2nd, 4th, 6th drift by
    if voicing == 'light':
        main = [(0, -4, 1, .5), (7, 0, 2, .6), (12, -3, 3, .6), (19, -12, 2, .7)]
        colour = [(14, -15, 1), (17, -14, 2)]
    L = np.zeros(N); R = np.zeros(N)
    for semi, db, k, depth in main:
        f = 440 * 2 ** ((root + semi - 69) / 12); g = 10 ** (db / 20)
        env = swell(k, rng.uniform(0, 6.28), depth)
        L += g * env * tone(f, rng); R += g * env * tone(f, rng)   # different left and right = wide
    for semi, db, k in colour:
        f = 440 * 2 ** ((root + semi - 69) / 12); g = 10 ** (db / 20)
        env = visit(k, rng.uniform(0, 6.28))
        L += g * env * tone(f, rng); R += g * env * tone(f, rng)
    whole = swell(1, rng.uniform(0, 6.28), 0.35)                    # the whole pad breathes
    L *= whole; R *= whole
    L = 0.35 * L + 1.0 * circ_conv(L, reverb_ir(rng)); R = 0.35 * R + 1.0 * circ_conv(R, reverb_ir(rng))
    st = np.stack([L, R], 1)
    st *= 10 ** (-17 / 20) / np.sqrt(np.mean(st ** 2))              # same loudness in every key
    peak = np.abs(st).max()
    if peak > 0.94: st *= 0.94 / peak
    return st

def save(st, path):
    pcm = (st * 32767).astype('<i2').tobytes()
    subprocess.run(['ffmpeg', '-y', '-loglevel', 'error', '-f', 's16le', '-ar', str(SR), '-ac', '2', '-i', '-',
                    '-c:a', 'libvorbis', '-q:a', '2', path], input=pcm, check=True)

if __name__ == '__main__':
    out = sys.argv[1]; os.makedirs(out, exist_ok=True)
    keys = [int(k) for k in sys.argv[2].split(',')] if len(sys.argv) > 2 else range(12)
    for s in keys:
        for v in ('full', 'light'):
            st = render(s, v); save(st, f'{out}/warm_{v}_{s:02d}.ogg')
            print(s, v, 'seam', round(float(np.abs(st[-1] - st[0]).max()), 4), 'max step', round(float(np.abs(np.diff(st, axis=0)).max()), 4))
