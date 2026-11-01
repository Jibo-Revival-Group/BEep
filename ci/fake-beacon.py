"""Stand-in BEacon for the simulator check: answers /api/status like a robot and serves a page
that opens a confirm() dialog, so one screenshot shows discovery, the web view and native dialogs."""
import http.server
import json

PAGE = b"""<!doctype html><meta name="viewport" content="width=device-width, initial-scale=1">
<body style="font-family: -apple-system; background: #00d4f0; color: white; padding: 24px">
<h1>Fake BEacon</h1><p id="r">Waiting for the dialog...</p>
<script>setTimeout(function () {
  document.getElementById('r').textContent = confirm('Dialog from BEacon') ? 'confirmed' : 'cancelled';
}, 800);</script></body>"""


class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path.startswith('/api/status'):
            body = json.dumps({'name': 'BEacon', 'hostname': 'Test-Jibo',
                               'addresses': [{'iface': 'wlan0', 'address': '127.0.0.1'}]}).encode()
            kind = 'application/json'
        else:
            body, kind = PAGE, 'text/html'
        self.send_response(200)
        self.send_header('Content-Type', kind)
        self.send_header('Content-Length', str(len(body)))
        self.end_headers()
        self.wfile.write(body)


http.server.ThreadingHTTPServer(('0.0.0.0', 8123), Handler).serve_forever()
