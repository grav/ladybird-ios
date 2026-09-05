#!/usr/bin/env python3
"""Local, dependency-free resource-loading fixture for the iOS Simulator."""

from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json


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
            "/": ("text/html; charset=utf-8", HTML),
            "/style.css": ("text/css", b'@import "/import.css"; body {font: 18px Helvetica; margin: 20px} #linked {background: #b8efb8; padding: 12px}'),
            "/import.css": ("text/css", b'#imported {background: #bbddff; padding: 12px}'),
            "/wrong-mime.css": ("text/plain", b'#mime {display:none}'),
            "/requests": ("application/json", json.dumps(REQUESTS).encode()),
        }
        mime, body = routes.get(self.path, ("text/plain", b"Not found"))
        self.send_response(200 if self.path in routes else 404)
        self.send_header("Content-Type", mime)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("X-Content-Type-Options", "nosniff")
        self.end_headers()
        self.wfile.write(body)


if __name__ == "__main__":
    print("Fixture: http://localhost:8765/", flush=True)
    ThreadingHTTPServer(("127.0.0.1", 8765), Handler).serve_forever()
