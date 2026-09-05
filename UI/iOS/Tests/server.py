#!/usr/bin/env python3
"""Local, dependency-free resource-loading fixture for the iOS Simulator."""

from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
import struct
import zlib
from pathlib import Path

REPO = Path(__file__).resolve().parents[3]
FONTS_HTML = '''<!doctype html><style>
body {font: 20px Helvetica; margin:20px}
@font-face {font-family: Same; src:url(/font.ttf)}
@font-face {font-family: Allowed; src:url(http://127.0.0.1:8765/font-cors.ttf)}
@font-face {font-family: Blocked; src:url(http://127.0.0.1:8765/font-blocked.ttf)}
@font-face {font-family: Invalid; src:url(/invalid.woff2)}
@font-face {font-family: Woff2; src:url(/ethiopic.woff2)}
</style><h1>Downloaded fonts</h1>
<p>First two samples must use chunky test letters. Denied and invalid samples must use Helvetica.</p>
<p style="font-family:Same,Helvetica">Same origin: ABC abc 123</p>
<p style="font-family:Allowed,Helvetica">CORS allowed: ABC abc 123</p>
<p style="font-family:Blocked,Helvetica">CORS denied: ABC abc 123</p>
<p style="font-family:Invalid,Helvetica">Invalid font: ABC abc 123</p>
<p style="font-family:Woff2,Helvetica">WOFF2 Ethiopic: ሰላም</p>'''.encode()


def test_png():
    def chunk(kind, data):
        return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data))

    # A tiny red/blue raster fixture, generated without third-party dependencies.
    pixels = b"\x00\xff\x00\x00\x00\x00\xff" * 2
    return (b"\x89PNG\r\n\x1a\n"
            + chunk(b"IHDR", struct.pack(">IIBBBBB", 2, 2, 8, 2, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(pixels)) + chunk(b"IEND", b""))


HTML = b'''<!doctype html><meta name="viewport" content="width=device-width">
<title>iOS resource smoke test</title>
<link rel="stylesheet" href="/redirect.css">
<link rel="stylesheet" href="/missing.css">
<link rel="stylesheet" href="/wrong-mime.css">
<h1>Resource loading</h1>
<p id="linked">Linked CSS: green background</p>
<p id="imported">Imported CSS: blue background</p>
<p id="mime">Wrong MIME: must stay visible</p>
<p>Missing CSS must not prevent this page from rendering.</p>
<p>Image: red left half, blue right half</p>
<img src="/test.png" width="120" height="60" alt="Raster image failed">
<div id="background" style="width:120px;height:60px">CSS background</div>
<p><img src="/broken.png" alt="Broken image fallback"></p>
<div style="height: 1100px">Scroll down to the bottom marker.</div>
<p id="bottom">Bottom marker</p>'''

REQUESTS = []


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        REQUESTS.append(self.path)
        if self.path == "/redirect.css":
            self.send_response(302)
            self.send_header("Location", "/style.css")
            self.end_headers()
            return
        routes = {
            "/fonts": ("text/html; charset=utf-8", FONTS_HTML),
            "/font.ttf": ("font/ttf", (REPO / "Base/res/fonts/SerenitySans-Regular.ttf").read_bytes()),
            "/font-cors.ttf": ("font/ttf", (REPO / "Base/res/fonts/SerenitySans-Regular.ttf").read_bytes()),
            "/font-blocked.ttf": ("font/ttf", (REPO / "Base/res/fonts/SerenitySans-Regular.ttf").read_bytes()),
            "/invalid.woff2": ("font/woff2", b"invalid font"),
            "/ethiopic.woff2": ("font/woff2", (REPO / "Tests/LibWeb/Assets/NotoSansEthiopic.woff2").read_bytes()),
            "/links": ("text/html", b'<!doctype html><base href="/nested/"><style>body {margin:20px} a {display:block; padding:20px}</style><a href="../destination"><span>Tap nested text to follow relative link</span></a><div style="height:1000px"></div><a href="../destination">Scrolled link</a>'),
            "/destination": ("text/html", b'<!doctype html><h1>Link navigation passed</h1>'),
            "/": ("text/html; charset=utf-8", HTML),
            "/style.css": ("text/css", b'@import "/import.css"; body {font: 18px Helvetica; margin: 20px} #linked {background: #b8efb8; padding: 12px}'),
            "/import.css": ("text/css", b'#imported {background: #bbddff; padding: 12px} #background {background-image: url(/background.png); background-size: 100% 100%; color: white}'),
            "/test.png": ("image/png", test_png()),
            "/background.png": ("image/png", test_png()),
            "/broken.png": ("image/png", b"invalid PNG"),
            "/wrong-mime.css": ("text/plain", b'#mime {display:none}'),
            "/requests": ("application/json", json.dumps(REQUESTS).encode()),
        }
        mime, body = routes.get(self.path, ("text/plain", b"Not found"))
        self.send_response(200 if self.path in routes else 404)
        self.send_header("Content-Type", mime)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("X-Content-Type-Options", "nosniff")
        if self.path == "/font-cors.ttf":
            self.send_header("Access-Control-Allow-Origin", "http://localhost:8765")
        self.end_headers()
        self.wfile.write(body)


if __name__ == "__main__":
    print("Fixture: http://localhost:8765/", flush=True)
    ThreadingHTTPServer(("127.0.0.1", 8765), Handler).serve_forever()
