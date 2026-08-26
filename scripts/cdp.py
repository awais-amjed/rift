#!/usr/bin/env python3
"""Minimal Chrome DevTools Protocol driver over a hand-rolled WebSocket.

The X pointer is unusable on this machine (XTEST warps are refused), and no
websocket library is installed, so this speaks just enough of RFC 6455 to
dispatch input and grab screenshots straight from the page.
"""
import base64
import json
import os
import socket
import struct
import sys
import time
import urllib.request

MASK = 0x80


class WS:
    def __init__(self, url):
        assert url.startswith("ws://")
        rest = url[5:]
        hostport, path = rest.split("/", 1)
        path = "/" + path
        host, port = hostport.split(":")
        self.sock = socket.create_connection((host, int(port)), timeout=30)
        key = base64.b64encode(os.urandom(16)).decode()
        req = (
            f"GET {path} HTTP/1.1\r\nHost: {hostport}\r\nUpgrade: websocket\r\n"
            f"Connection: Upgrade\r\nSec-WebSocket-Key: {key}\r\n"
            f"Sec-WebSocket-Version: 13\r\n\r\n"
        )
        self.sock.sendall(req.encode())
        buf = b""
        while b"\r\n\r\n" not in buf:
            buf += self.sock.recv(4096)
        assert b"101" in buf.split(b"\r\n")[0], buf[:200]
        self.buf = buf.split(b"\r\n\r\n", 1)[1]
        self.next_id = 0

    def _recv_exact(self, n):
        while len(self.buf) < n:
            chunk = self.sock.recv(65536)
            if not chunk:
                raise IOError("socket closed")
            self.buf += chunk
        out, self.buf = self.buf[:n], self.buf[n:]
        return out

    def send(self, method, params=None):
        self.next_id += 1
        payload = json.dumps(
            {"id": self.next_id, "method": method, "params": params or {}}
        ).encode()
        header = bytearray([0x81])
        n = len(payload)
        if n < 126:
            header.append(MASK | n)
        elif n < 65536:
            header.append(MASK | 126)
            header += struct.pack(">H", n)
        else:
            header.append(MASK | 127)
            header += struct.pack(">Q", n)
        m = os.urandom(4)
        header += m
        self.sock.sendall(bytes(header) + bytes(b ^ m[i % 4] for i, b in enumerate(payload)))
        return self.next_id

    def recv(self):
        b0, b1 = self._recv_exact(2)
        n = b1 & 0x7F
        if n == 126:
            n = struct.unpack(">H", self._recv_exact(2))[0]
        elif n == 127:
            n = struct.unpack(">Q", self._recv_exact(8))[0]
        if b1 & MASK:
            m = self._recv_exact(4)
            data = bytes(b ^ m[i % 4] for i, b in enumerate(self._recv_exact(n)))
        else:
            data = self._recv_exact(n)
        return json.loads(data)

    def call(self, method, params=None):
        want = self.send(method, params)
        while True:
            msg = self.recv()
            if msg.get("id") == want:
                if "error" in msg:
                    raise RuntimeError(f"{method}: {msg['error']}")
                return msg.get("result", {})

    def wait_event(self, method, timeout=15):
        """Block until an event arrives. `call` throws events away."""
        deadline = time.time() + timeout
        while time.time() < deadline:
            self.sock.settimeout(max(0.5, deadline - time.time()))
            try:
                msg = self.recv()
            except OSError:
                continue
            if msg.get("method") == method:
                return msg.get("params", {})
        raise SystemExit(f"timed out waiting for {method}")


def page_ws(port, match="localhost"):
    """The app's tab, not merely the first one.

    Picking the first page target silently attaches to whatever else is open —
    a blank tab opened to blur the app is enough to make every evaluate return
    nothing and look like the app misbehaved. Prefer a target whose URL matches,
    and only fall back to the first real page.
    """
    with urllib.request.urlopen(f"http://127.0.0.1:{port}/json/list", timeout=10) as r:
        targets = [
            t for t in json.load(r)
            if t.get("type") == "page" and "chrome-extension" not in t.get("url", "")
        ]
    for t in targets:
        if match in t.get("url", ""):
            return t["webSocketDebuggerUrl"]
    if targets:
        return targets[0]["webSocketDebuggerUrl"]
    raise SystemExit("no page target")


def click(ws, x, y):
    for kind in ("mousePressed", "mouseReleased"):
        ws.call(
            "Input.dispatchMouseEvent",
            {"type": kind, "x": x, "y": y, "button": "left", "clickCount": 1,
             "buttons": 1 if kind == "mousePressed" else 0},
        )


