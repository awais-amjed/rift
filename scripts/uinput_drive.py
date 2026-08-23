#!/usr/bin/env python3
"""Synthetic mouse + keyboard for driving the Linux client under Wayland.

XTEST — what `xdotool` uses — is refused by the GNOME Wayland compositor, and
the refusal is silent: `mousemove` returns success and the pointer does not
move. A uinput device is not synthetic input as far as the compositor is
concerned, it is a *device*, so it is honoured on Wayland and XWayland alike.

The pointer reports *relative* motion, like an ordinary mouse. Absolute axes
look reasonable and do not work: a device carrying ABS_X/ABS_Y without the
BTN_TOUCH or BTN_TOOL_PEN that would mark it a touchscreen or a tablet is bound
by the kernel as a joystick (it shows up as `jsN` in /proc/bus/input/devices),
and libinput ignores joysticks — so the device is created, the writes succeed,
and the pointer never moves. Absolute placement is done by slamming to the
top-left corner with one large negative delta and stepping back out from there,
which is what the compositor clamping the pointer to the screen gives us.

Needs membership of the `input` group for /dev/uinput; no root, no X.

    python3 scripts/uinput_drive.py move 400 300
    python3 scripts/uinput_drive.py click 400 300
    python3 scripts/uinput_drive.py rclick 400 300
    python3 scripts/uinput_drive.py type 'hello world'
    python3 scripts/uinput_drive.py key enter
    python3 scripts/uinput_drive.py scroll -5

A device is added to the session asynchronously, and until libinput has picked
it up its events go nowhere. Creating one per command is therefore a coin flip:
it works, then silently stops, and the failure looks like the app has hung. Run
a long-lived device instead and send commands to it —

    python3 scripts/uinput_drive.py serve &      # hold the device open
    python3 scripts/uinput_drive.py send click 400 300
    python3 scripts/uinput_drive.py send type 'hello'
    python3 scripts/uinput_drive.py send quit

`send` falls back to a one-shot device when no server is listening, so existing
callers keep working.
"""
import fcntl, os, struct, subprocess, sys, time

UINPUT = '/dev/uinput'
FIFO = os.environ.get('RIFT_UINPUT_FIFO', '/tmp/rift-uinput.fifo')

# Long enough for udev to tag the new device and libinput to add it to the
# seat. Below about a second the first events are routinely lost.
SETTLE_AFTER_CREATE = 1.6
SCREEN_W, SCREEN_H = 1920, 1080

EV_SYN, EV_KEY, EV_REL, EV_ABS = 0, 1, 2, 3
SYN_REPORT = 0
ABS_X, ABS_Y = 0, 1
REL_X, REL_Y, REL_WHEEL = 0, 1, 8
BTN_LEFT, BTN_RIGHT = 0x110, 0x111

# Small enough that pointer acceleration stays out of the way, and a handful of
# correction rounds to absorb whatever it still applies.
_MOVE_STEP = 6
_MOVE_CORRECTIONS = 14


def pointer_position():
    """Where the pointer actually is, or None if X cannot say.

    XWayland only tracks the pointer while it is over an X window, and reports
    a stale position otherwise — so this can lie, and a caller that needs the
    truth should keep the pointer over the window it is driving.
    """
    try:
        out = subprocess.run(['xdotool', 'getmouselocation'],
                             capture_output=True, text=True, timeout=2).stdout
        parts = dict(p.split(':') for p in out.split() if ':' in p)
        return int(parts['x']), int(parts['y'])
    except Exception:
        return None


def _iow(nr, size):
    return (1 << 30) | (size << 16) | (0x55 << 8) | nr


UI_SET_EVBIT = _iow(100, 4)
UI_SET_KEYBIT = _iow(101, 4)
UI_SET_RELBIT = _iow(102, 4)
UI_SET_ABSBIT = _iow(103, 4)
UI_DEV_CREATE = (0x55 << 8) | 1
UI_DEV_DESTROY = (0x55 << 8) | 2

# ── keycodes ──────────────────────────────────────────────
KEY = {}
for i, c in enumerate('1234567890'):
    KEY[c] = 2 + i
for i, c in enumerate('qwertyuiop'):
    KEY[c] = 16 + i
for i, c in enumerate('asdfghjkl'):
    KEY[c] = 30 + i
for i, c in enumerate('zxcvbnm'):
    KEY[c] = 44 + i
