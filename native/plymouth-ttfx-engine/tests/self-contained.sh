#!/bin/bash
set -euo pipefail

root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
sandbox=$(mktemp -d "${TMPDIR:-/tmp}/ttfx-plymouth-offline.XXXXXX")
cleanup() {
  rm -rf -- "$sandbox"
}
trap cleanup EXIT INT TERM

mkdir -p "$sandbox/source" "$sandbox/cargo-home" "$sandbox/target"
(
  cd "$root"
  tar --exclude='./target' --exclude='./vendor/ttfx/target' -cf - .
) | tar -xf - -C "$sandbox/source"

(
  cd "$sandbox/source"
  python3 tests/vendor-provenance.py
  CARGO_HOME="$sandbox/cargo-home" CARGO_TARGET_DIR="$sandbox/target" \
    cargo build --locked --offline --profile plymouth -j1
  gcc -std=c11 -Wall -Wextra -Wpedantic -Werror -Iinclude tests/smoke.c \
    "$sandbox/target/plymouth/libttfx_plymouth.a" -ldl -lpthread -lm \
    -o "$sandbox/smoke"
  "$sandbox/smoke"
)

printf 'isolated locked offline build: PASS\n'
