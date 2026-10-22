#!/usr/bin/env python3
"""Build the source irgx dependency privately, then run one native Cargo command.

The current Rust API needs additive native exports absent from irgx's existing
vendored archives. A failed source build never falls back to an older archive.
Select the repository toolchain before calling this host-build helper.
"""
from __future__ import annotations

import argparse
from contextlib import contextmanager
import fcntl
import json
import os
import platform
import shutil
import tempfile
from pathlib import Path
import re
import subprocess
import tomllib

import migration as m

IRREGEX = m.ROOT.parent / "irregex"
PREFIX = m.ROOT / ".local/rust-native/irgx"  # Historical raw archive stays untouched.
RAW_PREFIX = PREFIX.parent / "source-irgx"


def rust_toolchain() -> dict:
    """Record the visible Rust/Cargo versions and explicit compilation controls."""
    rustc = os.environ.get("RUSTC", "rustc")
    versions = {}
    for name, command in (("rustc", [rustc, "--version", "--verbose"]),
                          ("cargo", ["cargo", "--version", "--verbose"])):
        versions[name] = subprocess.run(command, check=True, capture_output=True,
                                        text=True).stdout.strip()
    # Keep only compilation controls, never the process's unrelated environment.
    controls = ("RUSTC", "RUSTC_WRAPPER", "RUSTC_WORKSPACE_WRAPPER", "RUSTDOC",
                "RUSTFLAGS", "CARGO_ENCODED_RUSTFLAGS", "RUSTDOCFLAGS",
                "CARGO_ENCODED_RUSTDOCFLAGS", "CARGO_INCREMENTAL", "SDKROOT")
    versions["environment"] = {key: os.environ[key] for key in controls if key in os.environ}
    return versions


@contextmanager
def build_lock():
    PREFIX.parent.mkdir(parents=True, exist_ok=True)
    with (PREFIX.parent / "build.lock").open("a") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        yield


def rust_inputs() -> dict:
    root = m.ROOT.resolve()
    crate = root / "rust"
    manifest = tomllib.loads((crate / "Cargo.toml").read_text())
    members = {crate}
    for spec in manifest.get("workspace", {}).get("members", []):
        matches = [crate] if spec == "." else list(crate.glob(spec))
        if not matches:
            raise ValueError(f"missing Rust workspace member: {spec}")
        for member in matches:
            if not member.resolve().is_relative_to(crate.resolve()):
                raise ValueError(f"Rust workspace member is outside retained source: {spec}")
            members.add(member)
    # Default tests and explicit working witnesses read manifests, expected
    # trees, grammar/source rosters and scanner specimens at runtime. Literal
    # include discovery alone cannot retain or guard those inventories.
    roots = [root / "customary", root / "test/grammar", root / "include",
             root / "test/migration/reference", root / "test/migration/specimens",
             root / "research/joinery/specimen", root / "research/joinery/corpus",
             root / "upstream/grammars", root / "upstream/sources"]
    paths = {crate / "Cargo.toml", crate / "Cargo.lock", root / "grammars.toml"}
    for member in members:
        paths.add(member / "Cargo.toml")
        if (member / "build.rs").is_file():
            paths.add(member / "build.rs")
        roots.extend(member / name for name in ("src", "tests", "examples", "benches", ".cargo"))
    for base in roots:
        paths.update(p for p in base.rglob("*") if p.is_file())
    # Literal includes can reach pinned inputs outside a member's source tree.
    pending = [p for p in paths if p.suffix == ".rs"]
    while pending:
        source = pending.pop()
        for match in re.finditer(r'include(?:_str|_bytes)?!\(\s*"([^"]+)"', source.read_text()):
            target = (source.parent / match[1]).resolve()
            if (not target.is_relative_to(root)
                    or target.is_relative_to(root / "holdout/vendor")):
                raise ValueError(f"compile input is outside retained source: {target}")
            if target not in paths:
                paths.add(target)
                if target.suffix == ".rs":
                    pending.append(target)
    return {str(path.relative_to(root)): m.sha(path.read_bytes()) for path in sorted(paths)}


def inputs() -> dict:
    native = m.snapshot("irregex")
    binding = IRREGEX / "bindings/rust"
    paths = sorted((binding / "src").rglob("*.rs")) + [binding / "build.rs", binding / "Cargo.toml"]
    return {"native": {k: native[k] for k in ("commit", "source_sha256", "files")},
            "binding": {str(p.relative_to(IRREGEX)): m.sha(p.read_bytes()) for p in paths}}


