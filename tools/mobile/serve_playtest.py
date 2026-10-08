"""Serve a local Web export over HTTPS on the same development network only.

Run: python tools/mobile/serve_playtest.py --directory build/mobile-web
Requires cryptography (python -m pip install cryptography). Stop with Ctrl+C.
Development/playtest only: no deployment, export modification or save handling.
"""
import argparse
from datetime import datetime, timedelta, timezone
from functools import partial
import hashlib
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
import ipaddress
import os
from pathlib import Path
import socket
import ssl


CERTIFICATE_URL = "/__playtest__/certificate.cer"


def lan_address(host):
    """Resolve an explicit bind address, or discover the default IPv4 interface."""
    if host != "0.0.0.0":
        return socket.gethostbyname(host)
    try:
        with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as probe:
            # UDP connect selects an interface; no packet is sent.
            probe.connect(("8.8.8.8", 80))
            address = probe.getsockname()[0]
            if not ipaddress.ip_address(address).is_loopback:
                return address
    except OSError:
        pass
    for address in socket.gethostbyname_ex(socket.gethostname())[2]:
        if not ipaddress.ip_address(address).is_loopback:
            return address
    raise ValueError("No LAN IPv4 address found. Use --host <PC's Wi-Fi IPv4 address>.")


def certificate_directory():
    base = Path(os.environ.get("LOCALAPPDATA", str(Path.home() / ".cache")))
    return base / "FishingGame" / "mobile-playtest-tls"


def ensure_certificate(address, cache):
    """Reuse a matching, unexpired certificate/key, or create a local dev pair."""
    try:
        from cryptography import x509
        from cryptography.hazmat.primitives import hashes, serialization
        from cryptography.hazmat.primitives.asymmetric import rsa
        from cryptography.x509.oid import ExtendedKeyUsageOID, NameOID
    except ImportError as exc:
        raise ValueError("Certificate generation requires cryptography. Run this Python "
                         "interpreter with -m pip install cryptography first.") from exc
    cache = Path(cache).resolve()
    cache.mkdir(parents=True, exist_ok=True)
    stem = str(ipaddress.ip_address(address)).replace(":", "_")
    cert_path, key_path = cache / f"{stem}.pem", cache / f"{stem}.key"
    now = datetime.now(timezone.utc)
    try:
        certificate = x509.load_pem_x509_certificate(cert_path.read_bytes())
        key = serialization.load_pem_private_key(key_path.read_bytes(), password=None)
        sans = certificate.extensions.get_extension_for_class(x509.SubjectAlternativeName).value
        if (certificate.not_valid_before_utc <= now
                and certificate.not_valid_after_utc > now + timedelta(days=1)
                and ipaddress.ip_address(address) in sans.get_values_for_type(x509.IPAddress)
                and certificate.public_key().public_numbers() == key.public_key().public_numbers()):
            return cert_path, key_path
    except (OSError, ValueError, x509.ExtensionNotFound):
        pass
    key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
    name = x509.Name([x509.NameAttribute(NameOID.COMMON_NAME, "FishingGame LAN Playtest (development only)")])
    certificate = (x509.CertificateBuilder()
                   .subject_name(name).issuer_name(name).public_key(key.public_key())
                   .serial_number(x509.random_serial_number())
                   .not_valid_before(now - timedelta(minutes=5))
                   .not_valid_after(now + timedelta(days=365))
                   .add_extension(x509.SubjectAlternativeName([
                       x509.IPAddress(ipaddress.ip_address(address)),
                       x509.IPAddress(ipaddress.ip_address("127.0.0.1")),
                       x509.DNSName("localhost")]), critical=False)
                   # Self-signed trust anchor, so iOS can explicitly trust this dev cert.
                   .add_extension(x509.BasicConstraints(ca=True, path_length=0), critical=True)
                   .add_extension(x509.KeyUsage(digital_signature=True, content_commitment=False,
                       key_encipherment=True, data_encipherment=False, key_agreement=False,
                       key_cert_sign=True, crl_sign=True, encipher_only=False, decipher_only=False), critical=True)
                   .add_extension(x509.ExtendedKeyUsage([ExtendedKeyUsageOID.SERVER_AUTH]), critical=False)
                   .sign(key, hashes.SHA256()))
    key_path.write_bytes(key.private_bytes(serialization.Encoding.PEM,
                         serialization.PrivateFormat.PKCS8, serialization.NoEncryption()))
    key_path.chmod(0o600)
    cert_path.write_bytes(certificate.public_bytes(serialization.Encoding.PEM))
    return cert_path, key_path


