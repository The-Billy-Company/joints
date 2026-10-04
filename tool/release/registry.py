"""Resolve immutable public artifact identities and publish a verified crate."""

import hashlib
import json
import os
import platform
import shutil
import tempfile
import urllib.error
import urllib.request
from pathlib import Path


def require(condition, message):
    if not condition:
        raise RuntimeError(message)


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def encoded(value):
    return (json.dumps(value, sort_keys=True, indent=2) + "\n").encode()


def package_inventory(root, version):
    names = [
        f"python/joints-{version}-py3-none-any.whl",
        f"python/joints-{version}.tar.gz",
        f"rust/joints-{version}.crate",
    ]
    return {
        name: hashlib.sha256((root / name).read_bytes()).hexdigest() for name in names
    }


def identities(root, version):
    identity = json.loads((root / "packages.json").read_bytes())
    require(
        identity["schema"] == 1 and identity["version"] == version,
        "package metadata version",
    )
    require(
        identity["files"] == package_inventory(root, version),
        "package checksum mismatch",
    )
    require(not identity["source"]["dirty"], "release packages built from dirty source")
    expected = {Path(name).name for name in identity["files"]}
    actual = {
        path.name for folder in ("python", "rust") for path in (root / folder).iterdir()
    }
    require(actual == expected, "unexpected package files")
    return identity


def build_host():
    system = platform.system()
    version = (
        platform.mac_ver()[0]
        if system == "Darwin"
        else platform.freedesktop_os_release().get("VERSION_ID", "unknown")
    )
    return {
        "system": system,
        "machine": platform.machine(),
        "version": version,
        "libc": list(platform.libc_ver()),
    }


def cargo(api, args, *command, cwd=None, env=None, capture=False):
    rust = api.run(
        ["rustup", "run", args.rust_toolchain, "rustc", "--version"], capture=True
    )
    require(rust.startswith("rustc 1.85.0 "), "Rust release floor must be 1.85.0")
    return api.run(
        ["rustup", "run", args.rust_toolchain, "cargo", *command],
        cwd=cwd or api.ROOT,
        env=env,
        capture=capture,
    )


def native_env(api, root):
    env = os.environ.copy()
    env.pop("PYTHONPATH", None)
    env.pop("PYTHONHOME", None)
    env["JOINTS_LIB"] = str(root / "lib" / api.shared(api.host()))
    env["JOINTS_LIB_DIR"] = str(root / "lib")
    env["JOINTS_LINK_KIND"] = "static"
    return env


def fetch(url, *, absent=False):
    request = urllib.request.Request(url, headers={"User-Agent": "Joints-release/1"})
    try:
        with urllib.request.urlopen(request, timeout=60) as response:
            require(
                response.status == 200,
                f"unexpected registry HTTP status: {response.status}",
            )
            return response.read()
    except urllib.error.HTTPError as error:
        if absent and error.code == 404:
            return None
        raise RuntimeError(f"registry HTTP {error.code}: {url}") from error
    except urllib.error.URLError as error:
        raise RuntimeError(f"registry did not answer: {url}: {error.reason}") from error


