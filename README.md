# dev_container_rust

[![Build](https://github.com/abitofhelp/dev_container_rust/actions/workflows/docker-build.yml/badge.svg)](https://github.com/abitofhelp/dev_container_rust/actions/workflows/docker-build.yml) [![Publish](https://github.com/abitofhelp/dev_container_rust/actions/workflows/docker-publish.yml/badge.svg)](https://github.com/abitofhelp/dev_container_rust/actions/workflows/docker-publish.yml) [![License: BSD-3-Clause](https://img.shields.io/badge/License-BSD--3--Clause-blue.svg)](LICENSE) [![Rust](https://img.shields.io/badge/Rust-stable-6f42c1)](#pre-installed-tools) [![Container](https://img.shields.io/badge/container-ghcr.io%2Fabitofhelp%2Fdev--container--rust-0A66C2)](#image-name)

Professional Rust development container for desktop and embedded (ARM Cortex-M/A) development.

## Supported Architectures

Single image, Ubuntu 24.04, multi-arch amd64 + arm64.

### Component Sources

| Component | Source | amd64 | arm64 | Notes |
|-----------|--------|:-----:|:-----:|-------|
| Base | Ubuntu 24.04 | Y | Y | glibc 2.39 |
| rustc/cargo | rustup (stable) | Y | Y | |
| rust-analyzer | rustup component | Y | Y | |
| rustfmt | rustup component | Y | Y | |
| clippy | rustup component | Y | Y | |
| llvm-tools | rustup component | Y | Y | For embedded (objcopy, size, etc.) |
| cargo-binstall | shell install script | Y | Y | |
| probe-rs | cargo-binstall | Y | Y | Replaces OpenOCD/stlink |
| cargo-generate | cargo-binstall | Y | Y | Project templates |
| cargo-expand | cargo-binstall | Y | Y | Macro expansion |
| sccache | cargo-binstall | Y | Y | Build cache (opt-in) |
| mold | apt | Y | Y | Fast linker |
| GCC | apt (build-essential) | Y | Y | For C dependencies |
| GDB | apt | Y | Y | |
| LLDB | apt | Y | Y | |
| gdb-multiarch | apt | Y | Y | Embedded debugging |
| Valgrind | apt | Y | Y | |
| arm-linux-gnueabihf-gcc | apt | Y | Y | STM32MP1 Linux sysroot |

### Why Single Image Only

Ubuntu 24.04's apt Rust is 1.75, far behind stable 1.85+. The supply-chain-
auditability argument for a system-only image does not hold when the language
version gap is this large. Rustup is the standard Rust installation method
and both images would use it, making a second Dockerfile pointless.

### Verified Test Matrix

| Image | Ubuntu VM (amd64) | macOS Intel (amd64) | MacBook Pro (arm64) |
|-------|:---:|:---:|:---:|
| `dev-container-rust` | Passed | Passed | Passed |

## Image Name

```text
ghcr.io/abitofhelp/dev-container-rust
```

## Why This Container Is Useful

This container provides a reproducible Rust development environment that adapts
to the host user at runtime. Any developer can pull the pre-built image and
run it without rebuilding.

The included `.zshrc` detects when it is running inside a container and
visibly marks the prompt, which helps prevent common mistakes:

- editing files in the wrong terminal
- confusing host and container environments
- forgetting which toolchain path is active
- debugging UID, GID, or mount issues more slowly than necessary

Example prompt:

```text
parallels@container /workspace (main) [ctr:rootless]
❯
```

## Features

- Multi-architecture support (`linux/amd64` + `linux/arm64`)
- Desktop Rust development (stable toolchain via rustup)
- Embedded Rust development:
  - ARM Cortex-M bare-metal (5 targets including STM32F769I)
  - ARM Cortex-A Linux cross-compilation (STM32MP135F)
- Build tools: cargo, mold (fast linker), sccache (opt-in build cache)
- Static analysis: clippy, rustfmt
- Language server: rust-analyzer
- Debuggers: GDB, LLDB, Valgrind, gdb-multiarch
- Embedded flashing: probe-rs (Rust-native, replaces OpenOCD + stlink-tools)
- Project tools: cargo-generate (templates), cargo-expand (macro expansion)
- Python 3 + venv
- Zsh interactive shell
- Runtime-adaptive user identity (no rebuild needed per developer)
- Container-aware shell prompt
- Designed for nerdctl + containerd (rootless)
- Also works with Docker (rootful), Podman (rootless), and Kubernetes
- GitHub Actions for build verification and container publishing
- Makefile for common build and run targets

## Pre-installed Tools

| Category | Tools |
|----------|-------|
| **Rust toolchain** | rustc, cargo (stable via rustup) |
| **Rust components** | rust-analyzer, rustfmt, clippy, llvm-tools |
| **Build tools** | cargo, make, mold (fast linker) |
| **Build cache** | sccache (opt-in via RUSTC_WRAPPER) |
| **C compiler** | gcc (build-essential, for C dependencies) |
| **Debuggers / profiling** | gdb, lldb, valgrind, strace |
| **Embedded (bare-metal)** | 5 thumbv7/v6/v8m targets via rustup, probe-rs, gdb-multiarch |
| **Embedded (Linux cross)** | armv7-unknown-linux-gnueabihf target, arm-linux-gnueabihf-gcc, libc6-dev-armhf-cross |
| **Cargo tools** | cargo-binstall, cargo-generate, cargo-expand |
| **Version control** | git, patch, openssh-client (ssh, scp) |
| **Text processing** | awk, sed, grep, diff, find, xargs, sort, uniq, wc, head, tail, tr, cut, tee |
| **Network** | curl, wget, rsync |
| **Archives** | tar, zip, unzip, xz, gzip, bzip2 |
| **Editors** | vim, nano |
| **Pagers / utilities** | less, more, file, which, lsof, ps, jq |
| **Search** | ripgrep (rg), fd-find (fdfind), fzf |
| **Python** | python3, pip3, python3-venv |
| **Shell** | zsh (default), bash, zsh-autosuggestions, zsh-syntax-highlighting |
| **Container** | gosu, sudo |

## Embedded Board Support

This image includes targets for two embedded development workflows:

| Board | SoC | Core | Runtime | Target / Cross-compiler |
|-------|-----|------|---------|-------------------------|
| STM32F769I Discovery | STM32F769NI | Cortex-M7 | Bare metal | `thumbv7em-none-eabihf` |
| STM32MP135F Discovery | STM32MP135F | Cortex-A7 | Linux | `armv7-unknown-linux-gnueabihf` + `arm-linux-gnueabihf-gcc` |

Rust uses the same compiler for desktop and embedded development — you just
add cross-compilation targets via `rustup target add`. No separate
cross-compiler (like `arm-none-eabi-gcc`) is needed for bare-metal targets.

The Linux cross-compilation target requires `arm-linux-gnueabihf-gcc` for
linking C dependencies and the sysroot (`libc6-dev-armhf-cross`).

### Embedded Toolchain Readiness

This image is fully self-contained for all three targets. No additional
downloads or toolchain installation is required.

| Target | Rust Target / Linker | Status |
|--------|----------------------|--------|
| Desktop (native) | default host target | Pre-installed |
| STM32F769I — Cortex-M7 bare-metal | `thumbv7em-none-eabihf` | Pre-installed |
| STM32MP135F — Cortex-A7 Linux | `armv7-unknown-linux-gnueabihf` + `arm-linux-gnueabihf-gcc` | Pre-installed |

### Embedded Targets (installed via rustup)

| Target | Board | Core | Runtime |
|--------|-------|------|---------|
| `thumbv7em-none-eabihf` | STM32F769I | Cortex-M7 (FPU) | Bare metal |
| `thumbv7em-none-eabi` | Cortex-M4/M7 (no FPU) | Cortex-M4/M7 | Bare metal |
| `thumbv7m-none-eabi` | Cortex-M3 | Cortex-M3 | Bare metal |
| `thumbv6m-none-eabi` | Cortex-M0/M0+ | Cortex-M0 | Bare metal |
| `thumbv8m.main-none-eabihf` | Cortex-M33 (FPU) | Cortex-M33 | Bare metal |
| `armv7-unknown-linux-gnueabihf` | STM32MP135F | Cortex-A7 | Linux |

### probe-rs

This image uses [probe-rs](https://probe.rs/) as the embedded flashing and
debugging tool. probe-rs is a modern, Rust-native replacement for OpenOCD
and stlink-tools. It supports STLink, J-Link, and CMSIS-DAP debug probes.

## STM32 Custom Image

For projects that require ST's proprietary tools, developers can build a custom
image on top of this base image.

ST provides a command-line installer (STM32CubeCLT) that bundles their
toolchain, STM32CubeProgrammer, and build integration:

- [STM32CubeCLT](https://www.st.com/en/development-tools/stm32cubeclt.html) — headless CLI toolchain
- [STM32CubeMX](https://www.st.com/en/development-tools/stm32cubemx.html) — project generator (GUI-based)

These tools require an ST account to download and cannot be automatically
fetched in a Dockerfile. To build a custom image:

1. Download the STM32CubeCLT Linux installer from the link above.
2. Create a `Dockerfile.stm32` that extends the base image:
   ```dockerfile
   FROM dev-container-rust:latest
   COPY STM32CubeCLT_*.sh /tmp/
   RUN chmod +x /tmp/STM32CubeCLT_*.sh && \
       /tmp/STM32CubeCLT_*.sh --mode unattended && \
       rm /tmp/STM32CubeCLT_*.sh
   ```
3. Build: `nerdctl build -f Dockerfile.stm32 -t dev-container-rust-stm32 .`

---

## Quick Start

### Pull a pre-built image

```bash
make pull
```

### Build from source

```bash
make build
```

### Run

```bash
cd ~/projects/my_rust_app
make -f /path/to/dev_container_rust/Makefile run
```

> **Note**: When using `make -f`, the Makefile mounts the caller's current
> directory (not the Makefile's directory) into the container. This is
> intentional — it bind-mounts your project, not the container repository.

The current directory is mounted into the container at `/workspace`. The
entrypoint adapts the container's home directory layout to match your host
user, so bind-mounted files are readable and writable.

### Inspect configured values

```bash
make inspect
```

## Manual Build

```bash
nerdctl build -t dev-container-rust .
```

## Manual Run

```bash
nerdctl run -it --rm \
  -e HOST_UID=$(id -u) \
  -e HOST_GID=$(id -g) \
  -e HOST_USER=$(whoami) \
  -v "$(pwd)":/workspace \
  -w /workspace \
  dev-container-rust
```

## Use Docker or Podman Instead of nerdctl

All Makefile targets use `CONTAINER_CLI`, which defaults to `nerdctl`. Override
it to use Docker or Podman:

```bash
make build CONTAINER_CLI=docker
make run CONTAINER_CLI=docker
```

Or use the convenience aliases:

```bash
make docker-build
make docker-run

make podman-build
make podman-run
```

Podman rootless uses `--userns=keep-id` to map the host user directly into the
container without needing the `HOST_*` environment variables or entrypoint
adaptation. Podman requires `crun` and `fuse-overlayfs`. The `--userns=keep-id`
flag requires kernel support for unprivileged private mounts (see User Guide
for details and known VM limitations).

## Housekeeping

Remove build artifacts (saved images, source archives):

```bash
make clean
```

Create a compressed source archive from the current HEAD:

```bash
make compress
```

## Deployment Environments

This image supports three deployment environments with a single build.

### Local Development (nerdctl rootless)

This is the primary workflow. `make run` passes the host identity and mounts
the current directory:

```bash
cd ~/projects/my_rust_app
make run
```

The entrypoint sets up the home directory layout to match your host identity.
In rootless mode, the process stays as container UID 0 (which maps to the host
user via the user namespace) for bind-mount correctness. This is safe — no
privilege escalation is possible.

### CI / Docker Rootful

The image runs as the fallback non-root user (`dev:1000:1000`) by default when
no `HOST_*` environment variables are passed. GitHub Actions workflows build
and publish the image using Docker.

### Kubernetes

The image is compatible with Kubernetes out of the box. Source code is
provisioned via PersistentVolumeClaims or init containers (e.g., git-sync),
not bind mounts.

Example pod spec:

```yaml
securityContext:
  runAsUser: 1000
  runAsGroup: 1000
  fsGroup: 1000
  runAsNonRoot: true
containers:
  - name: rust-dev
    image: ghcr.io/abitofhelp/dev-container-rust:latest
    workingDir: /workspace
    volumeMounts:
      - name: source
        mountPath: /workspace
volumes:
  - name: source
    persistentVolumeClaim:
      claimName: rust-source
```

`fsGroup: 1000` ensures the volume is writable by the container user.
Kubernetes manifests and Helm charts are not included in this repository.
Teams should create these per their cluster policies.

## Rootless Security

In rootless container runtimes (nerdctl/containerd rootless, Podman rootless),
the container runs inside a user namespace where container UID 0 maps to the
unprivileged host user. The process cannot escalate beyond the host user's
privileges. The entrypoint script detects this and avoids dropping privileges,
because doing so would map the process to a subordinate UID that cannot access
bind-mounted host files.

| Runtime          | Container UID 0 is...  | Bind mount access via...  | Security boundary      |
|------------------|------------------------|---------------------------|------------------------|
| Docker rootful   | Real root (dangerous)  | gosu drop to HOST_UID     | Container isolation    |
| nerdctl rootless | Host user (safe)       | Stay UID 0 (= host user)  | User namespace         |
| Podman rootless  | Host user (safe)       | --userns=keep-id          | User namespace         |
| Kubernetes       | Blocked by policy      | fsGroup in pod spec       | Pod security standards |

## Version Tags

```text
ghcr.io/abitofhelp/dev-container-rust:latest
ghcr.io/abitofhelp/dev-container-rust:rust-stable
```

The included publish workflow automatically creates tags in these styles.

## GitHub Actions

This repository includes:

- `docker-build.yml` to verify the Dockerfile on every push and pull request
  (multi-arch: amd64 + arm64)
- `docker-publish.yml` to publish the image to GitHub Container Registry
  (multi-arch push to GHCR)
- automatic tagging based on Rust version
- all actions pinned by SHA digest for supply-chain security

## Repository Layout

```text
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
└── USER_GUIDE.md
```

## License

BSD-3-Clause — see `LICENSE`.

## AI Assistance and Authorship

This project was developed by Michael Gardner with AI assistance from Claude
(Anthropic) and GPT (OpenAI). AI tools were used for design review,
architecture decisions, and code generation. All code has been reviewed and
approved by the human author. The human maintainer holds responsibility for
all code in this repository.