def preserve_sources(home: Path, files: dict, label: str) -> str:
    """Retain the exact inputs, including uncommitted code, for reconstruction."""
    base = PREFIX.parent / "sources"
    if Path(label).parts != (label,) or label in (".", ".."):
        raise ValueError(f"invalid retained source label: {label}")
    out = base / label / m.sha(m.encoded(files))

    def retained_parents(path: Path) -> None:
        # Only this owned subtree is constrained; /var may itself be a host alias.
        for parent in (base, *(base / part for part in path.relative_to(base).parents
                               if part != Path("."))):
            if parent.is_symlink() or (parent.exists() and not parent.is_dir()):
                raise ValueError(f"retained source parent is not a directory: {parent}")

    retained_parents(out / "manifest.json")
    for rel, expected in files.items():
        value = Path(rel)
        if value.is_absolute() or ".." in value.parts or str(value) != rel or not value.parts:
            raise ValueError(f"invalid retained source path: {rel}")
        stored = out / rel
        retained_parents(stored)
        if expected is None:
            if any(path.exists() or path.is_symlink() for path in (home / rel, stored)):
                raise ValueError(f"deleted source reappeared: {label}/{rel}")
            continue  # A deletion is retained in the manifest.
        data = (home / rel).read_bytes()
        if m.sha(data) != expected:
            raise ValueError(f"source changed while retaining {label}/{rel}")
        if stored.is_symlink() or (stored.exists() and not stored.is_file()):
            raise ValueError(f"retained source is not a regular file: {stored}")
        if stored.exists():
            if m.sha(stored.read_bytes()) != expected:
                raise ValueError(f"retained source was modified: {stored}")
        else:
            m.write(out, rel, data)
    manifest = m.encoded(files)
    if (out / "manifest.json").is_symlink() or ((out / "manifest.json").exists()
                                               and not (out / "manifest.json").is_file()):
        raise ValueError(f"retained source manifest is not a regular file: {out}")
    if (out / "manifest.json").exists():
        if (out / "manifest.json").read_bytes() != manifest:
            raise ValueError(f"retained source manifest was modified: {out}")
    else:
        m.write(out, "manifest.json", manifest)
    return str(out)


def native_environment(prefix: Path = RAW_PREFIX) -> dict[str, str]:
    before = inputs()
    command = ["zig", "build", "--prefix", str(prefix), "-Doptimize=ReleaseFast",
               "-Dlib-optimize=ReleaseFast", "-Dstrip=true"]
    subprocess.run(command, cwd=IRREGEX, check=True)
    if inputs() != before:
        raise ValueError("irgx sources changed during build; no Cargo command was run")
    archive = prefix / "lib/libirgx.a"
    if not archive.is_file():
        raise ValueError("successful native build omitted libirgx.a; refusing stale fallback")
    sources = preserve_sources(
        IRREGEX, before["native"]["files"] | before["binding"], "irgx"
    )
    if inputs() != before:
        raise ValueError("irgx sources changed while retained; no Cargo command was run")
    m.write(prefix, "provenance.json", m.encoded({
        "repository": str(IRREGEX), "inputs": before, "command": command,
        "sources": sources,
        "archive_sha256": m.sha(archive.read_bytes()),
        "zig": subprocess.run(["zig", "version"], check=True, capture_output=True,
                              text=True).stdout.strip(),
        "sdkroot": os.environ.get("SDKROOT"),
    }))
    return os.environ | {"IRGX_LIB_DIR": str(archive.parent)}