def resolve_registry(api, root, version, destination=None):
    identity = api.identities(root, version)
    states = {}
    pypi = api.fetch(f"https://pypi.org/pypi/joints/{version}/json", absent=True)
    states["pypi"] = "absent" if pypi is None else "present"
    if pypi is not None:
        record = json.loads(pypi)
        require(record["info"]["version"] == version, "PyPI version mismatch")
        urls = record["urls"]
        expected = {
            Path(name).name for name in identity["files"] if name.startswith("python/")
        }
        require(
            len(urls) == len(expected)
            and {item["filename"] for item in urls} == expected,
            "PyPI artifact inventory mismatch",
        )
        for item in urls:
            name = f"python/{item['filename']}"
            require(
                item["digests"]["sha256"] == identity["files"][name],
                "PyPI index checksum mismatch",
            )
            require(not item.get("yanked", False), "PyPI artifact is yanked")
            data = api.fetch(item["url"])
            require(
                hashlib.sha256(data).hexdigest() == identity["files"][name],
                "PyPI bytes mismatch",
            )
            if destination:
                (destination / name).write_bytes(data)
    crates = api.fetch(f"https://crates.io/api/v1/crates/joints/{version}", absent=True)
    states["crates"] = "absent" if crates is None else "present"
    if crates is not None:
        record = json.loads(crates)["version"]
        require(
            record["num"] == version and record["crate"] == "joints",
            "crates version mismatch",
        )
        name = f"rust/joints-{version}.crate"
        require(
            record["checksum"] == identity["files"][name],
            "crates index checksum mismatch",
        )
        require(not record["yanked"], "crate version is yanked")
        data = api.fetch(f"https://crates.io/api/v1/crates/joints/{version}/download")
        require(
            hashlib.sha256(data).hexdigest() == identity["files"][name],
            "crate bytes mismatch",
        )
        if destination:
            (destination / name).write_bytes(data)
    return states


def registry(api, args):
    with tempfile.TemporaryDirectory(prefix="joints-registry-") as temporary:
        root = Path(temporary)
        for name in ("python", "rust"):
            (root / name).mkdir()
        states = resolve_registry(api, args.packages.resolve(), args.version, root)
        require(
            states == {"pypi": "present", "crates": "present"},
            "release version absent from registry",
        )
        shutil.copyfile(args.packages / "packages.json", root / "packages.json")
        return api.verify_packages(args, root) | {"registries": states}


def publish_crate(api, args):
    identity = api.identities(args.packages.resolve(), args.version)
    require(
        api.source() == identity["source"],
        "publish source differs from tested packages",
    )
    with tempfile.TemporaryDirectory(prefix="joints-publish-") as temporary:
        temporary = Path(temporary)
        root = api.unpack_native(args.native, temporary / "native", args.version)
        env = api.native_env(root)
        target = temporary / "cargo-target"
        command = [
            "--locked",
            "--manifest-path",
            "bindings/rust/Cargo.toml",
            "--target-dir",
            str(target),
        ]
        api.cargo(args, "package", *command, env=env)
        actual = target / "package" / f"joints-{args.version}.crate"
        require(
            api.digest(actual)
            == identity["files"][f"rust/joints-{args.version}.crate"],
            "Cargo repack differs from tested crate; refusing publication",
        )
        require(api.source() == identity["source"], "source changed before publish")
        api.cargo(args, "publish", *command, env=env)
    return {"version": args.version, "crates_publish": "submitted"}


def checksums(api, args):
    packages_root = args.packages.resolve()
    version = json.loads((packages_root / "packages.json").read_bytes())["version"]
    identity = api.identities(packages_root, version)
    files = {Path(name).name: checksum for name, checksum in identity["files"].items()}
    files["packages.json"] = api.digest(packages_root / "packages.json")
    archives = {
        f"joints-{version}-{target}.tar.gz": target for target in api.TARGETS.values()
    }
    require(
        {path.name for path in args.native_directory.iterdir()} == set(archives),
        "native archive inventory mismatch",
    )
    with tempfile.TemporaryDirectory(prefix="joints-checksums-") as temporary:
        for filename, target in archives.items():
            archive = args.native_directory / filename
            root = api.unpack_native(archive, Path(temporary) / target, version, target)
            manifest = json.loads((root / "manifest.json").read_bytes())
            require(
                manifest["source"] == identity["source"],
                "release asset source mismatch",
            )
            files[filename] = api.digest(archive)
    destination = args.output or packages_root / "SHA256SUMS"
    require(not destination.exists(), "refusing to overwrite checksums")
    destination.write_text(
        "".join(f"{checksum}  {name}\n" for name, checksum in sorted(files.items()))
    )
    return {"checksums": str(destination), "version": version, "files": len(files)}
