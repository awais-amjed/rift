#!/usr/bin/env python3
"""Decodes what test_d3d11.c wrote for one encoder and checks each picture.

    native/ffenc/check_d3d11.py OUT_DIR ENCODER
"""
import subprocess
import sys

folder, encoder = sys.argv[1], sys.argv[2]
WIDTH, HEIGHT = 1920, 1080
failures = 0

# BT.601 limited, as ffenc tells viewers.
RED, GREEN, BLUE, GRAY = (81, 90, 240), (145, 54, 34), (41, 240, 110), (125, 128, 128)
BLACK = (16, 128, 128)
MEMORY = (200, 100, 150)


def fail(message):
    global failures
    failures += 1
    print(f"FAIL: {encoder}: {message}")


def pictures(name):
    """Each decoded picture of a stream as yuv420p bytes."""
    size = WIDTH * HEIGHT * 3 // 2
    decoder = subprocess.Popen(
        ["ffmpeg", "-v", "error", "-i", f"{folder}/{encoder}-{name}.h264",
         "-f", "rawvideo", "-pix_fmt", "yuv420p", "-"],
        stdout=subprocess.PIPE)
    while True:
        picture = decoder.stdout.read(size)
        if len(picture) < size:
            break
        yield picture
    decoder.wait()


def yuv(picture, x, y):
    u = WIDTH * HEIGHT + (y // 2) * (WIDTH // 2) + x // 2
    return picture[y * WIDTH + x], picture[u], picture[u + WIDTH * HEIGHT // 4]


def near(got, want, what):
    if any(abs(a - b) > 4 for a, b in zip(got, want)):
        fail(f"{what}: {tuple(got)}, wanted {want}")
        return False
    return True


def quarters(picture, what):
    places = ((0.2, 0.25), (0.8, 0.25), (0.2, 0.75), (0.8, 0.75))
    return all([near(yuv(picture, int(WIDTH * x), int(HEIGHT * y)), colour, what)
                for colour, (x, y) in zip((RED, GREEN, BLUE, GRAY), places)])


def count(name, got, want):
    if got != want:
        fail(f"{name}: {got} pictures decoded, wanted {want}")


n = 0
for n, picture in enumerate(pictures("quarters"), 1):
    if not quarters(picture, f"quarters, picture {n}"):
        break
count("quarters", n, 90)

n = late = 0
for n, picture in enumerate(pictures("bar"), 1):
    row = picture[(HEIGHT // 4) * WIDTH:(HEIGHT // 4) * WIDTH + WIDTH]
    bright = [x for x, value in enumerate(row) if value > 225]
    want = ((n - 1) * 8) % (WIDTH - 40)
    if not bright or abs(bright[0] - want) > 2:
        late += 1
        if late <= 3:
            fail(f"bar, picture {n}: at {bright[0] if bright else None}, wanted {want}")
count("bar", n, 300)

n = 0
for n, picture in enumerate(pictures("letterbox"), 1):
    ok = (near(yuv(picture, 960, 540), BLUE, f"letterbox, picture {n}, middle")
          and near(yuv(picture, 100, 540), BLACK, f"letterbox, picture {n}, left")
          and near(yuv(picture, 1820, 540), BLACK, f"letterbox, picture {n}, right"))
    if not ok:
        break
count("letterbox", n, 30)

n = 0
for n, picture in enumerate(pictures("memory"), 1):
    what = f"memory, picture {n}"
    ok = (near(yuv(picture, 960, 540), MEMORY, what) if 30 < n <= 60
          else quarters(picture, what))
    if not ok:
        break
count("memory", n, 90)

print(f"{encoder}: {'%d failures' % failures if failures else 'every picture right'}")
sys.exit(1 if failures else 0)
