# Vendored TTFX engine

Downstream integration: Andrés Villagrán <andres@villagranquiroz.cl>. Upstream source retains its own LICENSE and NOTICE; this attribution does not replace third-party authorship.

## Immutable source

- Upstream repository: `https://github.com/omacom/ttfx`.
- Upstream 0.4.0 base: `702b630512e76dc8edcbba47cf948e857bed8d77`.
- External PR #40 (iconidentify), imported head: `ea40033109d150847d6014545e8005ec3f845acc`.
- PR #40 was open and unmerged when imported. This is **0.4.0 plus a pinned PR**, not a claim that its AArch64 port is merged or released.
- Immutable source archive: `https://codeload.github.com/omacom/ttfx/tar.gz/ea40033109d150847d6014545e8005ec3f845acc`.
- Archive SHA-256: `dabbaab50fa6ca3b3f1b8e3ccd2b23bd883d2e21d7d8f85bc929712553555494`.

`vendor/ttfx-provenance.json` records the archive digest, upstream and downstream SHA-256 for every imported file, the local patch digest, the bridge lockfile digest, and the complete registry dependency closure. The import contains Cargo manifests, build.rs, LICENSE, NOTICE, README, src/, asm/ (both architectures), and tools/asm/. The upstream checkout was compared byte-for-byte against this archive before importing. Unrelated upstream documentation, CI, and integration-test assets are not packaged.

The bridge lockfile was re-resolved offline. Its only package change is TTFX 0.3.2 → 0.4.0; the 28 registry packages and their existing vendored checksums are unchanged. No sibling checkout is used, and no new registry dependency is required by this PR.

## Exact downstream delta

`vendor/ttfx-plymouth.patch` is the complete patch against the pinned upstream source, independently checkable with `git apply --check` in that upstream checkout. It changes 40 source files, not the assembly implementation:

- `src/engine/terminal.rs`: expose structured composited cells and skip terminal-size discovery when fixed embedded dimensions are supplied; retain a failing-probe regression test. Keep upstream's resize implementation intact.
- `src/engine/ctx.rs`: opt-in structured output without ANSI frame construction, opt-in final-text band mapping, and a structured-frame regression test. Keep upstream's motion and animation optimizations intact.
- `src/utils/graphics.rs`: restore the five-band final-text mapper and its geometry regression while using upstream's contiguous coordinate-color map instead of reverting to the old hash-map implementation.
- All 37 effect implementations: route their final-text mapping through that opt-in helper, including matrix, rain, and synthgrid. Transient gradients and orbittingvolley's launcher gradient keep their original mappings. CLI defaults are unchanged.

The existing bridge still owns first-frame creation, bounded top-to-bottom RGBA/style/glyph snapshots, virtual frame time, loader background propagation, retained terminal frames, explicit deterministic reset, panic containment, and the canonical decrypt gradient. The terminal logo's 19 nonempty rows remain the five exact colors `d0fdd9`, `a8fcba`, `82fb9c`, `539e65`, `2b5037` in bands `4,3,4,3,5`. The C ABI is unchanged; its legacy `out_looped` name reports completion, not an implicit reset. Header documentation and the stale C smoke expectation were corrected to match that existing behavior.

No password, failure-feedback, input pacing, handoff, plugin, or desktop protocol code is changed by this import.

## Assembly status: not active per frame

The actual embedded call path is `Engine::create/step` → `EffectCommand::build_effect` → Rust `Effect::next_frame` → structured terminal cells. Upstream's assembly API is `asm::try_run(Run)` → `ffi::offer` → the whole-effect `ttfx_asm_run_v*` runner. It owns terminal-oriented output and completion; it is not a bounded, resumable structured-cell API for Plymouth's event loop.

Accordingly the bridge explicitly uses `default-features = false` on TTFX. Both upstream assembly source trees and PR #40's AArch64 port are vendored unchanged, but **neither is linked or executed by the embedded build**. No assembly speedup or ARM runtime validation is claimed. Enabling the default feature or linking an object would not change this call path.

A future assembly adapter needs create/step/snapshot/reset/free primitives with host-owned timing and no tty/output/signal side effects, bounded glyph/color/style snapshots, loader-background propagation, the same final-text bands and retained completion behavior, and deterministic parity tests against the Rust backend. Native x86-64 and AArch64 execution must be verified separately. Keep the working Rust backend until those gates pass.

## Reproducible validation

Run from this directory:

```bash
cargo test --locked --offline -j1
cargo test --locked --offline -p ttfx --lib -j1
cargo clippy --locked --offline --all-targets -j1 -- -D warnings
python3 tests/vendor-provenance.py
bash tests/embedded-smoke.sh
bash tests/self-contained.sh
```

The provenance checker accepts `--upstream-archive PATH` to verify a downloaded archive without network access. It checks all source bytes and every file covered by the registry crates' Cargo checksum manifests. The embedded smoke test links the real optimized static library and uses strace to reject tty discovery, subprocesses, sleeping, signal setup, and ANSI output. Its only allowed write is the C harness's final success line.

The self-contained test copies only source (excluding both target directories), uses an initially empty CARGO_HOME and target directory, builds with `--locked --offline --profile plymouth -j1`, and links/runs the C smoke against that newly built library. It respects TMPDIR and removes the isolated build afterward.

The initial import passed 21 bridge Rust tests, 32 vendored library unit tests, Clippy with warnings denied, the cold offline build, and linked C smoke. The plugin's existing state, lifecycle, real activation, deterministic replay, handoff, and source-contract tests also passed; real Plymouth pixelbuffer testing was skipped because the host lacked its pkg-config dependencies. The plugin runner was exercised with only temporary paths redirected to scratch. The bridge is rustfmt-clean; the local vendor patch was checked for formatting without reformatting unrelated upstream code.

These are host-side checks, **not boot acceptance**. QEMU with matching Plymouth development libraries, physical Kuyen boot-to-desktop/password/handoff validation, and native ARM validation remain required. No production installation, initramfs rebuild, reboot, commit, or push was performed.
