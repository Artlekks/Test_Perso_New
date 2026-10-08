"""Local TLS smoke tests; no Godot export or phone required."""
import hashlib
import mimetypes
from functools import partial
from http.client import HTTPSConnection
from http.server import ThreadingHTTPServer
from pathlib import Path
import ssl
import tempfile
import threading
import unittest

from cryptography import x509
from cryptography.hazmat.primitives import serialization

import serve_playtest as helper


class PlaytestTLSTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.cache = self.root / "tls"

    def test_certificate_reuse_and_san(self):
        cert, key = helper.ensure_certificate("192.168.1.10", self.cache)
        original = cert.read_bytes(), key.read_bytes()
        self.assertEqual((cert, key), helper.ensure_certificate("192.168.1.10", self.cache))
        self.assertEqual(original, (cert.read_bytes(), key.read_bytes()))
        parsed = x509.load_pem_x509_certificate(cert.read_bytes())
        san = parsed.extensions.get_extension_for_class(x509.SubjectAlternativeName).value
        self.assertIn("192.168.1.10", [str(ip) for ip in san.get_values_for_type(x509.IPAddress)])
        self.assertTrue(parsed.extensions.get_extension_for_class(x509.BasicConstraints).value.ca)

    def test_different_lan_ip_has_matching_separate_certificate(self):
        first, _ = helper.ensure_certificate("192.168.1.10", self.cache)
        second, _ = helper.ensure_certificate("192.168.1.11", self.cache)
        self.assertNotEqual(first, second)
        self.assertNotEqual(first.read_bytes(), second.read_bytes())

    def test_missing_or_mismatched_key_is_repaired(self):
        cert, key = helper.ensure_certificate("127.0.0.1", self.cache)
        key.unlink()
        helper.ensure_certificate("127.0.0.1", self.cache)
        _, other_key = helper.ensure_certificate("192.168.1.10", self.cache)
        key.write_bytes(other_key.read_bytes())
        helper.ensure_certificate("127.0.0.1", self.cache)
        certificate = x509.load_pem_x509_certificate(cert.read_bytes())
        private_key = serialization.load_pem_private_key(key.read_bytes(), password=None)
        self.assertEqual(certificate.public_key().public_numbers(), private_key.public_key().public_numbers())

    def test_https_export_public_cert_headers_and_no_export_changes(self):
        export = self.root / "export"
        export.mkdir()
        (export / "index.html").write_bytes(b"<html>playtest</html>")
        (export / "index.wasm").write_bytes(b"wasm-test")
        (export / "index.js").write_bytes(b"js-test")
        (export / "index.pck").write_bytes(b"pck-test")
        before = {p.name: hashlib.sha256(p.read_bytes()).digest() for p in export.iterdir()}
        cert, key = helper.ensure_certificate("127.0.0.1", self.cache)
        public = ssl.PEM_cert_to_DER_cert(cert.read_text())
        context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        context.minimum_version = ssl.TLSVersion.TLSv1_2
        context.load_cert_chain(cert, key)
        handler = partial(helper.PlaytestHandler, directory=str(export), public_certificate=public)
        server = ThreadingHTTPServer(("127.0.0.1", 0), handler)
        server.socket = context.wrap_socket(server.socket, server_side=True)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        try:
            client = HTTPSConnection("127.0.0.1", server.server_port,
                                     context=ssl.create_default_context(cafile=str(cert)), timeout=5)
            try:
                for path, expected, mime in [
                    ("/", b"<html>playtest</html>", "text/html"),
                    ("/index.wasm", b"wasm-test", "application/wasm"),
                    ("/index.js", b"js-test", mimetypes.guess_type("index.js")[0]),
                    ("/index.pck", b"pck-test", "application/octet-stream"),
                    (helper.CERTIFICATE_URL, public, "application/x-x509-ca-cert"),
                ]:
                    client.request("GET", path)
                    response = client.getresponse()
                    self.assertEqual(response.status, 200)
                    self.assertEqual(response.read(), expected)
                    self.assertEqual(response.getheader("Content-Type"), mime)
                    self.assertEqual(response.getheader("Cache-Control"), "no-store, no-cache, max-age=0, must-revalidate")
                    self.assertEqual(response.getheader("Pragma"), "no-cache")
                    self.assertEqual(response.getheader("Expires"), "0")
                self.assertEqual(before, {p.name: hashlib.sha256(p.read_bytes()).digest() for p in export.iterdir()})
                # Simulate rebuilding while the SAME HTTPS listener stays up.
                for name in ("index.html", "index.js", "index.pck", "index.wasm"):
                    updated = b"new-build-" + name.encode()
                    (export / name).write_bytes(updated)
                    client.request("GET", "/" + name, headers={
                        "If-Modified-Since": "Wed, 01 Jan 2099 00:00:00 GMT",
                        "If-None-Match": '"old-build"',
                    })
                    response = client.getresponse()
                    self.assertEqual(response.status, 200)
                    self.assertEqual(response.read(), updated)
                before = {p.name: hashlib.sha256(p.read_bytes()).digest() for p in export.iterdir()}
                client.request("GET", "/tls/127.0.0.1.key")
                response = client.getresponse()
                self.assertEqual(response.status, 404)
                response.read()
            finally:
                client.close()
        finally:
            server.shutdown()
            thread.join(timeout=5)
            server.server_close()
        self.assertEqual(before, {p.name: hashlib.sha256(p.read_bytes()).digest() for p in export.iterdir()})

    def test_explicit_bind_address_is_used(self):
        self.assertEqual(helper.lan_address("127.0.0.1"), "127.0.0.1")


if __name__ == "__main__":
    unittest.main()
