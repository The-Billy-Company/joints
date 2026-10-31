"""Offline controls for exact GET-only draft candidate transport."""
from pathlib import Path
import contextlib
import copy
import hashlib
import io
import json
import os
import re
import subprocess
import sys
import tempfile
import textwrap
import unittest
from unittest.mock import patch
import urllib.error

import rust_candidate_download as candidate

PAYLOAD = b"qualified candidate archive\x00"
TOKEN = "offline_secret"
SELECTION = {"release_id": 123, "asset_id": 456, "target_commit": "a" * 40,
             "asset_name": "joints-macos-arm64.tar.gz", "sha256": hashlib.sha256(PAYLOAD).hexdigest()}
ASSET = {"id": 456, "name": SELECTION["asset_name"], "url": candidate.API + "/releases/assets/456",
         "state": "uploaded", "digest": "sha256:" + SELECTION["sha256"], "size": len(PAYLOAD),
         "created_at": "2026-10-22T00:00:00Z", "updated_at": "2026-10-22T00:00:00Z"}
RELEASE = {"id": 123, "url": candidate.API + "/releases/123",
           "assets_url": candidate.API + "/releases/123/assets", "draft": True,
           "published_at": None, "target_commitish": SELECTION["target_commit"],
           "tag_name": "private-candidate", "assets": [ASSET]}
STORAGE = "https://release-assets.githubusercontent.com/exact?signature=private"


class Response(io.BytesIO):
    def __init__(self, data, url, status=200, headers=None):
        super().__init__(data)
        self.url, self.status, self.headers = url, status, headers or {}

    def geturl(self):
        return self.url


class Server:
    def __init__(self, release=None, asset=None, payload=PAYLOAD, redirect=False, after=None):
        self.release = copy.deepcopy(RELEASE if release is None else release)
        self.asset = copy.deepcopy(ASSET if asset is None else asset)
        self.payload, self.redirect, self.after = payload, redirect, after
        self.calls, self.downloaded = [], False

    def open(self, request, timeout):
        url, headers = request.full_url, dict(request.header_items())
        self.calls.append((url, headers, request.get_method()))
        if url.startswith(candidate.API):
            if headers.get("Authorization") != "Bearer " + TOKEN:
                raise AssertionError("missing fixed API token")
        elif "Authorization" in headers:
            raise AssertionError("token reached storage")
        if url == RELEASE["url"]:
            value = self.after if self.downloaded and self.after is not None else self.release
            return Response(json.dumps(value).encode(), url)
        if url == ASSET["url"] and headers["Accept"] != "application/octet-stream":
            return Response(json.dumps(self.asset).encode(), url)
        if url == ASSET["url"] and self.redirect:
            raise urllib.error.HTTPError(url, 302, "redirect", {"Location": STORAGE}, io.BytesIO())
        if url in (ASSET["url"], STORAGE):
            self.downloaded = True
            return Response(self.payload, url, headers={"Content-Length": str(len(self.payload))})
        raise AssertionError("unexpected request")


