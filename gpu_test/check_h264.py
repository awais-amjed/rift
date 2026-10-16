"""Reads an Annex B H264 file and says, for its slices, what LiveKit's frame
encryption leaves a receiver able to read: the cryptor keeps the first
slice's NAL header and one byte after it readable, and the receiver needs the
IDR's PPS id from there (h264::idr_readable_when_encrypted in the Rust crate).
Lives on the gpu-encoding branch only. Run it with `python -I`:

    python -I gpu_test/check_h264.py stream.h264
"""
import collections
import sys


def units(data):
    """(type, bytes after the NAL header) for each NAL unit."""
    starts = []
    i = 0
    while True:
        j = data.find(b"\x00\x00\x01", i)
        if j < 0:
            break
        starts.append(j + 3)
        i = j + 3
    for n, at in enumerate(starts):
        end = starts[n + 1] - 3 if n + 1 < len(starts) else len(data)
        if at < len(data):
            yield data[at] & 0x1F, data[at + 1:end]


def header_fields(body):
    """first_mb_in_slice, slice_type, pic_parameter_set_id and the bit the id
    ends at, or None if the bytes run out."""
    bits = "".join(f"{b:08b}" for b in body[:4])
    pos = 0
    values = []
    for _ in range(3):
        zeros = 0
        while pos < len(bits) and bits[pos] == "0":
            zeros += 1
            pos += 1
        if pos + 1 + zeros > len(bits):
            return None
        pos += 1
        value = (1 << zeros) - 1 + (int(bits[pos:pos + zeros], 2) if zeros else 0)
        pos += zeros
        values.append(value)
    return values[0], values[1], values[2], pos


def main(path):
    data = open(path, "rb").read()
    kinds = collections.Counter()
    idrs = unreadable = 0
    for kind, body in units(data):
        if kind not in (1, 5):
            continue
        fields = header_fields(body)
        if fields is None:
            continue
        first_mb, slice_type, pps_id, end = fields
        if first_mb != 0:
            continue
        kinds[("IDR" if kind == 5 else "slice", slice_type)] += 1
        if kind == 5:
            idrs += 1
            if end > 8:
                unreadable += 1
    for (kind, slice_type), n in sorted(kinds.items()):
        print(f"{kind} slice_type {slice_type}: {n}")
    verdict = "OK" if unreadable == 0 else "FAIL"
    print(f"{verdict}: {unreadable} of {idrs} IDRs put the PPS id past what "
          "encryption leaves readable")
    return 0 if unreadable == 0 else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1]))
