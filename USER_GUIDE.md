<!-- ====================================================================== -->
<!-- USER_GUIDE.md                                                          -->
<!-- ====================================================================== -->
<!-- Copyright (c) 2025 Michael Gardner, A Bit of Help, Inc.               -->
<!-- SPDX-License-Identifier: BSD-3-Clause                                  -->
<!-- See LICENSE file in the project root.                                  -->
<!-- ====================================================================== -->

# User Guide: dev_container_rust

**Version**: 1.0.0
**Date**: 2026-03-09
**Authors**: Michael Gardner, Claude (Anthropic), GPT (OpenAI)

---

## 0. Why Single Image Only

### 0.1 Why there is no system-toolchain Dockerfile

Ubuntu 24.04's apt Rust package is version 1.75, far behind the current stable
release (1.85+). The supply-chain-auditability argument for a system-only image
does not hold when the language version gap is this large. Rustup is the
standard Rust installation method endorsed by the Rust project, and both a
hypothetical "system" image and this image would use rustup, making a second
Dockerfile pointless.

This stands in contrast to the C++ container, where the system image provides
Clang 18 and GCC 13 — fully functional C++20 compilers — from Ubuntu's apt
repositories. The version gap is small enough that a system-only image offers
genuine supply-chain value.

### 0.2 Supported architectures