def boundary_tools(objcopy: Path | None = None, indexer: Path | None = None) -> dict:
    """Select tools deterministically; no unrelated rustup toolchain search."""
    import rust_static_boundary as boundary
    target = {('Darwin', 'arm64'): 'macos-arm64', ('Linux', 'x86_64'): 'linux-x86_64'}.get(
        (platform.system(), platform.machine()))
    if target is None:
        raise ValueError('native C boundary supports macOS ARM64 or Linux x86_64 only')
    if objcopy is None:
        found = shutil.which('llvm-objcopy') or shutil.which('rust-objcopy')
        if found:
            objcopy = Path(found)
        else:
            rustc = os.environ.get('RUSTC', 'rustc')
            root = subprocess.run([rustc, '--print', 'sysroot'], check=True, capture_output=True, text=True).stdout.strip()
            version = subprocess.run([rustc, '-Vv'], check=True, capture_output=True, text=True).stdout
            host = re.search(r'^host: (\S+)$', version, re.M)
            if not host:
                raise ValueError('selected rustc did not identify its host')
            folder = Path(root) / 'lib/rustlib' / host[1] / 'bin'
            objcopy = next((folder / name for name in ('llvm-objcopy', 'rust-objcopy')
                            if (folder / name).is_file()), None)
    if objcopy is None:
        raise ValueError('LLVM objcopy unavailable; install selected llvm-tools or pass --objcopy explicitly')
    def identity(path, argument):
        path = Path(path).resolve(strict=True)
        if not path.is_file(): raise ValueError('boundary tool is not a regular executable')
        before = m.sha(path.read_bytes())
        version = subprocess.run([str(path), argument], env=boundary._tool_environment(),
                                 check=True, capture_output=True, text=True).stdout.strip()
        if before != m.sha(path.read_bytes()): raise ValueError('boundary tool changed during discovery')
        return {'path': str(path), 'sha256': before, 'version': version,
                'identity_scope': 'selected executable or explicit launcher; no inferred backend/runtime byte identity'}
    selected = {'target': target, 'objcopy': identity(objcopy, '--version')}
    if 'LLVM' not in selected['objcopy']['version']:
        raise ValueError('LLVM objcopy required; GNU objcopy is not a fallback')
    if target == 'macos-arm64':
        if indexer is None:
            indexer = Path(subprocess.run(['xcrun', '--find', 'libtool'], check=True,
                                         capture_output=True, text=True).stdout.strip())
        selected['indexer'] = identity(indexer, '-V')
        if not selected['indexer']['version'].startswith('Apple Inc. version cctools'):
            raise ValueError('Apple libtool indexer required')
    return selected


def producer_inputs() -> dict:
    import rust_static_boundary as boundary
    import rust_archive
    return {str(Path(p).resolve()): m.sha(Path(p).read_bytes())
            for p in (__file__, boundary.__file__, rust_archive.__file__)}


def check_native_link(selection: dict, native: dict, tools: dict, *, abi_family: str = 'irgx-abi2-105') -> dict:
    """Rejoin actual Cargo input to its immutable raw copy and checked proof."""
    import rust_static_boundary as boundary
    if abi_family not in (boundary.IRGX_ABI2, boundary.IRGX_MUNCH_IMAGE1):
        raise ValueError('unsupported native IRGX ABI family')
    identity = selection['identity']
    header = IRREGEX / 'include/irgx.h'
    if (identity['source_inputs'] != native['inputs']
            or identity['abi_family'] != abi_family or identity['target'] != tools['target']
            or identity['raw_sha256'] != native['archive_sha256']
            or identity['header_sha256'] != m.sha(header.read_bytes())
            or identity['producer_inputs'] != producer_inputs()
            or identity['tools'] != tools):
        raise ValueError('selected native source/header/producer/tool identity differs')
    for item in (tools['objcopy'], *([tools['indexer']] if 'indexer' in tools else [])):
        if m.sha(Path(item['path']).read_bytes()) != item['sha256']:
            raise ValueError('selected boundary tool changed')
    root = Path(selection['root'])
    metadata = root / 'selection.json'
    if (metadata.is_symlink() or not metadata.is_file()
            or ('selection_sha256' in selection and m.sha(metadata.read_bytes()) != selection['selection_sha256'])):
        raise ValueError('native selection metadata changed or is not a regular file')
    raw, selected, proof = root / 'original/libirgx.a', root / 'lib/libirgx.a', root / 'proof.json'
    for path, expected in ((raw, identity['raw_sha256']), (selected, selection['archive_sha256']),
                           (proof, selection['proof_sha256']), (root / 'original/irgx.h', identity['header_sha256'])):
        if path.is_symlink() or not path.is_file() or m.sha(path.read_bytes()) != expected:
            raise ValueError('selected native archive/proof/header differs')
    record = json.loads(proof.read_bytes())
    if record.get('abi_family') != abi_family:
        raise ValueError('selected native proof ABI family differs')
    if record['helper_sha256'] != identity['producer_inputs'][str(Path(boundary.__file__).resolve())]:
        raise ValueError('selected native proof producer differs')
    import rust_archive
    if record.get('parser_sha256') != identity['producer_inputs'][str(Path(rust_archive.__file__).resolve())]:
        raise ValueError('selected native proof parser differs')
    def same_tool(actual, selected):
        return (actual.get('path') == selected['path'] and actual.get('sha256') == selected['sha256']
                and actual.get('version', '').strip() == selected['version'].strip())
    transform = record.get('transform', {})
    if not same_tool(transform.get('tool', {}), tools['objcopy']):
        raise ValueError('recorded native transformer differs from selected tool')
    if 'index_restoration' in transform and ('indexer' not in tools
            or not same_tool(transform['index_restoration'], tools['indexer'])):
        raise ValueError('recorded native indexer differs from selected tool')
    # Atomic cache publication moves this directory. Keep historical command
    # paths, but rejoin every retained proof payload and log at its current root.
    produced = Path(selection['production_root'])
    proof_home = root / 'proof-work'
    if proof_home.is_symlink():
        raise ValueError('native proof directory is a symlink')
    payloads = {}
    for path in proof_home.rglob('*'):
        if path.is_symlink() or (not path.is_file() and not path.is_dir()):
            raise ValueError('native proof payload is not a regular file/directory')
        if path.is_file(): payloads[str(path.relative_to(root))] = m.sha(path.read_bytes())
    if payloads != selection['proof_files']:
        raise ValueError('retained native proof payloads changed')
    for command in transform.get('commands', []):
        Path(command['cwd']).relative_to(produced)
        for channel in ('stdout', 'stderr'):
            log = command[channel]
            relative = Path(log['path']).relative_to(produced)
            if str(relative) not in payloads or payloads[str(relative)] != log['sha256']:
                raise ValueError('retained native producer log differs')
    boundary.verify_archive(raw, selected, record, target=tools['target'],
        exports=boundary.declared_exports(header, tools['target'], abi_family=abi_family),
        abi_family=abi_family)
    if selection['library_dir'] != str(selected.parent):
        raise ValueError('actual IRGX_LIB_DIR differs from selected native proof')
    return record


