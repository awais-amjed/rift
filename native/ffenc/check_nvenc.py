#!/usr/bin/env python3
"""Decodes what test_nvenc_dmabuf.c wrote and checks each picture's numbers.

    native/ffenc/check_nvenc.py OUT_DIR
"""
import subprocess
import sys

folder = sys.argv[1]
failures = 0

RED, GREEN, BLUE, GRAY = (81, 90, 240), (145, 54, 34), (41, 240, 110), (125, 128, 128)
BLACK = (16, 128, 128)


def fail(message):
    global failures
    failures += 1
    print("FAIL:", message)


def pictures(name, width, height):
    """Each decoded picture of a stream as yuv420p bytes, one at a time."""
    size = width * height * 3 // 2
    decoder = subprocess.Popen(
        ["ffmpeg", "-v", "error", "-i", f"{folder}/{name}.h264",
         "-f", "rawvideo", "-pix_fmt", "yuv420p", "-"],
        stdout=subprocess.PIPE)
    while True:
        picture = decoder.stdout.read(size)
        if len(picture) < size:
            break
        yield picture
    decoder.wait()


def yuv(picture, width, height, x, y):
    u = width * height + (y // 2) * (width // 2) + x // 2
    return picture[y * width + x], picture[u], picture[u + width * height // 4]


def near(got, want, name):
    if any(abs(a - b) > 4 for a, b in zip(got, want)):
        fail(f"{name}: {got}, wanted {want}")


def quarters(picture, width, height, name, at=(RED, GREEN, BLUE, GRAY), left=0.2, right=0.8):
    places = ((left, 0.25), (right, 0.25), (left, 0.75), (right, 0.75))
    for colour, (x, y) in zip(at, places):
        near(yuv(picture, width, height, int(width * x), int(height * y)), colour, name)


def bar(name):
    width, height = 1920, 1080
    count = stale = 0
    for number, picture in enumerate(pictures(name, width, height)):
        count = number + 1
        row = picture[(height // 4) * width:(height // 4) * width + width]
        bright = [x for x, value in enumerate(row) if value > 225]
        if not bright or bright[0] != (number * 8) % (width - 40):
            stale += 1
        if number == 30:  # The bar is near the left, past the samples.
            quarters(picture, width, height, name, left=0.3, right=0.8)
    if count != 660:
        fail(f"{name}: {count} pictures")
    if stale:
        fail(f"{name}: the bar was wrong in {stale} of {count} pictures")
    print(f"{name}: {count} pictures, {stale} stale")


def last_of(name, width, height):
    picture = None
    for picture in pictures(name, width, height):
        pass
    return picture


for name in ("bar_606_xrgb", "bar_e08_xrgb", "bar_606_xbgr", "bar_e08_xbgr"):
    bar(name)

quarters(last_of("scaled", 1920, 1080), 1920, 1080, "scaled")

# 1000x800 in 1350x1080, with black bars either side.
letterbox = last_of("letterbox", 1920, 1080)
near(yuv(letterbox, 1920, 1080, 100, 540), BLACK, "letterbox's left bar")
near(yuv(letterbox, 1920, 1080, 1820, 540), BLACK, "letterbox's right bar")
quarters(letterbox, 1920, 1080, "letterbox", left=0.25, right=0.75)

# The crop is all red. Its place's chroma covers x < 102, y < 52 of the luma.
place = last_of("place", 640, 360)
near(yuv(place, 640, 360, 50, 25), RED, "the place")
for y in range(0, 360, 8):
    for x in range(0, 640, 8):
        if x >= 104 or y >= 54:
            near(yuv(place, 640, 360, x, y), BLACK, f"outside the place at {x},{y}")

# Turned clockwise: the buffer's bottom-left is now the top-left.
quarters(last_of("turned", 1080, 1920), 1080, 1920, "turned", at=(BLUE, RED, GRAY, GREEN))

# Scaled 3:1, every source pixel counts. Reports how far apart the row's values
# are in its middle: one sample a pixel keeps most of the stripes' 219.
stripes = last_of("stripes", 1280, 720)
row = stripes[360 * 1280 + 300:360 * 1280 + 980]
spread = max(row) - min(row)
print(f"stripes: values {spread} apart")
if spread > 110:
    fail(f"stripes scaled 3:1 alias: values {spread} apart")

# A repeat is the picture it repeats.
repeats = list(pictures("repeat", 1920, 1080))
if len(repeats) != 31:
    fail(f"repeat: {len(repeats)} pictures")
quarters(repeats[19], 1920, 1080, "before the repeats")
for number in (20, 29, 30):
    quarters(repeats[number], 1920, 1080, f"repeat {number}")

memory = list(pictures("memory", 1920, 1080))
if len(memory) != 90:
    fail(f"memory: {len(memory)} pictures")
quarters(memory[29], 1920, 1080, "before memory")
near(yuv(memory[59], 1920, 1080, 960, 540), (200, 100, 150), "from memory")
quarters(memory[89], 1920, 1080, "after memory")

if failures:
    sys.exit(f"{failures} failed")
print("nvenc pictures: ok")
