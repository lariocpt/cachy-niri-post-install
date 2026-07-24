#!/usr/bin/env bash
# Shared helpers for cli-tools-installer. Sourced by install.sh and steps/*.sh.
# Defines functions + variables only; running anything is the caller's job.

# ---- colors (disabled when stdout is not a tty) ----
if [ -t 1 ]; then
    RED=$'\033[0;31m'; GREEN=$'\033[0;32m'; YELLOW=$'\033[0;33m'
    BLUE=$'\033[0;34m'; MAGENTA=$'\033[0;35m'; CYAN=$'\033[0;36m'
    BOLD=$'\033[1m'; RESET=$'\033[0m'
else
    RED=''; GREEN=''; YELLOW=''; BLUE=''; MAGENTA=''; CYAN=''; BOLD=''; RESET=''
fi

# ---- logging ----
msg()   { printf '%s[cli-tools]%s %s\n' "$GREEN" "$RESET" "$*"; }
warn()  { printf '%s[warn]%s %s\n' "$YELLOW" "$RESET" "$*" >&2; }
error() { printf '%s[error]%s %s\n' "$RED" "$RESET" "$*" >&2; }
die()   { error "$*"; exit 1; }
have()  { command -v "$1" >/dev/null 2>&1; }

# ---- runtime switches (exported by install.sh; default off) ----
DRY_RUN="${DRY_RUN:-0}"
FORCE="${FORCE:-0}"
LOCAL_BIN="${HOME}/.local/bin"

dryrun_note() { printf '%s[dry-run]%s %s\n' "$CYAN" "$RESET" "$*"; }

# ---- distro detection -------------------------------------------------------
# Sets DISTRO (fedora|arch|unknown), PKG (dnf|dnf5|pacman|unknown), DISTRO_ID,
# DISTRO_PRETTY, IS_CACHYOS. Keys off /etc/os-release ID/ID_LIKE rather than
# `command -v`, because pacman/dnf can both be present on a host (e.g. a Fedora
# box with an AUR-ish setup). An explicit DISTRO_OVERRIDE (install.sh --distro)
# always wins.
detect_distro() {
    DISTRO=unknown; PKG=unknown; DISTRO_ID=unknown; DISTRO_PRETTY=unknown; IS_CACHYOS=0

    if [ -n "${DISTRO_OVERRIDE:-}" ]; then
        DISTRO="$DISTRO_OVERRIDE"; DISTRO_ID="$DISTRO_OVERRIDE"; DISTRO_PRETTY="$DISTRO_OVERRIDE (forced)"
    elif [ -r /etc/os-release ]; then
        local ID='' ID_LIKE='' PRETTY_NAME=''
        # shellcheck disable=SC1091
        . /etc/os-release
        DISTRO_ID="${ID:-unknown}"; DISTRO_PRETTY="${PRETTY_NAME:-$DISTRO_ID}"
        [ "$DISTRO_ID" = "cachyos" ] && IS_CACHYOS=1
        case "$DISTRO_ID" in
            fedora|rhel|centos|rocky|almalinux)            DISTRO=fedora ;;
            arch|cachyos|endeavouros|manjaro|garuda|artix) DISTRO=arch ;;
            *)
                case " ${ID_LIKE:-} " in
                    *arch*)            DISTRO=arch ;;
                    *fedora*|*rhel*)   DISTRO=fedora ;;
                    *)                 DISTRO=unknown ;;
                esac
                ;;
        esac
    fi

    case "$DISTRO" in
        fedora) if have dnf5; then PKG=dnf5; else PKG=dnf; fi ;;
        arch)   PKG=pacman ;;
        *)      PKG=unknown ;;
    esac
}

require_supported_distro() {
    if [ "$DISTRO" = unknown ] || [ "$PKG" = unknown ]; then
        die "could not detect a supported distro (got '${DISTRO_ID:-?}'). Re-run with: --distro fedora|arch"
    fi
}

distro_banner() {
    local extra=''
    [ "${IS_CACHYOS:-0}" = 1 ] && extra=" ${CYAN}(CachyOS — pacman will pull its optimized builds)${RESET}"
    msg "Detected: ${BOLD}${DISTRO_PRETTY}${RESET}  →  package manager: ${BOLD}${PKG}${RESET}${extra}"
}

# ---- backups ----------------------------------------------------------------
# Timestamped backup of a file/dir (epoch suffix; no external date-format deps).
backup_path() {
    local p="$1"
    [ -e "$p" ] || return 0
    local bak="$p.bak-$(date +%s 2>/dev/null || echo backup)"
    if [ "$DRY_RUN" = 1 ]; then dryrun_note "would back up $p -> $bak"; return 0; fi
    cp -a "$p" "$bak" && msg "backed up $(basename "$p") -> $(basename "$bak")"
}

# One pristine backup of an rc file, taken before the first guarded block we add to it.
# Idempotent: once any cli-tools-installer block is present, it won't re-snapshot.
backup_rc_once() {
    local rc="$1"
    if [ -f "$rc" ] && ! grep -q 'cli-tools-installer:' "$rc" 2>/dev/null; then
        backup_path "$rc"
    fi
}

# ---- idempotent guarded rc-block append -------------------------------------
# append_sentinel_block <file> <tag> <body...>
# Appends a block delimited by '# >>> cli-tools-installer: <tag> >>>' markers, but
# only if a block with that tag is not already present. Creates <file> if missing.
append_sentinel_block() {
    local file="$1" tag="$2"; shift 2
    local body="$*"
    local begin="# >>> cli-tools-installer: ${tag} >>>"
    local end="# <<< cli-tools-installer: ${tag} <<<"

    if [ -f "$file" ] && grep -qF "$begin" "$file" 2>/dev/null; then
        msg "$(basename "$file") already has the '${tag}' block — skipping"
        return 0
    fi
    if [ "$DRY_RUN" = 1 ]; then
        dryrun_note "would append '${tag}' block to ${file}"
        return 0
    fi
    # NOTE: backup is the caller's responsibility (one pristine snapshot per file per
    # run); backing up here would re-snapshot an already-modified file on later blocks.
    {
        printf '\n%s\n' "$begin"
        printf '%s\n' "$body"
        printf '%s\n' "$end"
    } >> "$file"
    msg "added '${tag}' block to $(basename "$file")"
}

# ---- PATH check -------------------------------------------------------------
local_bin_on_path() {
    case ":${PATH}:" in *":${LOCAL_BIN}:"*) return 0 ;; *) return 1 ;; esac
}
