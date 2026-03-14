# syntax=docker/dockerfile:1.7
# ============================================================================
# Dockerfile
# ============================================================================
# Copyright (c) 2025 Michael Gardner, A Bit of Help, Inc.
# SPDX-License-Identifier: BSD-3-Clause
# See LICENSE file in the project root.
# ============================================================================
#
# Rust Development Container
#
# Repository: dev_container_rust
# Docker Image: ghcr.io/abitofhelp/dev-container-rust
#
# This Dockerfile uses Ubuntu 24.04 as the base image and adds:
#   - Rust stable toolchain via rustup (rustc, cargo, rustfmt, clippy,
#     rust-analyzer, llvm-tools-preview)
#   - Embedded bare-metal targets (5 thumbv7/v6/v8m targets)
#   - ARM Cortex-A Linux cross-compilation target
#   - cargo-binstall for fast binary installs
#   - probe-rs for embedded flashing and debugging
#   - cargo-generate, cargo-expand, sccache
#   - mold fast linker
#
# Single image only. Ubuntu 24.04's apt Rust is 1.75, far behind stable
# 1.85+. The supply-chain-auditability argument for a system-only image
# does not hold when the language version gap is this large. Rustup is
# the standard Rust installation method.
#
# Purpose
# -------
# Reproducible development environment for:
#   - Desktop Rust development (stable toolchain)
#   - Embedded Rust development (ARM Cortex-M bare-metal, ARM Cortex-A Linux)
#   - Build tools: cargo, mold linker, sccache (opt-in)
#   - Static analysis: clippy, rustfmt
#   - Python 3 + venv
#   - Zsh interactive shell
#
# Supported architectures: linux/amd64, linux/arm64 (Apple Silicon).
#
# Designed for nerdctl + containerd (rootless).
#
# Files expected in the build context:
# - Dockerfile
# - .dockerignore
# - .zshrc
# - entrypoint.sh
#
# Build example:
# nerdctl build -t dev-container-rust .
#
# Run example:
# nerdctl run -it --rm \
#   -e HOST_UID=$(id -u) \
#   -e HOST_GID=$(id -g) \
#   -e HOST_USER=$(whoami) \
#   -v "$(pwd)":/workspace \
#   -w /workspace \
#   dev-container-rust
#
# Notes
# -----
# - User identity is adapted at runtime by entrypoint.sh, not baked in at
#   build time. The build-time user (dev:1000:1000) is a fallback for CI
#   and Kubernetes environments where no HOST_* variables are passed.
# - In rootless runtimes, container UID 0 maps to the host user via the
#   user namespace. The entrypoint detects this and stays as UID 0 rather
#   than dropping privileges, which would break bind-mount access.
# - In rootful runtimes, the entrypoint drops to the adapted user via gosu.
# - Rust uses the same compiler for desktop and embedded development — you
#   just add cross-compilation targets via `rustup target add`. No separate
#   cross-compiler (like arm-none-eabi-gcc) is needed for bare-metal targets.
#
# ============================================================================
# Pinned by digest for reproducibility. Update periodically:
#   nerdctl pull ubuntu:24.04
#   nerdctl image inspect ubuntu:24.04 | grep -A1 RepoDigests
FROM ubuntu:24.04@sha256:d1e2e92c075e5ca139d51a140fff46f84315c0fdce203eab2807c7e495eff4f9

# ----------------------------------------------------------------------------
# Build arguments (alphabetized)
# ----------------------------------------------------------------------------
ARG DEBIAN_FRONTEND=noninteractive
ARG USER_GID=1000
ARG USERNAME=dev
ARG USER_UID=1000