See the architecture compatibility table in
[README.md](README.md#component-sources) for a full breakdown of component
sources and versions per architecture.

The image uses Ubuntu 24.04 and supports `linux/amd64` and `linux/arm64`.
Apple Silicon users can use the image for native arm64 performance.

### 0.3 Embedded development

This image includes targets for two embedded development workflows:

| Board | SoC | Core | Runtime | Target / Cross-compiler |
|-------|-----|------|---------|-------------------------|
| STM32F769I Discovery | STM32F769NI | Cortex-M7 | Bare metal | `thumbv7em-none-eabihf` |
| STM32MP135F Discovery | STM32MP135F | Cortex-A7 | Linux | `armv7-unknown-linux-gnueabihf` + `arm-linux-gnueabihf-gcc` |

Rust uses the same compiler for desktop and embedded development — you just
add cross-compilation targets via `rustup target add`. No separate
cross-compiler (like `arm-none-eabi-gcc`) is needed for bare-metal targets.

The bare-metal workflow uses probe-rs for flashing and debugging. probe-rs
is a modern, Rust-native replacement for OpenOCD and stlink-tools.

The Linux cross-compilation target requires `arm-linux-gnueabihf-gcc` for
linking C dependencies and the sysroot (`libc6-dev-armhf-cross`).

For ST's proprietary tools (STM32CubeCLT, STM32CubeMX), see the "STM32 Custom
Image" section in [README.md](README.md#stm32-custom-image).

#### Configuring your project for each target

**Desktop (native)**

No extra configuration is needed. Build with Cargo directly:

```bash
cargo build
```

**STM32F769I — Cortex-M7 bare-metal**

Create a `.cargo/config.toml` in your project root:

```toml
[build]
target = "thumbv7em-none-eabihf"

[target.thumbv7em-none-eabihf]
rustflags = [
  "-C", "link-arg=-Tlink.x",
]
```

The `link.x` linker script is typically provided by your board support crate
(e.g., `cortex-m-rt`). Then build as usual:

```bash
cargo build
```

**STM32MP135F — Cortex-A7 Linux**

Create a `.cargo/config.toml` in your project root:

```toml
[target.armv7-unknown-linux-gnueabihf]
linker = "arm-linux-gnueabihf-gcc"
```

Then build with the cross-compilation target:

```bash
cargo build --target armv7-unknown-linux-gnueabihf
```

---

## 1. Prerequisites

### 1.1 Primary runtime: nerdctl + containerd (rootless)

This is the default development runtime. Install nerdctl and containerd
following the [nerdctl documentation](https://github.com/containerd/nerdctl).

### 1.2 Optional: Docker Engine (rootful testing)

Docker Engine is required for `make test-docker` and rootful testing.

```bash
# Ubuntu 24.04
sudo apt-get update
sudo apt-get install -y docker.io docker-buildx

# Add your user to the docker group.
sudo usermod -aG docker "$USER"

# Apply the group change — log out and back in.
# Verify after re-login.
docker --version
docker buildx version
```

> **Do not use `newgrp docker`** as a shortcut to apply the group change.
> It sets `docker` as the primary GID, which breaks Podman's `newuidmap`
> if Podman is also installed. A full logout/login picks up `docker` as a
> supplementary group and avoids this conflict.

Docker Engine coexists safely with rootless nerdctl/containerd. Docker runs
a system-level containerd at `/run/containerd/containerd.sock`, while rootless
nerdctl runs a user-space containerd at `~/.local/share/containerd/`. They use
separate storage and do not conflict.

### 1.3 Optional: Podman (rootless testing)

Podman is required for `make test-podman`.

```bash
# Ubuntu 24.04
sudo apt-get update
sudo apt-get install -y podman
```

Podman rootless requires `crun` and `fuse-overlayfs`:

```bash
sudo apt-get install -y crun
```

Configure Podman to use `crun` and `fuse-overlayfs`:

```ini
# ~/.config/containers/containers.conf
[engine]
runtime = "crun"
```

```ini
# ~/.config/containers/storage.conf
[storage]
driver = "overlay"

[storage.options.overlay]
mount_program = "/usr/local/bin/fuse-overlayfs"
```

> **Known limitation**: Podman's `--userns=keep-id` requires kernel support
> for unprivileged private mounts. This does not work in Parallels Desktop
> VMs due to kernel restrictions on mount propagation. Testing on bare-metal
> Ubuntu or non-Parallels VMs is pending. See the testing status section for
> details.

---

## 2. Design Goals

1. **One image, any developer** — a pre-built image from GHCR works for any
   developer without rebuilding. User identity is provided at run time, not
   baked in at build time.
2. **Bind-mounted source** — the developer's host project directory is
   mounted into the container. Edits inside the container are live on the host.
3. **Correct file permissions** — the container process runs with the host
   user's UID/GID so that bind-mounted files are readable and writable.
4. **Works in all three target environments** — local rootless nerdctl, local
   rootful Docker, and Kubernetes.
5. **Secure by default** — non-root inside the container in rootful runtimes.
   In rootless runtimes, container UID 0 is already unprivileged on the host.

---

## 3. Architecture: Runtime-Adaptive User

The image ships with a **generic fallback user** (`dev:1000:1000`) for CI and
Kubernetes. At run time, the **entrypoint script** reads host identity from
environment variables and creates or adapts the in-container user to match.

```
Host                          Container
─────                         ─────────
$(whoami)  → HOST_USER  ───→  entrypoint.sh creates user
$(id -u)   → HOST_UID   ───→  with matching UID
$(id -g)   → HOST_GID   ───→  and matching GID
$(pwd)     → -v mount   ───→  /workspace (bind mount)
```

---

## 4. File Inventory

```
dev_container_rust/
├── .dockerignore
├── .github/
│   └── workflows/
│       ├── docker-build.yml
│       └── docker-publish.yml
├── .gitignore
├── .zshrc
├── CHANGELOG.md
├── Dockerfile
├── entrypoint.sh
├── examples/
│   └── hello_rust/
├── LICENSE
├── Makefile
├── README.md
└── USER_GUIDE.md          ← this file
```

---

## 5. Dockerfile Design

### 5.1 Toolchain installation

The Rust toolchain is installed via rustup, the official Rust installer:

1. **rustup** installs to `/opt/rustup` (RUSTUP_HOME) and `/opt/cargo`
   (CARGO_HOME). These paths are location-independent and accessible to
   all users via `chmod -R a+rX`.

2. **Stable channel** with additional components: `rust-analyzer`,
   `llvm-tools-preview` (for embedded `objcopy`, `size`, etc.).

3. **Embedded targets** are added via `rustup target add` — Rust uses the
   same compiler for desktop and embedded, unlike C/C++ which requires
   separate cross-compilers.

4. **cargo-binstall** provides fast pre-built binary installs, 10-100x
   faster than compiling from source via `cargo install`.

5. **Cargo tools** (probe-rs, cargo-generate, cargo-expand, sccache)
   are installed via binstall for speed.

### 5.2 Design elements

- Base image pinned by SHA256 digest for reproducibility.
- `SHELL ["/bin/bash", "-o", "pipefail", "-c"]` for safe pipe handling.
- Build-time user (`dev:1000:1000`) as fallback for CI and Kubernetes.
- LICENSE, README, and USER_GUIDE copied into image at
  `/usr/share/doc/dev-container-rust/`.
- Entrypoint-based runtime user adaptation.
- sccache is installed but NOT set as `RUSTC_WRAPPER` — the user opts in
  by setting `export RUSTC_WRAPPER=sccache` when desired.

---

## 6. Entrypoint Script (entrypoint.sh)

### 6.1 Responsibilities

1. Export container-detection environment variables (`IN_CONTAINER=1`,
   `CONTAINER_RUNTIME`) so that `.zshrc` can detect the container environment
   reliably without inspecting `/proc` or sentinel files.
2. Read `HOST_USER`, `HOST_UID`, `HOST_GID` from environment.
3. If they are set and the entrypoint is running as root:
   a. Create a group with the given GID (if it does not exist).
   b. Create or adapt a user with the given username, UID, GID, home
      directory, and shell.
   c. Copy the default `.zshrc` into the new home if it does not exist.
   d. Set ownership on the home directory.
   e. Detect whether the runtime is rootless or rootful.
   f. If rootful: drop privileges via `gosu` and exec the CMD.
   g. If rootless: stay as UID 0 (which is the host user), set
      `HOME=/home/$HOST_USER`, and exec the CMD.
4. If `HOST_*` vars are not set, fall through to the default user (`dev`)
   and exec the CMD directly.

### 6.2 Rootless detection

The entrypoint detects rootless mode by checking whether UID 0 inside the
container maps to a non-root UID on the host:

```bash
is_rootless() {
    if [ -f /proc/self/uid_map ]; then
        local host_uid
        host_uid=$(awk '/^\s*0\s/ { print $2 }' /proc/self/uid_map)
        [ "$host_uid" != "0" ]
    else
        return 1
    fi
}
```

### 6.3 Privilege drop decision

```
if running as UID 0:
    if HOST_USER/HOST_UID/HOST_GID provided:
        create/adapt user
        if rootless:
            # Container UID 0 == host user. Dropping to HOST_UID would
            # map to an unmapped subordinate UID and break bind mounts.
            export HOME=/home/$HOST_USER
            exec "$@"                          # stay UID 0
        else (rootful):
            exec gosu "$HOST_USER" "$@"        # drop to real user
    else:
        # No host identity. Fall through to default user.
        exec gosu dev "$@"
else:
    # Already non-root (e.g., K8s securityContext). Just run.
    exec "$@"
fi
```

### 6.4 Error handling

- If `HOST_UID` is set but `HOST_USER` is not, default `HOST_USER` to `dev`.
- If `HOST_GID` is not set, default to the value of `HOST_UID`.
- The entrypoint must never prevent the container from starting.
- If user/group creation fails (e.g., UID conflict), the fallback is
  deterministic and depends on the runtime:
  - **Rootless**: log a warning, stay as UID 0 (which is the host user),
    set `HOME` to the fallback user's home (`/home/dev`), and exec the CMD.
  - **Rootful**: log a warning, drop to the fallback user via `gosu dev`,
    and exec the CMD.

---

## 7. Container Detection (.zshrc)

The entrypoint script exports `IN_CONTAINER=1` and `CONTAINER_RUNTIME` as
environment variables before exec'ing the shell. The `.zshrc` checks these
directly:

```bash
# Container detection — trust the entrypoint marker first
if [[ -n "$IN_CONTAINER" ]] && (( IN_CONTAINER )); then
    :
elif [[ -f /.dockerenv ]]; then
    ...existing fallback checks...
fi
```

The existing fallback checks (`/.dockerenv`, `/run/.containerenv`,
`/proc/1/cgroup`) are kept for cases where the `.zshrc` is used outside this
image.

---

## 8. Security Model Summary

| Runtime             | Container UID 0 is... | Bind mount access via... | Security boundary        |
|---------------------|-----------------------|--------------------------|--------------------------|
| Docker rootful      | Real root (dangerous) | gosu drop to HOST_UID    | Container isolation      |
| nerdctl rootless    | Host user (safe)      | Stay UID 0 (= host user) | User namespace           |
| Podman rootless     | Host user (safe)      | --userns=keep-id         | User namespace           |
| Kubernetes          | Blocked by policy     | fsGroup in pod spec      | Pod security standards   |

---

## 9. Resolved Questions

1. **Why no system-toolchain image**: Ubuntu 24.04's apt Rust is 1.75, far
   behind stable 1.85+. Both images would use rustup, making a second
   Dockerfile pointless. **Decided.**

2. **Embedded approach**: Rust uses the same compiler for desktop and embedded.
   Cross-compilation targets are added via `rustup target add`. No separate
   cross-compiler needed for bare-metal. probe-rs replaces OpenOCD + stlink
   as the modern, Rust-native flash/debug tool. **Decided.**

3. **Tool installation**: cargo-binstall for pre-built binaries (10-100x
   faster than `cargo install`). **Decided.**

4. **Build cache**: sccache installed but NOT set as RUSTC_WRAPPER by default.
   User opts in when desired. **Decided.**

5. **Fast linker**: mold (apt) — available on Ubuntu 24.04 for both amd64
   and arm64. **Decided.**

6. **gosu vs su-exec**: `gosu` — more common in Docker ecosystems, available
   in Ubuntu apt. **Decided.**

7. **Container detection**: Entrypoint exports `IN_CONTAINER=1` and
   `CONTAINER_RUNTIME` as environment variables. `.zshrc` checks those first,
   with existing sentinel/cgroup checks as fallback. **Decided.**

8. **Workspace path**: `/workspace` — fixed mount point, decoupled from
   username. **Decided.**

9. **Configurable container CLI**: `CONTAINER_CLI ?= nerdctl` with
   `docker-run` / `docker-build` as convenience aliases. **Decided.**

10. **Podman support**: Added `podman-build` and `podman-run` targets.
    `podman-run` uses `--userns=keep-id` instead of `HOST_*` environment
    variables. **Decided.**

11. **sudo + passwordless sudo**: Kept intentionally for development
    convenience. In rootless runtimes, container UID 0 is already
    unprivileged on the host. **Decided.**

## 10. Remaining Open Questions

None at this time.

---

## 11. CI Workflow Design

### 11.1 docker-build.yml

Single job (no matrix — single image only), multi-arch:

- Builds with `docker buildx build --platform linux/amd64,linux/arm64`
- Loads amd64 image for smoke test (`--load` only supports single platform)
- Smoke test compiles `examples/hello_rust` with `cargo build` and verifies
  toolchain versions

### 11.2 docker-publish.yml

Single job:

- Builds and pushes `dev-container-rust` for amd64+arm64
- Tags: `latest`, `rust-stable`, `v{tag}`

All GitHub Actions are pinned by SHA digest for supply-chain security.

---

## 12. Shell Aliases (.zshrc)

The `.zshrc` provides Rust development aliases:

| Alias | Command | Description |
|-------|---------|-------------|
| `cb` | `cargo build` | Build project |
| `cbr` | `cargo build --release` | Build release |
| `cck` | `cargo check` | Type-check project |
| `ccl` | `cargo clippy` | Run clippy linter |
| `cf` | `cargo fmt` | Format code |
| `cl` | `cargo clean` | Clean build artifacts |
| `cr` | `cargo run` | Run project |
| `crr` | `cargo run --release` | Run release build |
| `ct` | `cargo test` | Run tests |
| `ctn` | `cargo test -- --nocapture` | Run tests with output |
| `cdoc` | `cargo doc --open` | Generate and open docs |
| `cadd` | `cargo add` | Add a dependency |
| `cup` | `cargo update` | Update dependencies |

Plus standard git, navigation, file, and search aliases.

---

## 13. Upgrading Component Versions

### 13.1 Ubuntu base image

The Dockerfile pins its base image by digest for reproducibility.

```bash
nerdctl pull ubuntu:24.04
nerdctl image inspect ubuntu:24.04 \
  | python3 -c "import json,sys; d=json.load(sys.stdin); print(d[0]['RepoDigests'][0])"
# Update the FROM line in the Dockerfile with the new digest.
```

Rebuild and test after updating.

### 13.2 Rust toolchain version

The Rust toolchain tracks the stable channel. Rebuilding the image picks up
the latest stable release automatically. To pin a specific version:

```dockerfile
# In Dockerfile, change:
sh -s -- -y --default-toolchain stable
# To:
sh -s -- -y --default-toolchain 1.85.0
```

### 13.3 Cargo tools

Cargo tools are installed via cargo-binstall. Rebuilding picks up the latest
versions. To pin specific versions, add version specifiers:

```bash
cargo binstall -y --no-symlinks probe-rs-tools@0.24.0
```

### 13.4 mold linker

The mold version is determined by Ubuntu's apt package. Version updates come
with Ubuntu package updates.

### 13.5 ARM cross-compiler

The ARM cross-compiler is installed from Ubuntu's apt repository:

- `gcc-arm-linux-gnueabihf` — Linux (Cortex-A, STM32MP135F)

Version updates come with Ubuntu package updates.

### 13.6 Checklist

- [ ] Update version numbers / digests in the Dockerfile.
- [ ] Rebuild the image: `make build-no-cache`.
- [ ] Run the image and verify toolchain versions.
- [ ] Commit, tag, and push.

---

## 14. Pre-Release Testing Status

This section tracks testing gaps that should be resolved before the next
release. Remove or update entries as they are verified.

| Area                              | Status       | Notes                                                        |
|-----------------------------------|--------------|--------------------------------------------------------------|
| Rootless nerdctl (local)          | Verified     | Ubuntu 24.04 base, nerdctl. Build + smoke test passed.      |
| Docker rootful (macOS)            | Verified     | macOS Intel host, Docker. Build + smoke test passed.        |
| GitHub Actions build workflow     | Verified     | Multi-arch build + smoke test passed.                        |
| GitHub Actions publish workflow   | Verified     | GHCR push passed.                                            |
| Podman rootless (local)           | Blocked      | `--userns=keep-id` fails in Parallels VM (kernel restriction). |
| Kubernetes deployment             | Not tested   | Image is designed to be compatible; no cluster available.    |

---

Copyright (c) 2025 Michael Gardner, A Bit of Help, Inc.
SPDX-License-Identifier: BSD-3-Clause
