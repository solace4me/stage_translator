"""Render the 'Warm' worship pad: one seamless 24 s stereo loop per key,
in two voicings (full = with low end, light = lifted for phone speakers).
Everything is synthesized here, so the app owns the sound outright."""
import numpy as np, scipy.signal as sg, subprocess, sys, os
SR = 44100
LOOP = 24.0          # seconds in the loop
PRE = 8.0            # discarded warm-up (reverb fills)
XF = 4.0             # crossfade at the seam
rng = np.random.default_rng(7)

def saw_voice(freq, n, phase):
    # naive saw, softened later by the low-pass; plus a sine for body
    t = np.arange(n) / SR
    ph = (phase + freq * t) % 1.0
    return (2 * ph - 1) * 0.6 + 0.4 * np.sin(2 * np.pi * ph)

def note(midi, n, detunes=(-9, -4, 0, 4, 9)):
    f0 = 440 * 2 ** ((midi - 69) / 12)
    L = np.zeros(n); R = np.zeros(n)
    for i, c in enumerate(detunes):
        f = f0 * 2 ** (c / 1200)
        v = saw_voice(f, n, rng.random())
        pan = (i / (len(detunes) - 1))          # spread voices left to right
        L += v * np.cos(pan * np.pi / 2); R += v * np.sin(pan * np.pi / 2)
    return L / len(detunes), R / len(detunes)

def moving_lowpass(x, n, lo, hi, period):
    """Low-pass whose cutoff drifts slowly (one full cycle per `period` s)."""
    out = np.zeros_like(x); zi = None; B = 1024
    for s in range(0, n, B):
        t = s / SR
        cut = lo + (hi - lo) * (0.5 - 0.5 * np.cos(2 * np.pi * t / period))
        sos = sg.butter(2, cut, fs=SR, output='sos')
        if zi is None: zi = sg.sosfilt_zi(sos) * 0
        out[s:s+B], zi = sg.sosfilt(sos, x[s:s+B], zi=zi)
    return out

def reverb(x, seed):
    r = np.random.default_rng(seed)
    y = np.zeros_like(x)
    for d_ms, g in [(29.7, .84), (37.1, .83), (41.1, .82), (43.7, .81), (53.3, .80), (61.1, .79)]:
        d = int(d_ms * SR / 1000 * (1 + 0.02 * r.random()))
        a = np.zeros(d + 1); a[0] = 1; a[d] = -g
        y += sg.lfilter([1], a, x)
    y /= 6
    for d_ms in (5.0, 1.7):
        d = int(d_ms * SR / 1000); g = 0.7
        b = np.zeros(d + 1); b[0] = -g; b[d] = 1
        a = np.zeros(d + 1); a[0] = 1; a[d] = -g
        y = sg.lfilter(b, a, y)
    return y

def render(semitone, voicing):
    n = int((PRE + LOOP + XF) * SR)
    root = 48 + semitone if semitone <= 6 else 36 + semitone   # C3..F#3 or G2..B2
    if voicing == 'full':
        parts = [(root - 12, .55), (root, .9), (root + 7, .7), (root + 12, .6), (root + 19, .25)]
        lo, hi, hp = 450, 1300, 30
    else:  # light: no sub, lifted an octave, cut below 180 Hz
        parts = [(root + 12, .9), (root + 19, .7), (root + 24, .55), (root + 31, .2)]
        lo, hi, hp = 900, 2400, 180
    L = np.zeros(n); R = np.zeros(n)
    for m, g in parts:
        l, r = note(m, n); L += l * g; R += r * g
    L = moving_lowpass(L, n, lo, hi, LOOP); R = moving_lowpass(R, n, lo * 1.05, hi * 1.05, LOOP / 2)
    # slow swell so it breathes (period divides the loop)
    t = np.arange(n) / SR
    swell = 0.85 + 0.15 * np.cos(2 * np.pi * t / (LOOP / 2))
    L *= swell; R *= swell
    hsos = sg.butter(2, hp, 'highpass', fs=SR, output='sos')
    L = sg.sosfilt(hsos, L); R = sg.sosfilt(hsos, R)
    wetL, wetR = reverb(L, 1), reverb(R, 2)
    L = 0.55 * L + 0.75 * wetL; R = 0.55 * R + 0.75 * wetR
    # cut warm-up, make the loop seamless: blend the tail into the head
    a = int(PRE * SR); m = int(LOOP * SR); x = int(XF * SR)
    outL = L[a:a + m].copy(); outR = R[a:a + m].copy()
    tailL = L[a + m:a + m + x]; tailR = R[a + m:a + m + x]
    w = np.linspace(0, np.pi / 2, x)
    outL[:x] = outL[:x] * np.sin(w) + tailL * np.cos(w)
    outR[:x] = outR[:x] * np.sin(w) + tailR * np.cos(w)
    st = np.stack([outL, outR], 1)
    st *= 0.16 / np.sqrt(np.mean(st ** 2))           # same loudness in every key
    peak = np.abs(st).max()
    if peak > 0.95: st *= 0.95 / peak
    return st

def save(st, path):
    pcm = (st * 32767).astype('<i2').tobytes()
    subprocess.run(['ffmpeg', '-y', '-loglevel', 'error', '-f', 's16le', '-ar', str(SR), '-ac', '2', '-i', '-',
                    '-c:a', 'libvorbis', '-q:a', '3', path], input=pcm, check=True)

if __name__ == '__main__':
    out = sys.argv[1]; os.makedirs(out, exist_ok=True)
    keys = [int(k) for k in sys.argv[2].split(',')] if len(sys.argv) > 2 else range(12)
    for s in keys:
        for v in ('full', 'light'):
            st = render(s, v)
            save(st, f'{out}/warm_{v}_{s:02d}.ogg')
            # seam check: jump from last sample to first must be small
            print(s, v, 'seam', round(float(np.abs(st[-1] - st[0]).max()), 4),
                  'step', round(float(np.abs(np.diff(st, axis=0)).max()), 4))
