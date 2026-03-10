# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0-rc1] - 2026-03-09

### Added

- Ubuntu 24.04 base image pinned by digest for reproducibility.
- Rust stable toolchain via rustup (rustc 1.94.0, cargo, rustfmt, clippy,
  rust-analyzer, llvm-tools-preview).
- Single image only. Ubuntu 24.04's apt Rust is 1.75, far behind stable
  1.85+. The supply-chain-auditability argument for a system-only image
  does not hold when the language version gap is this large.
- Both `linux/amd64` and `linux/arm64` multi-arch builds supported.
- Embedded bare-metal targets via `rustup target add`:
  - `thumbv6m-none-eabi` (Cortex-M0/M0+)
  - `thumbv7m-none-eabi` (Cortex-M3)
  - `thumbv7em-none-eabi` (Cortex-M4/M7 without FPU)
  - `thumbv7em-none-eabihf` (Cortex-M7 with FPU, STM32F769I)
  - `thumbv8m.main-none-eabihf` (Cortex-M33 with FPU)
- Embedded Linux cross-compilation target:
  - `armv7-unknown-linux-gnueabihf` (Cortex-A7, STM32MP135F)
  - ARM Linux cross-compiler (`gcc-arm-linux-gnueabihf`, `libc6-dev-armhf-cross`)
    for building C dependencies in the sysroot.
- cargo-binstall for fast pre-built binary installs (10-100x faster than
  `cargo install` from source).
- Cargo tools installed via binstall:
  - probe-rs (modern Rust-native replacement for OpenOCD + stlink-tools)
  - cargo-generate (project templates)
  - cargo-expand (macro expansion)
  - sccache (build cache, opt-in via RUSTC_WRAPPER)
- mold fast linker (apt).
- Debuggers: GDB, LLDB, Valgrind, gdb-multiarch.
- Python 3 with venv support.
- Zsh interactive shell with autosuggestions and syntax highlighting.
- Runtime-adaptive user identity via `entrypoint.sh` — no rebuild needed
  per developer.
- Rootless detection via `/proc/self/uid_map` inspection.
- Rootful privilege drop via `gosu`.
- `DISPLAY_USER` environment variable for correct prompt identity in
  rootless mode.
- Container detection markers (`IN_CONTAINER`, `CONTAINER_RUNTIME`)
  exported by entrypoint for reliable `.zshrc` detection.
- Container-aware Zsh prompt with git branch and runtime indicator.
- Rust development aliases: `cb`, `cbr`, `cck`, `ccl`, `cf`, `cl`,
  `cr`, `crr`, `ct`, `ctn`, `cdoc`, `cadd`, `cup`.
- `container_info` shell function showing rustc, cargo, rustup, probe-rs,
  and mold versions.
- Makefile with targets: `build`, `build-no-cache`, `run`, `run-root`,
  `run-shell`, `pull`, `test`, `test-docker`, `test-podman`, `inspect`,
  `save`, `show-tags`, `tag-version`, `tag-latest`, `clean`, `compress`.
- Docker convenience aliases: `docker-pull`, `docker-build`, `docker-run`.
- Podman convenience aliases: `podman-pull`, `podman-build`, `podman-run`
  with `--userns=keep-id`.
- Configurable container CLI via `CONTAINER_CLI` variable (default: nerdctl).
- GitHub Actions build workflow with multi-arch build and smoke test.
- GitHub Actions publish workflow with GHCR push.
- `examples/hello_rust/` smoke test project with Cargo.
- LICENSE, README, and USER_GUIDE copied into image at
  `/usr/share/doc/dev-container-rust/`.
- Comprehensive USER_GUIDE.md covering architecture, security model,
  version upgrade procedures, and design decisions.

### Security

- Base image pinned by SHA256 digest.
- All GitHub Actions pinned by SHA digest for supply-chain security.
- `latest` tag only published on semver tags or explicit opt-in.
- `run-root` bypasses entrypoint to guarantee a true root shell.
- Passwordless sudo kept for development convenience; documented as an
  explicit design decision.
