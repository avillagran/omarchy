#!/usr/bin/env python3
"""Verify the pinned upstream import, local delta, and offline crate closure."""

import argparse
import hashlib
import json
from pathlib import Path
import tarfile
import tomllib

ROOT = Path(__file__).resolve().parents[1]


def sha256(data):
    return hashlib.sha256(data).hexdigest()


def verify(root, archive=None):
    vendor = root / "vendor/ttfx"
    manifest = json.loads((root / "vendor/ttfx-provenance.json").read_text())
    assert manifest["version"] == "0.4.0"
    assert manifest["revision"] == "ea40033109d150847d6014545e8005ec3f845acc"
    assert manifest["base_revision"] == "702b630512e76dc8edcbba47cf948e857bed8d77"
    assert manifest["pull_request"] == 40
    assert manifest["merged_at_import"] is False
    inventory = {
        path.relative_to(vendor).as_posix()
        for path in vendor.rglob("*")
        if path.is_file() and "target" not in path.relative_to(vendor).parts
    }
    assert inventory == set(manifest["files"]), "upstream source inventory drift"
    for relative, hashes in manifest["files"].items():
        assert sha256((vendor / relative).read_bytes()) == hashes["vendored_sha256"], relative
    patch = root / "vendor/ttfx-plymouth.patch"
    assert sha256(patch.read_bytes()) == manifest["patch_sha256"], "local delta drift"
    lock_bytes = (root / "Cargo.lock").read_bytes()
    assert sha256(lock_bytes) == manifest["bridge_lock_sha256"], "lockfile drift"
    lock = tomllib.loads(lock_bytes.decode())
    packages = {
        (package["name"], package["version"]): package["checksum"]
        for package in lock["package"]
        if package.get("source", "").startswith("registry+")
    }
    assert packages == {
        (package["name"], package["version"]): package["checksum"]
        for package in manifest["registry_packages"]
    }, "registry dependency closure drift"
    for package in manifest["registry_packages"]:
        directory = root / "vendor/crates" / package["directory"]
        checksums = json.loads((directory / ".cargo-checksum.json").read_text())
        assert checksums["package"] == package["checksum"], directory
        for relative, expected in checksums["files"].items():
            assert sha256((directory / relative).read_bytes()) == expected, directory / relative
    if archive:
        assert sha256(archive.read_bytes()) == manifest["archive_sha256"], "archive digest"
        prefix = "ttfx-" + manifest["revision"] + "/"
        with tarfile.open(archive) as source:
            for relative, hashes in manifest["files"].items():
                with source.extractfile(prefix + relative) as stream:
                    assert sha256(stream.read()) == hashes["upstream_sha256"], relative
    print(
        f"vendor provenance: PASS ({len(inventory)} source files, "
        f"{len(packages)} registry packages; PR #40 is not marked merged)"
    )


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=ROOT)
    parser.add_argument("--upstream-archive", type=Path)
    args = parser.parse_args()
    verify(args.root, args.upstream_archive)
