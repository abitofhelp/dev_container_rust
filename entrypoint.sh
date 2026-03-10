#!/bin/bash
# ============================================================================
# entrypoint.sh
# ============================================================================
# Copyright (c) 2025 Michael Gardner, A Bit of Help, Inc.
# SPDX-License-Identifier: BSD-3-Clause
# See LICENSE file in the project root.
# ============================================================================
#
# Runtime-adaptive entrypoint for the Rust development container.
#
# This script adapts the in-container user identity at startup based on
# environment variables passed from the host:
#
#   HOST_USER  — desired username  (default: dev)
#   HOST_UID   — desired UID       (default: 1000)
#   HOST_GID   — desired GID       (default: HOST_UID)
#
# In rootful runtimes (Docker), the script creates or adapts the user and
# drops privileges via gosu.  In rootless runtimes (nerdctl/containerd
# rootless), the script stays as container UID 0 — which maps to the
# unprivileged host user via the user namespace — because dropping to
# HOST_UID would map to a subordinate UID that cannot access bind-mounted
# host files.
#
# ============================================================================

set -euo pipefail

# ----------------------------------------------------------------------------
# Defaults
# ----------------------------------------------------------------------------
FALLBACK_USER="dev"
FALLBACK_HOME="/home/${FALLBACK_USER}"
DEFAULT_SHELL="/usr/bin/zsh"

# ----------------------------------------------------------------------------
# Helpers
# ----------------------------------------------------------------------------
log_info() {
    echo "[entrypoint] $*" >&2
}

log_warn() {
    echo "[entrypoint] Warning: $*" >&2
}

log_error() {
    echo "[entrypoint] Error: $*" >&2
}

# ----------------------------------------------------------------------------
# Container detection markers — exported so .zshrc can use them directly.
# ----------------------------------------------------------------------------
export IN_CONTAINER=1

# ----------------------------------------------------------------------------
# Rootless detection
# ----------------------------------------------------------------------------
is_rootless() {
    if [ -f /proc/self/uid_map ]; then
        # In rootless mode, container UID 0 maps to a non-zero host UID.
        # The uid_map line for UID 0 looks like: "0  <host_uid>  1"
        local host_uid
        host_uid=$(awk '$1 == 0 { print $2 }' /proc/self/uid_map)
        [ "$host_uid" != "0" ]
    else
        return 1
    fi
}

if is_rootless; then
    export CONTAINER_RUNTIME="rootless"
else
    export CONTAINER_RUNTIME="docker"
fi

# ----------------------------------------------------------------------------
# If not running as root, there is nothing to adapt.  This happens when
# Kubernetes starts the container with a securityContext that sets
# runAsUser to a non-zero UID.  Just exec the CMD.
# ----------------------------------------------------------------------------
if [ "$(id -u)" != "0" ]; then
    export DISPLAY_USER="${HOST_USER:-$(whoami)}"
    exec "$@"
fi

# ----------------------------------------------------------------------------
# Resolve host identity from environment (with defaults).
# ----------------------------------------------------------------------------
HOST_UID="${HOST_UID:-1000}"
HOST_USER="${HOST_USER:-${FALLBACK_USER}}"
HOST_GID="${HOST_GID:-${HOST_UID}}"
TARGET_HOME="/home/${HOST_USER}"

# ----------------------------------------------------------------------------
# Input validation
# ----------------------------------------------------------------------------
validate_inputs() {
    if ! [[ "$HOST_UID" =~ ^[0-9]+$ ]]; then
        log_error "HOST_UID '${HOST_UID}' is not a valid numeric UID."
        return 1
    fi
    if [ "$HOST_UID" = "0" ]; then
        log_error "HOST_UID=0 is not allowed. The container's root account must not be modified."
        return 1
    fi
    if ! [[ "$HOST_GID" =~ ^[0-9]+$ ]]; then
        log_error "HOST_GID '${HOST_GID}' is not a valid numeric GID."
        return 1
    fi
    if ! [[ "$HOST_USER" =~ ^[a-z_][a-z0-9_-]*$ ]]; then
        log_error "HOST_USER '${HOST_USER}' is not a valid username."
        return 1
    fi
    if [ "$HOST_USER" = "root" ]; then
        log_error "HOST_USER=root is not allowed. The container's root account must not be modified."
        return 1
    fi
}

