#!/usr/bin/env python3
"""How much of the start of speech push-to-talk loses, measured at a listener.

Two Rift clients in one voice channel on this machine. The *talker* has
push-to-talk on F8 and its input set to a virtual cable; this script plays a
test signal into that cable, presses F8 through SendInput, and records what
the *listener* plays out (WASAPI loopback of its output device). Nothing here
talks to Rift or LiveKit: the answer is in the audio.

    python ptt_audio.py devices
    python ptt_audio.py run   OUT --mode sweep  --n 12 --hold 1.5 --play "CABLE Input" --record "Speakers"
    python ptt_audio.py run   OUT --mode speech --n 8  --hold 2.2 --play "CABLE Input" --record "Speakers"
    python ptt_audio.py analyse OUT

Modes:
  sweep   a tone gliding 400 -> 2000 Hz over 2 s and round again, its pitch
          set by the wall clock, so the listener's first sound after a press
          says which instant of the source it is. Precise, but a noise model
          takes a steady tone for noise: run it with noise suppression Off.
  speech  a recorded sentence (say.wav), looped, with each press landing on
          its first syllable. For the noise models.

Output, per press (sweep):
  cut     ms of the source after the press that never arrived (lower is better)
  tail    ms still heard after the release (Rift holds 200 ms on purpose)
  ramp    ms from the first sound to 70% of the steady level
  and any sound heard outside a hold, which must never happen.
Output, per press (speech):
  first100 / first300  level of the opening against the rest of the hold, dB
  within6dB            ms until the heard voice is within 6 dB of the source

The source runs on the wall clock with a small lead; the audio stack's own
buffering adds a constant few tens of ms to `cut`. It is the same in every
run on one machine, so compare runs, not absolutes. Needs numpy (+ soundcard
for `run`), Python 3.10+. Requires Windows for `run` (SendInput).
"""
import argparse, os, sys, threading, time, wave

import numpy as np

R = 48000
HERE = os.path.dirname(os.path.abspath(__file__))
VK_F8, SCAN_F8 = 0x77, 0x42


# ── Sources ───────────────────────────────────────────────────────────────

def sweep_at(t):
    """The sweep's frequency at wall time t (seconds since the epoch)."""
    return 400 + 800 * (t % 2.0)


class Sweep:
    def __init__(self, t0):
        self.t0, self.n, self.ph = t0, 0, 0.0

    def next(self, count):
        t = self.t0 + (self.n + np.arange(count)) / R
        ph = self.ph + np.cumsum(2 * np.pi * sweep_at(t) / R)
        self.ph = float(ph[-1] % (2 * np.pi))
        self.n += count
        return (0.3 * np.sin(ph)).astype(np.float32)


def load_speech():
    w = wave.open(os.path.join(HERE, 'say.wav'))
    src = np.frombuffer(w.readframes(w.getnframes()), dtype='<i2').astype(np.float32) / 32768
    r0 = w.getframerate()
    x = np.interp(np.arange(int(len(src) * R / r0)) * r0 / R, np.arange(len(src)), src)
    return (x * 0.5 / max(1e-9, np.abs(x).max())).astype(np.float32)


class Speech:
    def __init__(self, t0, x):
        self.t0, self.x, self.n = t0, x, 0

    def next(self, count):
        out = self.x[(self.n + np.arange(count)) % len(self.x)]
        self.n += count
        return out


# ── Keys (Windows) ────────────────────────────────────────────────────────

def make_key():
    import ctypes
    from ctypes import wintypes

    class KEYBDINPUT(ctypes.Structure):
        _fields_ = [('wVk', wintypes.WORD), ('wScan', wintypes.WORD), ('dwFlags', wintypes.DWORD),
                    ('time', wintypes.DWORD), ('dwExtraInfo', ctypes.c_size_t)]

    class INPUT(ctypes.Structure):
        class _U(ctypes.Union):
            _fields_ = [('ki', KEYBDINPUT), ('pad', ctypes.c_byte * 32)]
        _anonymous_ = ('u',)
        _fields_ = [('type', wintypes.DWORD), ('u', _U)]

    send = ctypes.windll.user32.SendInput

    def key(down):
        i = INPUT(type=1)
        i.ki = KEYBDINPUT(VK_F8, SCAN_F8, 0 if down else 0x0002, 0, 0)
        if send(1, ctypes.byref(i), ctypes.sizeof(i)) != 1:
            raise OSError('SendInput refused the key')
    return key