class CandidateDownload(unittest.TestCase):
    def run_download(self, server, selection=None, token=TOKEN):
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        home = Path(directory.name)
        out, receipt = home / "candidate.tar.gz", home / "receipt.json"
        with patch.object(candidate.urllib.request, "build_opener") as builder:
            builder.return_value.open.side_effect = server.open
            report = candidate.download(selection or SELECTION, out, receipt, token)
        return out, receipt, report

    def refused(self, server, message, selection=None, token=TOKEN):
        with tempfile.TemporaryDirectory() as directory:
            out, receipt = (Path(directory) / name for name in ("candidate.tar.gz", "receipt.json"))
            with patch.object(candidate.urllib.request, "build_opener") as builder:
                builder.return_value.open.side_effect = server.open
                with self.assertRaisesRegex(candidate.DownloadError, message):
                    candidate.download(selection or SELECTION, out, receipt, token)
            self.assertFalse(out.exists())

            if receipt.exists():
                report = json.loads(receipt.read_bytes())
                self.assertEqual(report["status"], "failed")
                self.assertFalse(report["pass"])
                self.assertNotIn(TOKEN, receipt.read_text())
            self.assertFalse(list(Path(directory).glob(".candidate-*")))

    def test_direct_api_download_and_exact_receipt(self):
        server = Server()
        out, receipt, report = self.run_download(server)
        self.assertEqual(out.read_bytes(), PAYLOAD)
        self.assertEqual(report, json.loads(receipt.read_bytes()))
        self.assertEqual(report["before"], report["after"])
        self.assertTrue(report["pass"])
        self.assertEqual(len(server.calls), 5)
        self.assertEqual({method for _, _, method in server.calls}, {"GET"})
        self.assertNotIn(TOKEN, receipt.read_text())

    def test_redirect_is_a_new_unauthenticated_storage_request(self):
        server = Server(redirect=True)
        out, _, _ = self.run_download(server)
        self.assertEqual(out.read_bytes(), PAYLOAD)
        storage = next(headers for url, headers, _ in server.calls if url == STORAGE)
        self.assertNotIn("Authorization", storage)
        self.assertNotIn("X-github-api-version", storage)
        self.assertEqual({method for _, _, method in server.calls}, {"GET"})

    def test_missing_token_refuses_before_network(self):
        server = Server()
        self.refused(server, "GH_TOKEN is required", token="")
        self.assertEqual(server.calls, [])

    def test_wrong_release_asset_commit_draft_or_inventory_refuses(self):
        for change, message in [({"id": 124}, "release identity"), ({"draft": False}, "unpublished draft"),
                                ({"published_at": "2026-10-22"}, "unpublished draft"),
                                ({"target_commitish": "main"}, "target commit"),
                                ({"assets": []}, "unique member"),
                                ({"assets": [ASSET, ASSET]}, "unique member")]:
            with self.subTest(change=change):
                self.refused(Server(release=RELEASE | change), message)
        for change in ({"id": 457}, {"name": "other.tar.gz"}, {"state": "new"},
                       {"digest": "sha256:" + "b" * 64}, {"url": "https://other.invalid/asset"}):
            with self.subTest(asset=change):
                self.refused(Server(asset=ASSET | change), "asset identity")

    def test_wrong_payload_and_lengths_refuse_without_publishing(self):
        self.refused(Server(payload=b"x" * len(PAYLOAD)), "SHA256 differs")
        self.refused(Server(payload=PAYLOAD[:-1]), "content length differs")
        for size in (0, True, candidate.LIMIT + 1):
            with self.subTest(size=size):
                release = copy.deepcopy(RELEASE)
                release["assets"][0]["size"] = size
                self.refused(Server(release=release), "size is unsupported")

    def test_metadata_changed_after_transfer_refuses(self):
        self.refused(Server(after=RELEASE | {"tag_name": "changed"}), "metadata changed during download")
        self.refused(Server(after=RELEASE | {"draft": False}), "unpublished draft")

    def test_metadata_redirect_refuses_without_following(self):
        with patch.object(candidate, "response", return_value=Response(b"", RELEASE["url"], 302)):
            with self.assertRaisesRegex(candidate.DownloadError, "metadata response"):
                candidate.snapshot(SELECTION, TOKEN)

    def test_storage_redirects_reject_http_credentials_ports_and_other_hosts(self):
        for url in ("http://release-assets.githubusercontent.com/a", "https://user:pass@release-assets.githubusercontent.com/a",
                    "https://release-assets.githubusercontent.com:444/a", "https://api.github.com/a",
                    "https://attacker.invalid/a", STORAGE + "#fragment", "//release-assets.githubusercontent.com/a"):
            with self.subTest(url=url), self.assertRaises(candidate.DownloadError):
                candidate.storage_location(url)

    def test_selection_validation_and_existing_output_refuse(self):
        for change in ({"release_id": True}, {"asset_id": -1}, {"target_commit": "main"},
                       {"sha256": "A" * 64}, {"asset_name": "../candidate.tar.gz"}):
            with self.subTest(change=change):
                self.refused(Server(), ".", selection=SELECTION | change)
        with tempfile.TemporaryDirectory() as directory:
            out, receipt = Path(directory) / "existing", Path(directory) / "receipt"
            out.write_bytes(b"previous")
            with self.assertRaisesRegex(candidate.DownloadError, "already exists"):
                candidate.download(SELECTION, out, receipt, TOKEN)
            self.assertEqual(out.read_bytes(), b"previous")
            self.assertFalse(receipt.exists())

    def test_cli_smoke_without_network(self):
        with tempfile.TemporaryDirectory() as directory:
            out, receipt = Path(directory) / "candidate", Path(directory) / "receipt.json"
            argv = ["--release-id", "123", "--asset-id", "456", "--target-commit", SELECTION["target_commit"],
                    "--asset-name", SELECTION["asset_name"], "--sha256", SELECTION["sha256"],
                    "--out", str(out), "--receipt", str(receipt)]
            with patch.dict(os.environ, {"GH_TOKEN": TOKEN}), \
                    patch.object(candidate.urllib.request, "build_opener") as builder, \
                    contextlib.redirect_stdout(io.StringIO()) as output:
                builder.return_value.open.side_effect = Server(redirect=True).open
                self.assertEqual(candidate.main(argv), 0)
            self.assertEqual(json.loads(output.getvalue())["output"]["sha256"], SELECTION["sha256"])
            self.assertTrue(json.loads(receipt.read_bytes())["pass"])

    def test_metadata_only_probe_has_no_binary_request_or_installed_claim(self):
        server = Server()
        with tempfile.TemporaryDirectory() as directory:
            receipt = Path(directory) / "receipt.json"
            with patch.object(candidate.urllib.request, "build_opener") as builder:
                builder.return_value.open.side_effect = server.open
                report = candidate.download(SELECTION, None, receipt, TOKEN, metadata_only=True)
            self.assertEqual(len(server.calls), 4)
            self.assertNotIn("output", report)
            self.assertEqual(report["mode"], "metadata-only")
            self.assertTrue(report["transport_only"])
            self.assertFalse(report["installed_qualified"])
            self.assertFalse(report["cutover_authorized"])
            self.assertEqual(list(Path(directory).iterdir()), [receipt])

    def test_transport_exception_never_retains_secret_or_signed_url(self):
        with tempfile.TemporaryDirectory() as directory:
            out, receipt = Path(directory) / "candidate", Path(directory) / "receipt.json"
            with patch.object(candidate, "snapshot", return_value={"release": {}, "asset": ASSET}), \
                    patch.object(candidate, "transfer", side_effect=OSError(STORAGE + TOKEN)):
                with self.assertRaises(candidate.DownloadError) as error:
                    candidate.download(SELECTION, out, receipt, TOKEN)
            for text in (str(error.exception), receipt.read_text()):
                self.assertNotIn(TOKEN, text)
                self.assertNotIn(STORAGE, text)
            self.assertFalse(out.exists())