def native_link(raw: Path, native: dict, tools: dict, cache: Path | None = None, *, abi_family: str = 'irgx-abi2-105') -> dict:
    """Select an immutable checked native C boundary; never overwrite bad entries."""
    import rust_static_boundary as boundary
    if abi_family not in (boundary.IRGX_ABI2, boundary.IRGX_MUNCH_IMAGE1):
        raise ValueError('unsupported native IRGX ABI family')
    cache = cache or PREFIX.parent / ('native-boundary-munch-image1' if abi_family == boundary.IRGX_MUNCH_IMAGE1 else 'native-boundary')
    header = IRREGEX / 'include/irgx.h'
    identity = {'raw_sha256': m.sha(raw.read_bytes()), 'source_inputs': native['inputs'],
                'header_sha256': m.sha(header.read_bytes()), 'abi_family': abi_family,
                'target': tools['target'], 'tools': tools, 'producer_inputs': producer_inputs()}
    if identity['raw_sha256'] != native['archive_sha256']:
        raise ValueError('raw source-engine archive differs before selection')
    if native['inputs']['native']['files'].get('include/irgx.h') != identity['header_sha256']:
        raise ValueError('authoritative native header is not source-attested')
    key = m.sha(m.encoded(identity));entry = cache / key
    hit = entry.exists() or entry.is_symlink()
    if not hit:
        cache.mkdir(parents=True, exist_ok=True)
        attempt = Path(tempfile.mkdtemp(prefix='attempt-' + key + '-', dir=cache))
        try:
            (attempt / 'original').mkdir()
            shutil.copy2(raw, attempt / 'original/libirgx.a')
            shutil.copy2(header, attempt / 'original/irgx.h')
            proof = boundary.transform_archive(attempt / 'original/libirgx.a', attempt / 'lib/libirgx.a',
                target=tools['target'], exports=boundary.declared_exports(header, tools['target'], abi_family=abi_family),
                abi_family=abi_family, objcopy=Path(tools['objcopy']['path']),
                indexer=Path(tools['indexer']['path']) if 'indexer' in tools else None, work=attempt / 'proof-work')
            m.write(attempt, 'proof.json', m.encoded(proof))
            selection = {'schema': 1, 'identity': identity, 'archive_sha256': m.sha((attempt / 'lib/libirgx.a').read_bytes()),
                         'proof_sha256': m.sha((attempt / 'proof.json').read_bytes()), 'raw_provenance': native,
                         'production_root': str(attempt),
                         'proof_files': {str(p.relative_to(attempt)): m.sha(p.read_bytes())
                                         for p in (attempt / 'proof-work').rglob('*') if p.is_file()}}
            m.write(attempt, 'selection.json', m.encoded(selection))
            check_native_link({**selection, 'root': str(attempt), 'library_dir': str(attempt / 'lib')}, native, tools, abi_family=abi_family)
            if entry.exists() or entry.is_symlink(): raise ValueError('native cache appeared during publication')
            attempt.rename(entry)  # One writer under build_lock; only complete entries publish.
        except Exception as error:
            m.write(attempt, 'failure.json', m.encoded({'pass': False, 'error': str(error)}))
            raise
    if entry.is_symlink() or not entry.is_dir(): raise ValueError('native cache is not a regular directory')
    path = entry / 'selection.json'
    if path.is_symlink() or not path.is_file(): raise ValueError('partial native cache; no raw fallback')
    selection = json.loads(path.read_bytes())
    if selection.get('schema') != 1 or selection.get('identity') != identity:
        raise ValueError('native cache identity differs; no overwrite or raw fallback')
    if (selection['raw_provenance']['inputs'] != native['inputs']
            or selection['raw_provenance']['archive_sha256'] != native['archive_sha256']):
        raise ValueError('historical native cache producer differs')
    selected = {**selection, 'root': str(entry), 'library_dir': str(entry / 'lib'), 'cache_key': key,
                'cache_hit': hit, 'selection_sha256': m.sha(path.read_bytes())}
    check_native_link(selected, native, tools, abi_family=abi_family)
    return selected