def move(ws, x, y):
    """Park the pointer, so hover states can be read off a screenshot.

    The compositor is not involved — the event is dispatched inside the
    renderer — which is the whole reason this harness survives when the
    desktop one cannot inject input at all.
    """
    ws.call(
        "Input.dispatchMouseEvent",
        {"type": "mouseMoved", "x": x, "y": y, "buttons": 0},
    )


def rclick(ws, x, y):
    for kind in ("mousePressed", "mouseReleased"):
        ws.call(
            "Input.dispatchMouseEvent",
            {"type": kind, "x": x, "y": y, "button": "right", "clickCount": 1,
             "buttons": 2 if kind == "mousePressed" else 0},
        )


def type_text(ws, text):
    for ch in text:
        ws.call("Input.dispatchKeyEvent", {"type": "keyDown", "text": ch})
        ws.call("Input.dispatchKeyEvent", {"type": "keyUp", "text": ch})


def key(ws, name):
    codes = {
        "Enter": (13, "Enter", "\r"),
        "Backspace": (8, "Backspace", None),
        "Tab": (9, "Tab", None),
        "Escape": (27, "Escape", None),
    }
    code, k, text = codes[name]
    down = {"type": "keyDown", "windowsVirtualKeyCode": code, "key": k,
            "nativeVirtualKeyCode": code}
    if text:
        down["text"] = text
    ws.call("Input.dispatchKeyEvent", down)
    ws.call("Input.dispatchKeyEvent", {"type": "keyUp", "windowsVirtualKeyCode": code,
                                       "key": k, "nativeVirtualKeyCode": code})


def attach_file(ws, x, y, path):
    """Put a real file into the app's file input without the OS dialog.

    Clicking the composer's + opens a native chooser that no automation here
    can reach — on Linux it is a GTK window belonging to the browser. Chrome
    will hand the chooser over instead: with interception on, the dialog never
    opens and the page reports which input asked for it, which is the node
    `DOM.setFileInputFiles` needs.
    """
    ws.call("Page.enable")
    ws.call("DOM.enable")
    ws.call("Page.setInterceptFileChooserDialog", {"enabled": True})
    try:
        click(ws, x, y)
        event = ws.wait_event("Page.fileChooserOpened")
        node = event.get("backendNodeId")
        if node is None:
            raise SystemExit("file chooser carried no backendNodeId")
        ws.call("DOM.setFileInputFiles",
                {"files": [os.path.abspath(path)], "backendNodeId": node})
    finally:
        ws.call("Page.setInterceptFileChooserDialog", {"enabled": False})


def set_file_input(ws, path, selector="input[type=file]"):
    """Hand a file to an input that is already in the DOM.

    The companion to `attach_file`: Flutter's file_picker inserts the input and
    clicks it in one go, so by the time interception is armed the chooser has
    often already been asked for. The input is still there, and setting its
    files fires the same change event the picker is waiting on.
    """
    ws.call("DOM.enable")
    doc = ws.call("DOM.getDocument", {"depth": 1})
    node = ws.call("DOM.querySelector",
                   {"nodeId": doc["root"]["nodeId"], "selector": selector})
    if not node.get("nodeId"):
        raise SystemExit(f"no node matching {selector}")
    ws.call("DOM.setFileInputFiles",
            {"files": [os.path.abspath(path)], "nodeId": node["nodeId"]})


def shot(ws, path):
    r = ws.call("Page.captureScreenshot", {"format": "png"})
    with open(path, "wb") as f:
        f.write(base64.b64decode(r["data"]))
    return path


if __name__ == "__main__":
    port = int(sys.argv[1])
    ws = WS(page_ws(port))
    cmd = sys.argv[2]
    if cmd == "shot":
        print(shot(ws, sys.argv[3]))
    elif cmd == "click":
        click(ws, float(sys.argv[3]), float(sys.argv[4]))
    elif cmd == "move":
        move(ws, float(sys.argv[3]), float(sys.argv[4]))
    elif cmd == "rclick":
        rclick(ws, float(sys.argv[3]), float(sys.argv[4]))
    elif cmd == "type":
        type_text(ws, sys.argv[3])
    elif cmd == "key":
        key(ws, sys.argv[3])
    elif cmd == "attach":
        attach_file(ws, float(sys.argv[3]), float(sys.argv[4]), sys.argv[5])
    elif cmd == "setfile":
        set_file_input(ws, sys.argv[3])
    elif cmd == "eval":
        print(ws.call("Runtime.evaluate",
                      {"expression": sys.argv[3], "returnByValue": True}))
    print("ok")