class CandidateWorkflow(unittest.TestCase):
    root = Path(__file__).resolve().parents[1]

    @staticmethod
    def step(body, name):
        start = body.index("      - name: " + name)
        end = body.find("\n      - ", start + 1)
        return body[start:] if end == -1 else body[start:end]

    def test_dispatch_has_exact_selection_inputs_and_read_only_permissions(self):
        workflow = (self.root / ".github/workflows/rust-candidate.yml").read_text()
        inputs = workflow.split("    inputs:\n", 1)[1].split("\npermissions:", 1)[0]
        self.assertEqual(set(re.findall(r"^      ([a-z][a-z0-9_]+):", inputs, re.M)),
                         {"helper_ref", "linux_url", "linux_sha256", "macos_url", "macos_sha256",
                          "candidate_commit", "release_id", "linux_asset_id", "macos_asset_id", "transport_only"})
        self.assertEqual(re.findall(r"^permissions:\n((?:  [^\n]+\n)+)", workflow, re.M), ["  contents: read\n"])
        installed, transport = workflow.split("  transport:\n", 1)
        self.assertIn("    permissions:\n      contents: read\n      actions: read\n", installed)
        self.assertIn("    permissions:\n      contents: write\n", transport)
        self.assertEqual(workflow.count("contents: write"), 1)
        self.assertNotIn("GH_TOKEN", installed)
        self.assertNotIn("rust_candidate_download.py", installed)
        self.assertIn("ref: ${{ inputs.helper_ref }}", workflow)
        self.assertIn("CANDIDATE_COMMIT: ${{ inputs.candidate_commit }}", workflow)
        self.assertIn("--target-commit \"$CANDIDATE_COMMIT\"", workflow)

    def test_opaque_transfer_is_pinned_isolated_and_never_executes_candidate(self):
        workflow = (self.root / ".github/workflows/rust-candidate.yml").read_text()
        helper_hash = candidate.sha(candidate.__file__)
        installed, transport = workflow.split("  transport:\n", 1)
        pin = self.step(transport, "Pin the opaque transport helper")
        transfer = self.step(transport, "Transfer only the exact opaque unpublished draft asset")
        self.assertIn("expected = '" + helper_hash + "'", pin)
        self.assertLess(transport.index(pin), transport.index(transfer))
        self.assertIn("python3 -I - <<'PY'", pin)
        self.assertIn("python -I -B tool/rust_candidate_download.py", transfer)
        self.assertNotIn("--metadata-only", transfer)
        self.assertIn("GH_TOKEN: ${{ github.token }}", transfer)
        self.assertEqual(transport.count("GH_TOKEN:"), 1)
        for flag in ("--release-id", "--asset-id", "--target-commit", "--asset-name", "--sha256", "--out", "--receipt"):
            self.assertIn(flag, transfer)
        for forbidden in ("rustup ", "cargo ", "rustc ", "rust_delivery.py", "installed-check", "tar -", "unzip "):
            self.assertNotIn(forbidden, transport)
        self.assertIn("name: candidate-transport-${{ matrix.target }}", transport)
        self.assertIn("path: |\n            candidate.tar.gz\n            candidate-transport.json\n", transport)
        self.assertIn("overwrite: false", transport)
        fetch = self.step(installed, "Fetch the same-run immutable candidate transport artifact")
        self.assertIn("actions/download-artifact@d3f86a106a0bac45b974a628896c90dbdf5c8093", fetch)
        self.assertIn("name: candidate-transport-${{ matrix.target }}", fetch)
        for forbidden in ("run-id:", "repository:", "github-token:"):
            self.assertNotIn(forbidden, fetch)
        check = self.step(installed, "Independently check the transported candidate identity and bytes")
        self.assertLess(installed.index(fetch), installed.index(check))
        self.assertLess(installed.index(check), installed.index("name: Make both required Rust toolchains available"))

    def test_job_conditions_preserve_public_draft_failure_and_probe_routes(self):
        workflow = (self.root / ".github/workflows/rust-candidate.yml").read_text()
        installed, transport = workflow.split("  transport:\n", 1)
        condition = re.search(r"^    if: \$\{\{ (.+) \}\}$", installed, re.M)[1]
        for release, probe, result, cancelled, expected in (
                ("", False, "skipped", False, True), ("123", False, "success", False, True),
                ("123", False, "failure", False, False), ("123", False, "skipped", False, False),
                ("123", True, "success", False, False), ("", True, "failure", False, False),
                ("123", False, "success", True, False)):
            expression = condition.replace("always()", "True").replace("cancelled()", repr(cancelled))
            expression = expression.replace("inputs.transport_only", repr(probe)).replace("inputs.release_id", repr(release))
            expression = expression.replace("needs.transport.result", repr(result)).replace("&&", " and ").replace("||", " or ").replace("!", "not ")
            with self.subTest(release=release, probe=probe, result=result, cancelled=cancelled):
                self.assertEqual(eval(expression, {"__builtins__": {}}), expected)
        self.assertIn("if: inputs.release_id != '' || inputs.transport_only", transport)
        self.assertIn("fromJSON(inputs.transport_only &&", transport)
        self.assertIn("'positive draft ID required'", transport)

    def test_anonymous_https_mode_and_source_ci_controls_remain(self):
        workflow = (self.root / ".github/workflows/rust-candidate.yml").read_text()
        fallback = self.step(workflow, "Verify actual host floor and download pinned local candidate")
        self.assertIn("if not os.environ['CANDIDATE_RELEASE_ID']:", fallback)
        self.assertIn("urllib.request.urlopen(url)", fallback)
        self.assertIn("HTTPS redirect required", fallback)
        self.assertNotIn("GH_TOKEN", fallback)
        source_ci = (self.root / ".github/workflows/rust-engine.yml").read_text()
        self.assertIn("python -B -m unittest discover -s tool -p test_rust_candidate_download.py", source_ci)

    def test_installed_receipt_verifier_accepts_exact_files_and_refuses_changes(self):
        workflow = (self.root / ".github/workflows/rust-candidate.yml").read_text()
        step = self.step(workflow, "Independently check the transported candidate identity and bytes")
        script = textwrap.dedent(step.split("<<'PY'\n", 1)[1].rsplit("\n          PY", 1)[0])
        env = {"CANDIDATE_COMMIT": SELECTION["target_commit"], "CANDIDATE_RELEASE_ID": "123",
               "CANDIDATE_ASSET_ID": "456", "CANDIDATE_ASSET_NAME": SELECTION["asset_name"],
               "CANDIDATE_SHA256": SELECTION["sha256"]}
        receipt = {"schema": 1, "status": "complete", "pass": True, "repository": candidate.REPOSITORY,
                   "method": "GET", "producer_sha256": candidate.sha(candidate.__file__), "mode": "download-only",
                   "transport_only": True, "installed_qualified": False, "cutover_authorized": False,
                   "selection": SELECTION, "before": {"draft": True}, "after": {"draft": True},
                   "output": {"sha256": SELECTION["sha256"], "bytes": len(PAYLOAD)},
                   "download": {"sha256": SELECTION["sha256"], "bytes": len(PAYLOAD)}}
        for change in ("none", "payload", "selection", "receipt", "symlink", "extra", "metadata"):
            with self.subTest(change=change), tempfile.TemporaryDirectory() as directory:
                home = Path(directory); transfer = home / "candidate-transfer"; transfer.mkdir()
                archive = transfer / "candidate.tar.gz"; archive.write_bytes(PAYLOAD)
                value = copy.deepcopy(receipt)
                if change == "payload": archive.write_bytes(b"changed")
                elif change == "selection": value["selection"]["asset_id"] = 457
                elif change == "receipt": value["pass"] = False
                elif change == "metadata": value["after"] = {"draft": False}
                elif change == "extra": (transfer / "extra").write_bytes(b"unexpected")
                elif change == "symlink":
                    archive.rename(home / "elsewhere"); archive.symlink_to(home / "elsewhere")
                (transfer / "candidate-transport.json").write_text(json.dumps(value))
                previous = Path.cwd()
                try:
                    os.chdir(home)
                    with patch.dict(os.environ, env), contextlib.redirect_stdout(io.StringIO()):
                        if change == "none": exec(compile(script, "installed-receipt-verifier", "exec"), {})
                        else:
                            with self.assertRaises(AssertionError):
                                exec(compile(script, "installed-receipt-verifier", "exec"), {})
                finally:
                    os.chdir(previous)
                self.assertEqual((home / "candidate.tar.gz").exists(), change == "none")

    def test_real_isolated_cli_refuses_missing_token_without_shadow_import_or_network(self):
        with tempfile.TemporaryDirectory() as directory:
            home = Path(directory); receipt = home / "receipt.json"
            (home / "json.py").write_text("raise RuntimeError('hostile shadow import')\n")
            argv = [sys.executable, "-I", "-B", str(Path(candidate.__file__).resolve()),
                    "--release-id", "123", "--asset-id", "456", "--target-commit", SELECTION["target_commit"],
                    "--asset-name", SELECTION["asset_name"], "--sha256", SELECTION["sha256"],
                    "--out", str(home / "candidate.tar.gz"), "--receipt", str(receipt)]
            result = subprocess.run(argv, cwd=home, env=os.environ | {"GH_TOKEN": "", "PYTHONPATH": str(home)},
                                    capture_output=True, text=True, timeout=10)
            self.assertEqual(result.returncode, 1, result.stderr)
            self.assertNotIn("hostile shadow import", result.stderr)
            value = json.loads(receipt.read_bytes())
            self.assertEqual(value["status"], "failed")
            self.assertEqual(value["error"], "GH_TOKEN is required")
            self.assertFalse((home / "candidate.tar.gz").exists())


if __name__ == "__main__":
    unittest.main()
