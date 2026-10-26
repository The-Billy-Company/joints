"""Pinned source transport uses real TLS and HTTP refusals at its network seam."""

from __future__ import annotations

import hashlib
import io
import os
import socket
import ssl
import subprocess
import tempfile
import threading
import time
import unittest
import urllib.parse
from contextlib import ExitStack
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from unittest.mock import patch

import breadth


class _Sources(BaseHTTPRequestHandler):
    def do_GET(self):
        case = self.server.case
        host = self.headers["Host"]
        case.requests.append((host, self.path, dict(self.headers)))
        status, body, headers, delay = case.replies[host]
        time.sleep(delay)
        self.send_response(status)
        self.send_header("Content-Length", str(len(body)))
        for key, value in headers.items():
            self.send_header(key, value)
        self.end_headers()
        try:
            self.wfile.write(body)
        except OSError:
            pass  # The deadline control deliberately closes its TLS peer.

    def log_message(self, *_args):
        pass


class PinnedSourceTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.certificate = tempfile.TemporaryDirectory()
        root = Path(cls.certificate.name)
        config = root / "openssl.cnf"
        config.write_text(
            "[req]\ndistinguished_name=dn\nx509_extensions=names\n"
            "[dn]\n[names]\nsubjectAltName=DNS:raw.githubusercontent.com,DNS:api.github.com\n"
        )
        cls.cert, cls.key = root / "cert.pem", root / "key.pem"
        subprocess.run(
            [
                "openssl",
                "req",
                "-x509",
                "-newkey",
                "rsa:2048",
                "-nodes",
                "-subj",
                "/CN=pinned-source-test",
                "-days",
                "1",
                "-config",
                str(config),
                "-keyout",
                str(cls.key),
                "-out",
                str(cls.cert),
            ],
            check=True,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )

    @classmethod
    def tearDownClass(cls):
        cls.certificate.cleanup()

    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.stack = ExitStack()
        self.addCleanup(self.stack.close)
        self.requests = []
        self.payload = b"the exact pinned source\n"
        self.ref = "0123456789abcdef0123456789abcdef01234567"
        self.path = "README.md"
        self.coordinate = f"owner/repo/{self.ref}/{self.path}"
        self.replies = {
            "raw.githubusercontent.com": (429, b"rate limited", {}, 0),
            "api.github.com": (200, self.payload, {}, 0),
        }
        self.server = ThreadingHTTPServer(("127.0.0.1", 0), _Sources)
        self.server.case = self
        context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        context.load_cert_chain(self.cert, self.key)
        self.server.socket = context.wrap_socket(self.server.socket, server_side=True)
        self.worker = threading.Thread(
            target=self.server.serve_forever, kwargs={"poll_interval": 0.01}
        )
        self.worker.start()
        self.addCleanup(self.close_server)
        self.context = ssl.create_default_context(cafile=str(self.cert))
        self.stack.enter_context(
            patch("ssl._create_default_https_context", return_value=self.context)
        )
        self.stack.enter_context(patch("urllib.request._opener", None))
        resolve = socket.getaddrinfo

        def loopback(host, port, *args, **kwargs):
            self.assertIn(host, self.replies, "transport tried an unapproved hostname")
            return resolve("127.0.0.1", self.server.server_port, *args, **kwargs)

        self.stack.enter_context(patch("socket.getaddrinfo", side_effect=loopback))
        self.stack.enter_context(
            patch.dict(
                os.environ,
                {
                    "NO_PROXY": "*",
                    "no_proxy": "*",
                    "GITHUB_TOKEN": "not-a-real-credential",
                },
            )
        )
        self.stack.enter_context(patch.object(breadth, "DEST", self.root))
        self.stack.enter_context(
            patch.object(
                breadth,
                "SOURCES",
                {
                    "source": (
                        self.coordinate,
                        "source.md",
                        hashlib.sha256(self.payload).hexdigest(),
                    ),
                },
            )
        )
        self.stack.enter_context(patch("sys.stdout", new=io.StringIO()))
        self.stack.enter_context(patch("sys.stderr", new=io.StringIO()))

    def close_server(self):
        self.server.shutdown()
        self.server.server_close()
        self.worker.join()

    def test_raw_success_keeps_the_single_read(self):
        self.replies["raw.githubusercontent.com"] = (200, self.payload, {}, 0)
        self.assertEqual(breadth.fetch(), 0)
        self.assertEqual((self.root / "source.md").read_bytes(), self.payload)
        self.assertEqual(
            [host for host, _, _ in self.requests], ["raw.githubusercontent.com"]
        )

    def test_rate_limit_falls_back_to_the_same_encoded_pin(self):
        self.assertEqual(breadth.fetch(), 0)
        self.assertEqual((self.root / "source.md").read_bytes(), self.payload)
        self.assertEqual(
            [host for host, _, _ in self.requests],
            ["raw.githubusercontent.com", "api.github.com"],
        )
        raw, api = (urllib.parse.urlsplit(path) for _, path, _ in self.requests)
        self.assertEqual(urllib.parse.unquote(raw.path), "/" + self.coordinate)
        self.assertEqual(
            urllib.parse.unquote(api.path), "/repos/owner/repo/contents/" + self.path
        )
        self.assertEqual(urllib.parse.parse_qs(api.query), {"ref": [self.ref]})
        self.assertTrue(
            all("Authorization" not in headers for _, _, headers in self.requests)
        )
        self.assertEqual(
            self.requests[1][2]["Accept"], "application/vnd.github.raw+json"
        )
        self.assertFalse((self.root / "source.md.part").exists())

    def test_wrong_fallback_bytes_cannot_replace_an_existing_source(self):
        before = b"previous source"
        (self.root / "source.md").write_bytes(before)
        self.replies["api.github.com"] = (200, b"different bytes", {}, 0)
        self.assertEqual(breadth.fetch(), 1)
        self.assertEqual((self.root / "source.md").read_bytes(), before)
        self.assertFalse((self.root / "source.md.part").exists())

    def test_source_path_keeps_url_delimiters_inside_the_same_pin(self):
        self.path = "a space/percent%#?.md"
        self.coordinate = f"owner/repo/{self.ref}/{self.path}"
        breadth.SOURCES["source"] = (
            self.coordinate,
            "source.md",
            hashlib.sha256(self.payload).hexdigest(),
        )
        self.assertEqual(breadth.fetch(), 0)
        raw, api = (urllib.parse.urlsplit(path) for _, path, _ in self.requests)
        self.assertEqual(urllib.parse.unquote(raw.path), "/" + self.coordinate)
        self.assertEqual(
            urllib.parse.unquote(api.path), "/repos/owner/repo/contents/" + self.path
        )
        self.assertEqual(urllib.parse.parse_qs(api.query), {"ref": [self.ref]})

    def test_other_http_errors_do_not_switch_authority(self):
        for status in (403, 404, 500):
            with self.subTest(status=status):
                self.requests.clear()
                self.replies["raw.githubusercontent.com"] = (status, b"refused", {}, 0)
                self.assertEqual(breadth.fetch(), 1)
                self.assertEqual(
                    [host for host, _, _ in self.requests],
                    ["raw.githubusercontent.com"],
                )
                self.assertFalse((self.root / "source.md").exists())

    def test_fallback_http_errors_leave_the_existing_source_intact(self):
        before = b"previous source"
        (self.root / "source.md").write_bytes(before)
        for status in (403, 404, 429, 500):
            with self.subTest(status=status):
                self.requests.clear()
                self.replies["api.github.com"] = (status, self.payload, {}, 0)
                self.assertEqual(breadth.fetch(), 1)
                self.assertEqual(len(self.requests), 2)
                self.assertEqual((self.root / "source.md").read_bytes(), before)
                self.assertFalse((self.root / "source.md.part").exists())

    def test_untrusted_tls_is_not_a_rate_limit_fallback(self):
        with (
            patch(
                "ssl._create_default_https_context",
                return_value=ssl.create_default_context(),
            ),
            patch("urllib.request._opener", None),
        ):
            self.assertEqual(breadth.fetch(), 1)
        self.assertEqual(self.requests, [])
        self.assertFalse((self.root / "source.md").exists())

    def test_api_redirects_cannot_change_the_coordinate_or_host(self):
        for location in ("/another-coordinate", "https://foreign.invalid/source"):
            with self.subTest(location=location):
                self.requests.clear()
                self.replies["api.github.com"] = (302, b"", {"Location": location}, 0)
                self.assertEqual(breadth.fetch(), 1)
                self.assertEqual(len(self.requests), 2)
                self.assertFalse((self.root / "source.md").exists())

    def test_fallback_uses_only_the_remaining_request_timeout(self):
        self.replies["raw.githubusercontent.com"] = (429, b"rate limited", {}, 0.5)
        self.replies["api.github.com"] = (200, self.payload, {}, 0.5)
        with (
            patch.object(breadth, "_FETCH_TIMEOUT", 0.8),
            self.assertRaises((TimeoutError, socket.timeout)),
        ):
            breadth.pull(self.coordinate)
        self.assertEqual(
            [host for host, _, _ in self.requests],
            ["raw.githubusercontent.com", "api.github.com"],
        )
        self.assertFalse((self.root / "source.md").exists())


if __name__ == "__main__":
    unittest.main()