KEY.update({
    '\n': 28, 'enter': 28, 'esc': 1, 'escape': 1, 'backspace': 14, 'tab': 15,
    ' ': 57, 'space': 57, '-': 12, '=': 13, '[': 26, ']': 27, ';': 39,
    "'": 40, '`': 41, '\\': 43, ',': 51, '.': 52, '/': 53,
    'left': 105, 'right': 106, 'up': 103, 'down': 108,
    'home': 102, 'end': 107, 'delete': 111, 'pageup': 104, 'pagedown': 109,
})
KEY_LEFTSHIFT, KEY_LEFTCTRL, KEY_LEFTALT = 42, 29, 56
MODS = {'ctrl': KEY_LEFTCTRL, 'shift': KEY_LEFTSHIFT, 'alt': KEY_LEFTALT}
SHIFTED = {
    '!': '1', '@': '2', '#': '3', '$': '4', '%': '5', '^': '6', '&': '7',
    '*': '8', '(': '9', ')': '0', '_': '-', '+': '=', '{': '[', '}': ']',
    ':': ';', '"': "'", '~': '`', '|': '\\', '<': ',', '>': '.', '?': '/',
}


class Device:
    # A device that declares pointer axes is classified as a pointer, and a
    # pointer's key events are not routed to the focused window — they simply
    # vanish, with clicks still working, which makes it look like the app has
    # stopped accepting text. So the keyboard is a separate device that
    # declares no axes and no buttons at all.
    def __init__(self, keyboard_only=False):
        self.keyboard_only = keyboard_only
        self.fd = os.open(UINPUT, os.O_WRONLY | os.O_NONBLOCK)
        events = (EV_KEY, EV_SYN) if keyboard_only else (EV_KEY, EV_REL,
                                                         EV_SYN)
        for ev in events:
            fcntl.ioctl(self.fd, UI_SET_EVBIT, ev)
        codes = set(KEY.values()) | {KEY_LEFTSHIFT, KEY_LEFTCTRL, KEY_LEFTALT}
        if not keyboard_only:
            codes |= {BTN_LEFT, BTN_RIGHT}
        for code in codes:
            fcntl.ioctl(self.fd, UI_SET_KEYBIT, code)
        if not keyboard_only:
            for axis in (REL_X, REL_Y, REL_WHEEL):
                fcntl.ioctl(self.fd, UI_SET_RELBIT, axis)

        absmax = [0] * 64
        absmax[ABS_X], absmax[ABS_Y] = SCREEN_W - 1, SCREEN_H - 1
        name = b'rift-test-keyboard' if keyboard_only else b'rift-test-input'
        dev = struct.pack('80sHHHHi', name, 3, 0x1234, 0x5678, 1, 0)
        dev += struct.pack('64i', *absmax)          # absmax
        dev += struct.pack('64i', *([0] * 64))      # absmin
        dev += struct.pack('64i', *([0] * 64))      # absfuzz
        dev += struct.pack('64i', *([0] * 64))      # absflat
        os.write(self.fd, dev)
        fcntl.ioctl(self.fd, UI_DEV_CREATE)
        # The compositor has to notice the new device and settle before it will
        # route anything from it; without this the first events are dropped.
        time.sleep(SETTLE_AFTER_CREATE)

    def emit(self, type_, code, value):
        os.write(self.fd, struct.pack('llHHi', 0, 0, type_, code, value))

    def syn(self):
        self.emit(EV_SYN, SYN_REPORT, 0)

    def move(self, x, y):
        """Put the pointer at an absolute screen position.

        Relative motion has no origin, so one is made: a delta far larger than
        any screen drives the pointer into the top-left corner, where the
        compositor clamps it.

        Stepping back out is done in small increments and then *checked*,
        because pointer acceleration is applied to synthetic motion exactly as
        it is to a real mouse: one large delta lands well past where it was
        aimed, and the click that follows goes to whatever is there — often
        another window, which takes the keyboard focus with it. Small steps
        keep the velocity low enough that acceleration is roughly 1:1, and the
        closed loop corrects whatever is left over.
        """
        self._corner()
        for _ in range(_MOVE_CORRECTIONS):
            at = pointer_position()
            if at is None:
                # No X window under the pointer to ask — fall back to open
                # loop and accept the error rather than spinning.
                self._nudge(int(x), int(y))
                break
            dx, dy = int(x) - at[0], int(y) - at[1]
            if abs(dx) <= 1 and abs(dy) <= 1:
                break
            self._nudge(dx, dy)
        time.sleep(0.05)

    def _corner(self):
        for _ in range(4):
            self.emit(EV_REL, REL_X, -SCREEN_W)
            self.emit(EV_REL, REL_Y, -SCREEN_H)
            self.syn()
            time.sleep(0.004)
        time.sleep(0.02)

    def _nudge(self, dx, dy):
        """Travel (dx, dy) in steps small enough not to be accelerated."""
        while dx or dy:
            sx = max(-_MOVE_STEP, min(_MOVE_STEP, dx))
            sy = max(-_MOVE_STEP, min(_MOVE_STEP, dy))
            self.emit(EV_REL, REL_X, sx)
            self.emit(EV_REL, REL_Y, sy)
            self.syn()
            time.sleep(0.002)
            dx -= sx
            dy -= sy

    def click(self, button=BTN_LEFT):
        self.emit(EV_KEY, button, 1)
        self.syn()
        time.sleep(0.05)
        self.emit(EV_KEY, button, 0)
        self.syn()
        time.sleep(0.05)

    def tap(self, code, mods=()):
        for m in mods:
            self.emit(EV_KEY, m, 1)
        self.emit(EV_KEY, code, 1)
        self.syn()
        time.sleep(0.012)
        self.emit(EV_KEY, code, 0)
        for m in reversed(mods):
            self.emit(EV_KEY, m, 0)
        self.syn()
        time.sleep(0.02)

    def type(self, text):
        for ch in text:
            if ch in SHIFTED:
                self.tap(KEY[SHIFTED[ch]], (KEY_LEFTSHIFT,))
            elif ch.isupper():
                self.tap(KEY[ch.lower()], (KEY_LEFTSHIFT,))
            elif ch in KEY:
                self.tap(KEY[ch])
            else:
                raise SystemExit(f'unmapped character {ch!r}')

    def scroll(self, ticks):
        step = 1 if ticks > 0 else -1
        for _ in range(abs(ticks)):
            self.emit(EV_REL, REL_WHEEL, step)
            self.syn()
            time.sleep(0.03)

    def clear_mods(self):
        """Release every modifier, in case one was left logically held.

        A device that dies mid-chord — a crash between key-down and key-up —
        leaves the compositor believing the modifier is still held, and every
        later keystroke silently becomes a shortcut instead of a character.
        Nothing on screen says so: typing simply stops working.
        """
        for code in (KEY_LEFTSHIFT, KEY_LEFTCTRL, KEY_LEFTALT):
            self.emit(EV_KEY, code, 0)
        self.syn()
        time.sleep(0.05)

    def close(self):
        fcntl.ioctl(self.fd, UI_DEV_DESTROY)
        os.close(self.fd)