class PlaytestHandler(SimpleHTTPRequestHandler):
    extensions_map = {**SimpleHTTPRequestHandler.extensions_map,
                      ".wasm": "application/wasm",
                      ".pck": "application/octet-stream"}

    def __init__(self, *args, public_certificate=b"", **kwargs):
        self.public_certificate = public_certificate
        super().__init__(*args, **kwargs)

    def send_head(self):
        if self.path.split("?", 1)[0] == CERTIFICATE_URL:
            from io import BytesIO
            self.send_response(200)
            self.send_header("Content-Type", "application/x-x509-ca-cert")
            self.send_header("Content-Disposition", 'attachment; filename="FishingGame-LAN-Playtest.cer"')
            self.send_header("Content-Length", str(len(self.public_certificate)))
            self.end_headers()
            return BytesIO(self.public_certificate)
        return super().send_head()

    def end_headers(self):
        self.send_header("Cache-Control", "no-store")
        super().end_headers()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--directory", default="build/mobile-web")
    parser.add_argument("--host", default="0.0.0.0")
    parser.add_argument("--port", type=int, default=8060)
    args = parser.parse_args()
    directory = Path(args.directory).resolve()
    if not (directory / "index.html").is_file():
        parser.error(f"No exported index.html in {directory}. Export the Web preset first.")
    try:
        address = lan_address(args.host)
        cache = certificate_directory().resolve()
        if cache == directory or directory in cache.parents:
            parser.error("TLS cache must be outside the export directory; select a narrower --directory.")
        cert_path, key_path = ensure_certificate(address, cache)
        context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        context.minimum_version = ssl.TLSVersion.TLSv1_2
        context.load_cert_chain(cert_path, key_path)
        public_certificate = ssl.PEM_cert_to_DER_cert(cert_path.read_text(encoding="ascii"))
    except (OSError, ValueError, ssl.SSLError) as exc:
        parser.error(str(exc))
    handler = partial(PlaytestHandler, directory=str(directory), public_certificate=public_certificate)
    with ThreadingHTTPServer((args.host, args.port), handler) as server:
        server.socket = context.wrap_socket(server.socket, server_side=True)
        url = f"https://{address}:{server.server_port}"
        print(f"DEVELOPMENT / LAN PLAYTEST ONLY. Serving {directory}", flush=True)
        print(f"Bound to {args.host}:{server.server_port}. iPhone (same Wi-Fi): {url}/", flush=True)
        print(f"Reused/generated certificate: {cert_path}\nPrivate key stays outside the export: {key_path}")
        print(f"Certificate SHA-256: {hashlib.sha256(public_certificate).hexdigest()}")
        print("Safari first visit: Show Details -> visit this website / Continue, then confirm "
              "(wording varies; may require your passcode). Only accept your own PC's address.")
        print("A warning bypass may NOT satisfy Godot's secure-context check. If it persists, "
              "install and fully trust this development certificate once:")
        print(f"  Open {url}{CERTIFICATE_URL} in Safari to download the PUBLIC certificate.")
        print("  Settings -> General -> VPN & Device Management -> install the downloaded profile;\n"
              "  Settings -> General -> About -> Certificate Trust Settings -> enable full trust\n"
              "  for FishingGame LAN Playtest (development only). Reopen Safari and reload.")
        print("Repeat trust setup if the LAN IP changes or the certificate renews. "
              "Remove the profile when finished playtesting. Ctrl+C stops.", flush=True)
        try:
            server.serve_forever()
        except KeyboardInterrupt:
            pass


if __name__ == "__main__":
    main()