# ----------------------------------------------------------------------------
# Environment variables (alphabetized)
# ----------------------------------------------------------------------------
ENV CARGO_HOME=/opt/cargo \
    HOME=/home/${USERNAME} \
    LANG=en_US.UTF-8 \
    LANGUAGE=en_US:en \
    LC_ALL=en_US.UTF-8 \
    PATH="/opt/cargo/bin:/home/${USERNAME}/.local/bin:/usr/local/bin:${PATH}" \
    RUSTUP_HOME=/opt/rustup \
    SHELL=/usr/bin/zsh \
    TERM=xterm-256color \
    TZ=UTC

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# ----------------------------------------------------------------------------
# Base packages (alphabetized)
# ----------------------------------------------------------------------------
RUN apt-get update && apt-get install -y --no-install-recommends \
    # ------------------------------------------------------------------
    # Build essentials (for C deps like openssl-sys, ring, etc.)
    # ------------------------------------------------------------------
    build-essential \
    libssl-dev \
    pkg-config \
    # ------------------------------------------------------------------
    # Debuggers
    # ------------------------------------------------------------------
    gdb \
    lldb \
    valgrind \
    # ------------------------------------------------------------------
    # Embedded: ARM Cortex-A Linux cross-compiler (STM32MP1)
    # ------------------------------------------------------------------
    gcc-arm-linux-gnueabihf \
    libc6-dev-armhf-cross \
    # ------------------------------------------------------------------
    # Embedded: hardware debug tools
    # ------------------------------------------------------------------
    gdb-multiarch \
    # ------------------------------------------------------------------
    # Fast linker
    # ------------------------------------------------------------------
    mold \
    # ------------------------------------------------------------------
    # General development tools
    # ------------------------------------------------------------------
    bzip2 \
    ca-certificates \
    curl \
    fd-find \
    file \
    fzf \
    git \
    gosu \
    jq \
    less \
    locales \
    lsof \
    make \
    nano \
    neovim \
    openssh-client \
    patch \
    procps \
    python3 \
    python3-dev \
    python3-pip \
    python3-venv \
    ripgrep \
    rsync \
    strace \
    sudo \
    tzdata \
    unzip \
    vim \
    wget \
    xz-utils \
    zip \
    zsh \
    zsh-autosuggestions \
    zsh-syntax-highlighting \
 && locale-gen en_US.UTF-8 \
 && update-locale LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 \
 && rm -rf /var/lib/apt/lists/*

# ----------------------------------------------------------------------------
# Rustup + stable toolchain
# ----------------------------------------------------------------------------
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | \
    sh -s -- -y --default-toolchain stable --profile default \
 && rustup component add rust-analyzer llvm-tools-preview \
 && chmod -R a+rX /opt/rustup /opt/cargo

# ----------------------------------------------------------------------------
# Embedded targets (installed via rustup)
# ----------------------------------------------------------------------------
RUN rustup target add \
    thumbv6m-none-eabi \
    thumbv7m-none-eabi \
    thumbv7em-none-eabi \
    thumbv7em-none-eabihf \
    thumbv8m.main-none-eabihf \
    armv7-unknown-linux-gnueabihf \
 && chmod -R a+rX /opt/rustup

# ----------------------------------------------------------------------------
# cargo-binstall (fast binary installs)
# ----------------------------------------------------------------------------
RUN curl -L --proto '=https' --tlsv1.2 -sSf \
    https://raw.githubusercontent.com/cargo-bins/cargo-binstall/main/install-from-binstall-release.sh \
    | bash \
 && chmod -R a+rX /opt/cargo

# ----------------------------------------------------------------------------
# Cargo tools (via binstall)
# ----------------------------------------------------------------------------
RUN cargo binstall -y --no-symlinks \
    probe-rs-tools \
    cargo-generate \
    cargo-expand \
    sccache \
 && chmod -R a+rX /opt/cargo

# ----------------------------------------------------------------------------
# Create developer user
# ----------------------------------------------------------------------------
RUN set -eux; \
    if ! getent group "${USER_GID}" >/dev/null; then \
        groupadd --gid "${USER_GID}" "${USERNAME}"; \
    fi; \
    if id -u "${USERNAME}" >/dev/null 2>&1; then \
        usermod --uid "${USER_UID}" --gid "${USER_GID}" --shell /usr/bin/zsh "${USERNAME}"; \
    elif getent passwd "${USER_UID}" >/dev/null; then \
        EXISTING_USER="$(getent passwd "${USER_UID}" | cut -d: -f1)"; \
        # Remove pre-existing target home (may be created by earlier ENV HOME) \
        # so that --move-home can rename the existing user's home directory. \
        rm -rf "/home/${USERNAME}"; \
        usermod --login "${USERNAME}" --home "/home/${USERNAME}" --move-home \
            --gid "${USER_GID}" --shell /usr/bin/zsh "${EXISTING_USER}"; \
    else \
        useradd --uid "${USER_UID}" --gid "${USER_GID}" -m -s /usr/bin/zsh "${USERNAME}"; \
    fi; \
    usermod -aG sudo "${USERNAME}"; \
    echo "${USERNAME} ALL=(ALL) NOPASSWD:ALL" > "/etc/sudoers.d/${USERNAME}"; \
    chmod 0440 "/etc/sudoers.d/${USERNAME}"

# ----------------------------------------------------------------------------
# License
# ----------------------------------------------------------------------------
COPY LICENSE /usr/share/doc/dev-container-rust/LICENSE
COPY README.md /usr/share/doc/dev-container-rust/README.md
COPY USER_GUIDE.md /usr/share/doc/dev-container-rust/USER_GUIDE.md

# ----------------------------------------------------------------------------
# Switch to developer user
# ----------------------------------------------------------------------------
USER ${USERNAME}
WORKDIR ${HOME}

RUN mkdir -p \
    "${HOME}/.docker/completions" \
    "${HOME}/.local/bin" \
    "${HOME}/workspace"

COPY --chown=${USER_UID}:${USER_GID} .zshrc ${HOME}/.zshrc

# ----------------------------------------------------------------------------
# Verify toolchain installation
# ----------------------------------------------------------------------------
RUN echo "" \
 && echo "=== Rust toolchain ===" \
 && rustc --version \
 && cargo --version \
 && rustfmt --version \
 && cargo clippy --version \
 && rust-analyzer --version \
 && echo "" \
 && echo "=== Embedded targets ===" \
 && rustup target list --installed \
 && echo "" \
 && echo "=== Cargo tools ===" \
 && probe-rs --version \
 && cargo-generate --version \
 && cargo-expand --version \
 && sccache --version \
 && echo "" \
 && echo "=== System tools ===" \
 && mold --version \
 && arm-linux-gnueabihf-gcc --version | head -1 \
 && gdb-multiarch --version | head -1

# ----------------------------------------------------------------------------
# Install entrypoint and set runtime defaults
# ----------------------------------------------------------------------------
USER root

COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

WORKDIR /workspace

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["/usr/bin/zsh", "-l"]