# ── Run ───────────────────────────────────────────────────────────────────

def pick(items, name):
    found = [d for d in items if name.lower() in d.name.lower()]
    if not found:
        sys.exit(f'no device matching {name!r}; see `devices`')
    return found[0]


def run(a):
    import soundcard as sc
    os.makedirs(a.out, exist_ok=True)
    key = make_key()
    spk = pick(sc.all_speakers(), a.play)
    loop = pick(sc.all_microphones(include_loopback=True), a.record)
    print(f'playing into {spk.name}; recording {loop.name}')
    lead = 0.02
    t0 = time.time() + lead
    speech = load_speech() if a.mode == 'speech' else None
    src = Sweep(t0) if speech is None else Speech(t0, speech)
    period = None if speech is None else len(speech) / R
    with open(os.path.join(a.out, 'feed.log'), 'w') as f:
        f.write(f'T0 {t0:.6f}\nmode {a.mode}\n' + (f'P {period:.6f}\n' if period else ''))
    stop = threading.Event()
    chunks, rec0 = [], []

    def feed():
        with spk.player(samplerate=R, channels=1, blocksize=480) as p:
            while not stop.is_set():
                # Keep the written audio a little ahead of the wall clock.
                while src.n / R + t0 > time.time() + lead and not stop.is_set():
                    time.sleep(0.002)
                p.play(src.next(480))

    def record():
        with loop.recorder(samplerate=R, channels=1, blocksize=480) as r:
            r.record(numframes=480)  # let it settle
            rec0.append(time.time())
            while not stop.is_set():
                chunks.append(r.record(numframes=4800)[:, 0].astype(np.float32))

    th = [threading.Thread(target=feed, daemon=True), threading.Thread(target=record, daemon=True)]
    for t in th:
        t.start()
    time.sleep(2.0)
    bench = open(os.path.join(a.out, 'bench'), 'w')
    for i in range(a.n):
        if period:  # land on the sentence's first syllable
            k = int((time.time() + 0.8 - t0) // period) + 1
            at = t0 + k * period
        else:
            at = time.time() + np.random.uniform(1.5, 2.5)
        while time.time() < at - 0.003:
            time.sleep(0.001)
        while time.time() < at:
            pass
        bench.write(f'press {i} {time.time():.6f}\n'); key(True)
        time.sleep(a.hold)
        bench.write(f'release {i} {time.time():.6f}\n'); key(False)
        bench.flush()
    time.sleep(2.0)
    stop.set()
    for t in th:
        t.join(2)
    bench.close()
    np.concatenate(chunks).tofile(os.path.join(a.out, 'rec.f32'))
    open(os.path.join(a.out, 'rec0'), 'w').write(f'{rec0[0]:.6f}')
    if speech is not None:
        np.save(os.path.join(a.out, 'speech.npy'), speech)
    analyse(a.out)


# ── Analysis ──────────────────────────────────────────────────────────────

def load(out):
    d = {}
    for line in open(os.path.join(out, 'feed.log')):
        k, v = line.split()
        d[k] = v
    bench = [l.split() for l in open(os.path.join(out, 'bench'))]
    press = {int(b[1]): float(b[2]) for b in bench if b[0] == 'press'}
    rel = {int(b[1]): float(b[2]) for b in bench if b[0] == 'release'}
    rec = np.fromfile(os.path.join(out, 'rec.f32'), dtype=np.float32)
    rec0 = float(open(os.path.join(out, 'rec0')).read())
    return d, press, rel, rec, rec0


def rms(a, i, n=480):
    s = a[max(i, 0):i + n]
    return float(np.sqrt(np.mean(s * s))) if len(s) else 0.0


def freq(a, i):
    """Peak frequency of the 10 ms frame at i, to about a hertz."""
    s = a[i:i + 480] * np.hanning(480)
    spec = np.abs(np.fft.rfft(s, 65536))
    lo, hi = int(300 * 65536 / R), int(2200 * 65536 / R)
    k = lo + int(np.argmax(spec[lo:hi]))
    if 0 < k < len(spec) - 1:  # parabolic peak
        y0, y1, y2 = spec[k - 1:k + 2]
        k += 0.5 * (y0 - y2) / (y0 - 2 * y1 + y2 + 1e-12)
    return k * R / 65536


def segments(a, threshold=0.01, gap_ms=40):
    env = np.sqrt(np.convolve(a * a, np.ones(48) / 48, mode='same'))[::48] > threshold
    segs, i = [], 0
    while i < len(env):
        if env[i]:
            j = i
            while j < len(env) and (env[j] or env[j:j + gap_ms].any()):
                j += 1
            segs.append((i * 48, j * 48)); i = j
        else:
            i += 1
    return segs


def analyse_sweep(out):
    _, press, rel, a, rec0 = load(out)
    rows, stray = {}, []
    for s0, s1 in segments(a):
        t_recv = rec0 + s0 / R
        earlier = [k for k in press if press[k] <= t_recv]
        if s1 - s0 < 960 or not earlier:
            stray.append((t_recv, (s1 - s0) / R)); continue
        k = max(earlier)
        if t_recv > rel[k] + 1.0:  # long after the release: not this hold's
            stray.append((t_recv, (s1 - s0) / R)); continue
        # The delay from source to here, read where the burst is steady; its
        # first tens of ms can be another sound (the talker's own PTT tone).
        ds = sorted((rec0 + (i + 240) / R - (freq(a, i) - 400) / 800) % 2.0
                    for i in range(s0 + 7200, s1 - 14400, 2400))
        if not ds:
            stray.append((t_recv, (s1 - s0) / R)); continue
        lat = ds[len(ds) // 2]
        lat = lat - 2.0 if lat > 1.9 else lat
        on = next((i for i in range(s0, s0 + R, 120) if rms(a, i) > 0.01 and
                   abs(freq(a, i) - sweep_at(rec0 + (i + 240) / R - lat)) < 25), None)
        if on is None:
            stray.append((t_recv, (s1 - s0) / R)); continue
        start, end = rec0 + on / R - lat, rec0 + s1 / R - lat
        mids = sorted(rms(a, i) for i in range(s0 + 24000, s1 - 24000, 4800)) or [rms(a, s0 + 24000)]
        steady = mids[len(mids) // 2]
        ramp = next(((i - on) / R for i in range(on, s1, 240) if rms(a, i) >= 0.7 * steady), 0)
        rows.setdefault(k, []).append(((start - press[k]) * 1e3, (end - rel[k]) * 1e3,
                                       lat * 1e3, (s1 - s0) / R, ramp * 1e3))
    print(' #   cut ms  tail ms  delay ms  heard s  ramp ms')
    for k in sorted(press):
        for r in rows.get(k, []):
            more = '  (more than one burst)' if len(rows[k]) > 1 else ''
            print(f'{k:2d} {r[0]:8.0f} {r[1]:8.0f} {r[2]:9.0f} {r[3]:8.2f} {r[4]:8.0f}{more}')
        if k not in rows:
            print(f'{k:2d}   nothing heard')
    cuts = sorted(r[0] for v in rows.values() for r in v)
    ramps = sorted(r[4] for v in rows.values() for r in v)
    if cuts:
        print(f'cut median {cuts[len(cuts) // 2]:.0f} ms (min {cuts[0]:.0f}, max {cuts[-1]:.0f}); '
              f'ramp median {ramps[len(ramps) // 2]:.0f} ms; holds heard {len(rows)}/{len(press)}')
    for t, dur in stray:
        print(f'HEARD OUTSIDE A HOLD: at {t:.3f}, {dur * 1e3:.0f} ms')
    if not stray:
        print('nothing heard outside a hold')


def analyse_speech(out):
    d, press, rel, rec, rec0 = load(out)
    t0 = float(d['T0'])
    x = np.load(os.path.join(out, 'speech.npy'))

    def src(t, n):
        i = int(round((t - t0) * R))
        return x[np.arange(i, i + n) % len(x)]

    def env(a, f=480):
        m = len(a) // f
        return 10 * np.log10(np.mean(a[:m * f].reshape(m, f) ** 2, axis=1) + 1e-12)

    def lvl(a):
        return 10 * np.log10(np.mean(a ** 2) + 1e-12)

    print(' #  delay ms  first100 dB  first300 dB  within6dB ms   (against the rest of the hold)')
    res = []
    for i in sorted(press):
        tp = press[i]
        s = src(tp, int((rel[i] - tp) * R))
        ref = s[int(0.6 * R):int(1.1 * R)]
        best = (-2, 0)
        for lag in range(int(0.02 * R), int(0.5 * R), 24):
            j = int(round((tp + 0.6 + lag / R - rec0) * R))
            seg = rec[j:j + len(ref)]
            if len(seg) < len(ref) or j < 0:
                continue
            c = float(np.dot(seg, ref) / (np.linalg.norm(seg) * np.linalg.norm(ref) + 1e-12))
            best = max(best, (c, lag))
        c, lag = best
        j0 = int(round((tp + lag / R - rec0) * R))
        heard = rec[j0:j0 + len(s)]
        if len(heard) < len(s):
            print(f'{i:2d}   recording ends early'); continue
        whole = lvl(heard[R // 2:]) - lvl(s[R // 2:])
        f100 = lvl(heard[:4800]) - lvl(s[:4800]) - whole
        f300 = lvl(heard[:14400]) - lvl(s[:14400]) - whole
        es, eh = env(s), env(heard)
        ok = next((m * 10 for m in range(len(es)) if es[m] > -45 and eh[m] > es[m] + whole - 6), None)
        res.append((f100, f300, ok if ok is not None else 999))
        print(f'{i:2d} {lag / R * 1e3:8.0f} {f100:12.1f} {f300:12.1f} {ok if ok is not None else -1:12d}'
              f'   (match {c:.2f})')
    if res:
        m = np.median(np.array(res), axis=0)
        print(f'median: first100 {m[0]:.1f} dB, first300 {m[1]:.1f} dB, within 6 dB after {m[2]:.0f} ms')


def analyse(out):
    mode = next((l.split()[1] for l in open(os.path.join(out, 'feed.log')) if l.startswith('mode')), 'sweep')
    (analyse_speech if mode == 'speech' else analyse_sweep)(out)


def devices(_):
    import soundcard as sc
    print('play into (speakers):')
    for d in sc.all_speakers():
        print('  ', d.name)
    print('record (microphones, loopback included):')
    for d in sc.all_microphones(include_loopback=True):
        print('  ', d.name, '(loopback)' if getattr(d, 'isloopback', False) else '')


def main():
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = p.add_subparsers(dest='cmd', required=True)
    sub.add_parser('devices').set_defaults(fn=devices)
    r = sub.add_parser('run')
    r.add_argument('out')
    r.add_argument('--mode', choices=['sweep', 'speech'], default='sweep')
    r.add_argument('--n', type=int, default=12)
    r.add_argument('--hold', type=float, default=1.5)
    r.add_argument('--play', required=True, help="part of the virtual cable's playback name")
    r.add_argument('--record', required=True, help="part of the listener's output device name")
    r.set_defaults(fn=run)
    an = sub.add_parser('analyse')
    an.add_argument('out')
    an.set_defaults(fn=lambda a: analyse(a.out))
    a = p.parse_args()
    a.fn(a)


if __name__ == '__main__':
    main()
