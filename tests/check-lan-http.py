"""Exercise the production scanner's real URLSession against loopback only."""
import http.server
import json
import subprocess
import sys
import threading

requests = []


class Handler(http.server.BaseHTTPRequestHandler):
    mode = "comfy"

    def do_GET(self):
        requests.append((self.server.server_port, self.path))
        assert self.path == "/system_stats"
        assert "Cookie" not in self.headers and "Authorization" not in self.headers
        self.send_response(302 if self.mode == "redirect" else 200)
        if self.mode == "redirect":
            self.send_header("Location", target)
        self.end_headers()
        if self.mode == "comfy":
            self.wfile.write(json.dumps({"system": {"os": "linux", "python_version": "3.12"}, "devices": []}).encode())
        elif self.mode == "html":
            self.wfile.write(b"<html>Unrelated device</html>")

    def log_message(self, *args):
        pass


servers = []
try:
    for mode in ["comfy", "redirect", "html"]:
        handler = type("Fixture", (Handler,), {"mode": mode})
        server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), handler)
        threading.Thread(target=server.serve_forever, daemon=True).start()
        servers.append(server)
    endpoints = [f"http://127.0.0.1:{s.server_port}" for s in servers]
    target = endpoints[0] + "/system_stats"
    output = subprocess.check_output([sys.argv[1], "--probe", *endpoints], text=True, timeout=15)
    assert output.strip().splitlines() == [endpoints[0]], output
    assert len(requests) == 3, requests  # A followed redirect would add a fourth request.
    print("PASS: real loopback HTTP discovery, HTML rejection and redirect refusal")
finally:
    for server in servers:
        server.shutdown()
        server.server_close()
