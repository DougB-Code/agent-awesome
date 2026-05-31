#!/usr/bin/env python3
"""Serves a deterministic OpenAI-compatible chat completion for smoke tests."""

from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
import os


class ChatHandler(BaseHTTPRequestHandler):
    """Handles health checks and chat completions for the smoke model."""

    def do_GET(self):
        """Returns a lightweight health response."""
        if self.path == "/health":
            self._write_json({"status": "ok"})
            return
        self.send_error(404)

    def do_POST(self):
        """Returns one deterministic assistant message."""
        if self.path != "/v1/chat/completions":
            self.send_error(404)
            return
        length = int(self.headers.get("content-length", "0"))
        if length > 0:
            self.rfile.read(length)
        self._write_json(
            {
                "choices": [
                    {
                        "message": {
                            "role": "assistant",
                            "content": "remote gemma ready",
                        }
                    }
                ]
            }
        )

    def log_message(self, format, *args):
        """Suppresses default request logging for cleaner smoke output."""
        return

    def _write_json(self, payload):
        """Writes a JSON response body."""
        data = json.dumps(payload).encode("utf-8")
        self.send_response(200)
        self.send_header("content-type", "application/json")
        self.send_header("content-length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)


def main():
    """Starts the mock chat completion server."""
    host = os.environ.get("AA_MOCK_MODEL_HOST", "127.0.0.1")
    port = int(os.environ.get("AA_MOCK_MODEL_PORT", "18180"))
    ThreadingHTTPServer((host, port), ChatHandler).serve_forever()


if __name__ == "__main__":
    main()