# ----------------------------------------------------------------------------
# Create or adapt group
# ----------------------------------------------------------------------------
create_group() {
    if getent group "${HOST_GID}" >/dev/null 2>&1; then
        return 0
    fi
    if ! groupadd --gid "${HOST_GID}" -K GID_MIN=100 -K GID_MAX=65534 "${HOST_USER}"; then
        log_error "Failed to create group '${HOST_USER}' with GID ${HOST_GID}."
        return 1
    fi
}

# ----------------------------------------------------------------------------
# Create or adapt user
# ----------------------------------------------------------------------------
create_user() {
    if id -u "${HOST_USER}" >/dev/null 2>&1; then
        # User exists by name — adjust UID/GID if needed.
        if ! usermod --uid "${HOST_UID}" --gid "${HOST_GID}" \
                --home "${TARGET_HOME}" --shell "${DEFAULT_SHELL}" \
                "${HOST_USER}"; then
            log_error "Failed to modify existing user '${HOST_USER}'."
            return 1
        fi
    elif getent passwd "${HOST_UID}" >/dev/null 2>&1; then
        # A different user owns this UID — rename it.
        local existing
        existing=$(getent passwd "${HOST_UID}" | cut -d: -f1)
        if ! usermod --login "${HOST_USER}" --home "${TARGET_HOME}" --move-home \
                --gid "${HOST_GID}" --shell "${DEFAULT_SHELL}" \
                "${existing}"; then
            log_error "Failed to rename user '${existing}' to '${HOST_USER}'."
            return 1
        fi
    else
        # No conflict — create fresh.
        if ! useradd --uid "${HOST_UID}" --gid "${HOST_GID}" \
                -K UID_MIN=100 -K UID_MAX=65534 \
                -m -s "${DEFAULT_SHELL}" "${HOST_USER}"; then
            log_error "Failed to create user '${HOST_USER}' (${HOST_UID}:${HOST_GID})."
            return 1
        fi
    fi
}

# ----------------------------------------------------------------------------
# Set up home directory
# ----------------------------------------------------------------------------
setup_home() {
    mkdir -p "${TARGET_HOME}" || return 1

    # Copy default .zshrc if the target home does not have one.
    if [ ! -f "${TARGET_HOME}/.zshrc" ] && [ -f "${FALLBACK_HOME}/.zshrc" ]; then
        cp "${FALLBACK_HOME}/.zshrc" "${TARGET_HOME}/.zshrc"
    fi

    # Ensure expected directories exist.
    mkdir -p "${TARGET_HOME}/.local/bin"

    # Non-fatal: some files may be on read-only mounts.
    if ! chown -R "${HOST_UID}:${HOST_GID}" "${TARGET_HOME}" 2>/dev/null; then
        log_warn "Could not chown all files in ${TARGET_HOME}."
    fi
}

# ----------------------------------------------------------------------------
# Attempt user adaptation
# ----------------------------------------------------------------------------
adapt_user() {
    validate_inputs || return 1
    create_group || return 1
    create_user || return 1
    setup_home || return 1
}

# ----------------------------------------------------------------------------
# Deterministic fallback: rootless stays UID 0, rootful drops to dev.
# ----------------------------------------------------------------------------
run_fallback() {
    log_warn "User adaptation failed. Falling back to ${FALLBACK_USER}."
    export DISPLAY_USER="${FALLBACK_USER}"
    if is_rootless; then
        export HOME="${FALLBACK_HOME}"
        exec "$@"
    else
        export HOME="${FALLBACK_HOME}"
        exec gosu "${FALLBACK_USER}" "$@"
    fi
}

# ----------------------------------------------------------------------------
# Main
# ----------------------------------------------------------------------------
if ! adapt_user; then
    run_fallback "$@"
fi

export DISPLAY_USER="${HOST_USER}"

if is_rootless; then
    # Container UID 0 == host user.  Dropping to HOST_UID would map to a
    # subordinate UID and break bind-mount access.  Stay as UID 0 but use
    # the adapted user's home directory for shell configuration.
    export HOME="${TARGET_HOME}"
    exec "$@"
else
    # Rootful runtime.  Drop privileges to the real user.
    export HOME="${TARGET_HOME}"
    exec gosu "${HOST_USER}" "$@"
fi