def run(verb: str, args: list[str], *, objcopy: Path | None = None, indexer: Path | None = None,
        abi_family: str = 'irgx-abi2-105') -> int:
    if os.environ.get('CARGO_BUILD_TARGET') or any(a == '--target' or a.startswith('--target=') for a in args):
        raise ValueError('this helper builds host archives; cross builds need an explicit target irgx archive')
    command = ['cargo', verb, '--manifest-path', str(m.ROOT / 'rust/Cargo.toml'), *args]
    if verb == 'fmt': return subprocess.run(command, cwd=m.ROOT).returncode
    import rust_static_boundary as boundary
    if abi_family not in (boundary.IRGX_ABI2, boundary.IRGX_MUNCH_IMAGE1):
        raise ValueError('unsupported native IRGX ABI family')
    image = abi_family == boundary.IRGX_MUNCH_IMAGE1
    raw_prefix = PREFIX.parent / 'source-irgx-munch-image1' if image else RAW_PREFIX
    tools = boundary_tools(objcopy, indexer)
    with build_lock():
        env = native_environment(raw_prefix)
        native = json.loads((raw_prefix / 'provenance.json').read_bytes())
        archive = raw_prefix / 'lib/libirgx.a'
        before = rust_inputs();sources = preserve_sources(m.ROOT, before, 'joints')
        if inputs() != native['inputs'] or m.sha(archive.read_bytes()) != native['archive_sha256']:
            raise ValueError('irgx changed before Cargo; refusing an unattributed build')
        selected = native_link(archive, native, tools, abi_family=abi_family)
        selection_before = m.sha((Path(selected['root']) / 'selection.json').read_bytes())
        check_native_link(selected, native, tools, abi_family=abi_family)
        env = env | {'IRGX_LIB_DIR': selected['library_dir']}
        toolchain = rust_toolchain()
        code = subprocess.run(command, cwd=m.ROOT, env=env).returncode
        link_error = None
        try:
            check_native_link(selected, native, tools, abi_family=abi_family)
            if m.sha((Path(selected['root']) / 'selection.json').read_bytes()) != selection_before:
                raise ValueError('native selection metadata changed during Cargo')
            if (rust_inputs() != before or inputs() != native['inputs']
                    or m.sha(archive.read_bytes()) != native['archive_sha256']):
                raise ValueError('source or raw archive changed during Cargo')
        except Exception as error: link_error = str(error)
        stable = link_error is None
        m.write(PREFIX.parent, 'last-cargo-munch-image1.json' if image else 'last-cargo.json', m.encoded({
            'command': command, 'exit': code, 'stable': stable, 'rust_inputs': before, 'sources': sources,
            'native': native, 'native_link': selected, 'native_link_error': link_error,
            'native_link_environment': {'IRGX_LIB_DIR': env['IRGX_LIB_DIR']}, 'toolchain': toolchain}))
        if not stable: raise ValueError('sources or actual linked archive changed during Cargo; gate attribution refused')
        return code


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("verb", choices=("build", "test", "check", "clippy", "fmt"))
    parser.add_argument("--objcopy", type=Path, help="explicit LLVM objcopy; otherwise PATH/selected rustc sysroot")
    parser.add_argument("--indexer", type=Path, help="explicit Apple libtool; otherwise xcrun selection")
    parser.add_argument("--irgx-abi-family", choices=("irgx-abi2-105", "irgx-abi2-108-munch-image1"),
                        default="irgx-abi2-105", help="explicit native family; Image1 never upgrades implicitly")
    known, cargo = parser.parse_known_args()
    try:
        raise SystemExit(run(known.verb, cargo, objcopy=known.objcopy, indexer=known.indexer, abi_family=known.irgx_abi_family))
    except (OSError, ValueError, subprocess.CalledProcessError) as error:
        parser.exit(2, f"rust.py: {error}\n")
