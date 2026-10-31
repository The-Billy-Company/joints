"""Pure source-bootstrap controls; every network/process call is mocked."""
import hashlib
import io
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile
import unittest
from unittest.mock import patch

import rust_python_bootstrap as bootstrap


class PythonBootstrap(unittest.TestCase):
    def test_shared_bootstrap_keeps_the_proven_recipe_and_retained_commands(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            workflow = bootstrap.ROOT / ".github/workflows/rust-engine.yml"
            evidence, work = root / "evidence", root / "work"
            body = b"authored official-source substitute; no download or build"
            source_hash = hashlib.sha256(body).hexdigest()
            response = io.BytesIO(body)
            response.geturl = lambda: bootstrap.SOURCE_URL
            calls = []

            def run(argv, *, cwd, env, capture_output):
                self.assertTrue(capture_output)
                calls.append((argv, cwd, dict(env)))
                answer = b""
                if argv[0] == "/usr/bin/xcrun":
                    answer = b"/authored/MacOSX14.5.sdk\n"
                elif argv[0] == "brew":
                    answer = str(root / "openssl").encode() + b"\n"
                elif argv[:2] == ["/usr/bin/make", "install"]:
                    python = work / "installed/bin/python3.12"
                    python.parent.mkdir(parents=True)
                    python.write_bytes(b"authored built interpreter")
                elif argv[0].endswith("/python3.12"):
                    answer = b"3.12.15 authored\n"
                return subprocess.CompletedProcess(argv, 0, answer, b"authored log\n")

            with patch.object(bootstrap.platform, "system", return_value="Darwin"), \
                 patch.object(bootstrap.platform, "machine", return_value="arm64"), \
                 patch.object(bootstrap.platform, "mac_ver", return_value=("14.8.9", (), "")), \
                 patch.object(bootstrap, "SOURCE_SHA256", source_hash), \
                 patch.object(bootstrap.urllib.request, "urlopen", return_value=response) as download, \
                 patch.object(bootstrap.subprocess, "run", side_effect=run), \
                 patch.dict(os.environ, GITHUB_PATH=str(root / "github-path"), GITHUB_ENV=str(root / "github-env")):
                bootstrap.build(workflow, evidence, work, "AUTHORED_BOOTSTRAP")
                value = bootstrap.checked_receipt(evidence / "receipt.json", work / "installed/bin/python3.12", workflow)["receipt"]
            download.assert_called_once_with(bootstrap.SOURCE_URL)
            self.assertTrue(value["pass"])
            self.assertEqual(value["bootstrap_helper_sha256"], bootstrap.digest(bootstrap.__file__))
            self.assertEqual([row["label"] for row in value["commands"]], list(bootstrap.BUILD_STEPS))
            self.assertEqual(calls[0][0], ["/usr/bin/xcrun", "--sdk", "macosx14.5", "--show-sdk-path"])
            self.assertEqual(calls[1][0], ["brew", "--prefix", "openssl@3"])
            self.assertEqual(calls[2][0], ["/usr/bin/clang", "--version"])
            self.assertEqual(calls[3][0], ["/usr/bin/tar", "-xzf", str(work / "Python-3.12.15.tgz"), "-C", str(work)])
            self.assertEqual(calls[4][0], [str(work / "Python-3.12.15/configure"), "--prefix=" + str(work / "installed"),
                                         "--with-openssl=" + str(root / "openssl"), "--with-openssl-rpath=auto", "--with-ensurepip=no"])
            self.assertEqual(calls[5][0], ["/usr/bin/make", "-j2"])
            self.assertEqual(calls[6][0], ["/usr/bin/make", "install"])
            self.assertEqual(calls[7][0][1:3], ["-B", "-c"])
            self.assertIn("import ctypes, ssl, sys, zlib", calls[7][0][3])
            for _, _, env in calls:
                self.assertEqual(env["DEVELOPER_DIR"], "/Applications/Xcode_15.4.app/Contents/Developer")
                self.assertEqual(env["MACOSX_DEPLOYMENT_TARGET"], "14.0")
                self.assertEqual(env["CC"], "/usr/bin/clang")
            self.assertEqual(calls[-1][2]["SDKROOT"], "/authored/MacOSX14.5.sdk")
            self.assertEqual((root / "github-path").read_text(), str(work / "installed/bin") + "\n")
            self.assertEqual((root / "github-env").read_text(), "AUTHORED_BOOTSTRAP=" + str(evidence / "receipt.json") + "\n")

    def test_newer_or_wrong_host_refuses_before_network_or_process(self):
        with patch.object(bootstrap.urllib.request, "urlopen") as download, \
             patch.object(bootstrap.subprocess, "run") as run:
            for system, machine, version in [("Darwin", "arm64", "26.6"), ("Darwin", "x86_64", "14.8"), ("Linux", "arm64", "14.8")]:
                with self.subTest(system=system, machine=machine, version=version), \
                     patch.object(bootstrap.platform, "system", return_value=system), \
                     patch.object(bootstrap.platform, "machine", return_value=machine), \
                     patch.object(bootstrap.platform, "mac_ver", return_value=(version, (), "")), \
                     self.assertRaisesRegex(ValueError, "actual macOS 14"):
                    bootstrap.build(Path("unused"), Path("unused"), Path("unused"), "UNUSED")
            download.assert_not_called()
            run.assert_not_called()

    def test_installed_workflow_pins_bootstrap_before_executing_it(self):
        workflow = (bootstrap.ROOT / ".github/workflows/rust-candidate.yml").read_text()
        validate = workflow.index("name: Validate explicit helper and candidate inputs")
        checkout = workflow.index("uses: actions/checkout@")
        pin = workflow.index("name: Pin the shared Python source bootstrap")
        build = workflow.index("name: Build the exact official Python on macOS 14")
        check = workflow.index("name: Check the retained Python source bootstrap")
        verify = workflow.index("name: Execute installed candidate contracts")
        self.assertTrue(validate < checkout < pin < build < check < verify)
        self.assertIn("python3 - <<'PY'", workflow[validate:checkout])
        pin_step = workflow[pin:build]
        match = re.search(r"expected = '([0-9a-f]{64})'", pin_step)
        self.assertIsNotNone(match)
        self.assertEqual(match[1], bootstrap.digest(bootstrap.__file__))
        self.assertIn("--workflow .github/workflows/rust-candidate.yml", workflow)
        self.assertIn("if: matrix.target == 'linux-x86_64'", workflow)
        self.assertIn("if: matrix.target == 'macos-arm64'", workflow)
        self.assertIn("--receipt-environment CANDIDATE_PYTHON_BOOTSTRAP", workflow)
        self.assertIn("python-source-bootstrap/", workflow)


if __name__ == "__main__":
    unittest.main()
