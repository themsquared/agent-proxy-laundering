#!/usr/bin/env python3
"""Mock arbitrary remote destination.

Stands in for anywhere a laundered fetch could point: an attacker's
collector, a cloud metadata endpoint, an internal service the agent was
never supposed to reach. It answers every request and counts how many it
received, so the demo proves a negative (it was never reached) with an
exact number instead of eyeballing output.
"""
import json
import sys
from http.server import BaseHTTPRequestHandler, HTTPServer

HITS = {"count": 0}


class Handler(BaseHTTPRequestHandler):
    def log_message(self, fmt, *args):
        pass

    def do_GET(self):
        if self.path == "/stats":
            body = json.dumps({"requests_received": HITS["count"]}).encode()
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
            return

        HITS["count"] += 1
        body = json.dumps({
            "reached": "attacker-target",
            "note": "this response proves whatever called it treated this host as a valid fetch target",
        }).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)


if __name__ == "__main__":
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 8082
    HTTPServer(("0.0.0.0", port), Handler).serve_forever()
