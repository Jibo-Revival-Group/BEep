"""Stand-in robot for the simulator check: serves the real BEacon page (BEam's beacon/public,
path in argv[1]) and answers /api/status like a Jibo, so the screenshots show the real page."""
import http.server
import json
import sys

PUBLIC = sys.argv[1]
STATUS = {
    'name': 'BEacon', 'host': {'name': '@be/be', 'version': '13.0.9'}, 'robot': True,
    'hostname': 'Test-Jibo', 'uptimeSeconds': 4133,
    'addresses': [{'iface': 'wlan0', 'address': '127.0.0.1'}],
    'paths': {}, 'theme': {'name': 'None', 'live': True}
}


class Handler(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=PUBLIC, **kwargs)

    def do_GET(self):
        if not self.path.startswith('/api/'):
            return super().do_GET()
        found = self.path.startswith('/api/status')
        body = json.dumps(STATUS if found else {'error': 'Not in the simulator check'}).encode()
        self.send_response(200 if found else 404)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Content-Length', str(len(body)))
        self.end_headers()
        self.wfile.write(body)


http.server.ThreadingHTTPServer(('0.0.0.0', 8123), Handler).serve_forever()