def run(dev, cmd, args):
    if cmd == 'move':
        dev.move(int(args[0]), int(args[1]))
    elif cmd in ('click', 'rclick', 'dclick'):
        if len(args) >= 2:
            dev.move(int(args[0]), int(args[1]))
            time.sleep(0.12)
        button = BTN_RIGHT if cmd == 'rclick' else BTN_LEFT
        dev.click(button)
        if cmd == 'dclick':
            time.sleep(0.06)
            dev.click(button)
    elif cmd == 'type':
        dev.clear_mods()
        dev.type(args[0])
    elif cmd == 'key':
        for spec in args:
            parts = spec.lower().split('+')
            mods = tuple(MODS[p] for p in parts[:-1])
            dev.tap(KEY[parts[-1]], mods)
    elif cmd == 'clearmods':
        dev.clear_mods()
    elif cmd == 'scroll':
        dev.scroll(int(args[0]))
    else:
        raise SystemExit(f'unknown command {cmd}')


def serve():
    """Hold one device open and run whatever is written to the FIFO."""
    if os.path.exists(FIFO):
        os.unlink(FIFO)
    os.mkfifo(FIFO, 0o600)
    dev = Device()
    print(f'ready {FIFO}', flush=True)
    try:
        while True:
            with open(FIFO) as fifo:
                for line in fifo:
                    parts = line.rstrip('\n').split('\t')
                    if not parts or not parts[0]:
                        continue
                    if parts[0] == 'quit':
                        return
                    try:
                        run(dev, parts[0], parts[1:])
                    except Exception as err:
                        print(f'error: {err}', file=sys.stderr, flush=True)
    finally:
        dev.close()
        if os.path.exists(FIFO):
            os.unlink(FIFO)


def send(cmd, args):
    """Hand one command to a running server, or do it one-shot if none is up."""
    if os.path.exists(FIFO):
        try:
            fd = os.open(FIFO, os.O_WRONLY | os.O_NONBLOCK)
            os.write(fd, ('\t'.join([cmd, *args]) + '\n').encode())
            os.close(fd)
            return
        except OSError:
            pass  # nobody reading — fall through to a one-shot device
    dev = Device(keyboard_only=False)
    try:
        run(dev, cmd, args)
    finally:
        time.sleep(0.1)
        dev.close()


def main():
    if len(sys.argv) < 2:
        raise SystemExit(__doc__)
    cmd, args = sys.argv[1], sys.argv[2:]
    if cmd == 'serve':
        serve()
        return
    if cmd == 'send':
        send(args[0], args[1:])
        return
    send(cmd, args)


if __name__ == '__main__':
    main()
