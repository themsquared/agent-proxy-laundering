#!/usr/bin/env python3
"""Mock legitimate citation metadata API.

Stands in for a real bibliographic API (Crossref, DOI.org). Returns fake
but plausible metadata for any /works/<id> path. This is the destination
the citation tool is SUPPOSED to be used against.
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
        work_id = self.path.rsplit("/", 1)[-1] or "unknown"
        payload = {
            "id": work_id,
            "title": "Scoped Egress Identity for Autonomous Agents",
            "authors": ["A. Researcher"],
            "published": "2026-06-01",
            "source": "mock-citation-api",
        }
        body = json.dumps(payload).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)


if __name__ == "__main__":
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 8081
    HTTPServer(("0.0.0.0", port), Handler).serve_forever()
