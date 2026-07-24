#!/usr/bin/env bash
# Cross-distro package map + repo setup + batch installer.
# Sourced by steps/10-packages.sh (which runs as root). Depends on lib/common.sh.
#
# Scope = the CLI/terminal toolset only (ghostty, yazi + preview/viewer tools, core
# terminal utils). GUI apps and the niri/waybar desktop layer are deliberately absent.
#
# Tools NOT in a given distro's repos are handled by steps/20-binaries.sh as
# GitHub-release fallbacks (that step only fetches what is still missing afterwards):
#   * Fedora repos lack: yazi, starship, resvg, xan, mdfried, doxx, xleak, lazyenv, broot
#   * Arch repos lack:   xleak, lazyenv   (the rest are in extra/chaotic)

# Build tools the installer itself needs.
prereq_packages_fedora() { printf '%s\n' curl git tar unzip; }
prereq_packages_arch()   { printf '%s\n' curl git tar unzip; }

# Native CLI/terminal packages available from the distro's own repositories.
fedora_packages() {
    # Excluded (not in Fedora repos -> handled in steps/20-binaries.sh): yazi, starship,
    # resvg, broot. Also excluded: full `ffmpeg` (conflicts with the preinstalled
    # ffmpeg-free, which already provides the ffmpeg binary ffmpegthumbnailer needs).
    printf '%s\n' \
        ghostty file \
        ffmpegthumbnailer poppler-utils ImageMagick p7zip p7zip-plugins jq chafa \
        fd-find ripgrep fzf zoxide wl-clipboard less micro tree lynx rtorrent \
        zsh zsh-autosuggestions zsh-syntax-highlighting glow \
        perl-File-Compare openssl-devel
}

arch_packages() {
    printf '%s\n' \
        ghostty yazi file \
        ffmpeg ffmpegthumbnailer resvg poppler imagemagick 7zip jq chafa \
        fd ripgrep fzf zoxide broot wl-clipboard less micro tree lynx rtorrent \
        zsh zsh-autosuggestions zsh-syntax-highlighting starship glow \
        mdfried doxx xan
}

# ---- repository enablement (root) ------------------------------------------
setup_repos() {
    case "$DISTRO" in
        fedora) _setup_repos_fedora ;;
        arch)   _setup_repos_arch ;;
        *)      die "setup_repos: unsupported distro '$DISTRO'" ;;
    esac
}

_setup_repos_fedora() {
    local rel; rel="$(rpm -E %fedora 2>/dev/null || echo "")"
    msg "enabling RPM Fusion (free + nonfree) for ffmpeg/codecs ..."
    if [ "$DRY_RUN" = 1 ]; then
        dryrun_note "would enable RPM Fusion + dnf-plugins-core + ghostty COPR"
        return 0
    fi
    "$PKG" install -y \
        "https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-${rel}.noarch.rpm" \
        "https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-${rel}.noarch.rpm" \
        || warn "RPM Fusion enablement failed; ffmpeg/thumbnailer may be unavailable"

    "$PKG" install -y dnf-plugins-core || warn "dnf-plugins-core install failed (needed for COPR)"

    msg "enabling ghostty COPR ..."
    "$PKG" copr enable -y scottames/ghostty \
        || "$PKG" copr enable -y pgdev/ghostty \
        || dnf copr enable -y scottames/ghostty \
        || warn "could not enable a ghostty COPR — ghostty may fail to install (non-fatal)"
}

_setup_repos_arch() {
    msg "refreshing pacman databases ..."
    if [ "$DRY_RUN" = 1 ]; then dryrun_note "would run: pacman -Sy"; return 0; fi
    # Refresh DBs only (no -u): keeps this a tooling installer, not a system upgrade.
    # On CachyOS the optimized repos are already configured, so -S pulls optimized builds.
    pacman -Sy --noconfirm || warn "pacman -Sy failed; install may use stale databases"
}

# ---- batch install with per-package fallback (root) -------------------------
# A single unavailable package must not sink the whole batch.
install_packages() {
    [ "$#" -gt 0 ] || return 0
    case "$PKG" in
        dnf|dnf5)
            if [ "$DRY_RUN" = 1 ]; then dryrun_note "would: $PKG install -y --skip-unavailable $*"; return 0; fi
            # --skip-unavailable: a package missing from the repos is skipped, not fatal,
            # so the whole set installs in one transaction (no slow per-package retry).
            if ! "$PKG" install -y --skip-unavailable "$@"; then
                warn "batch install failed; retrying packages individually"
                local p; for p in "$@"; do "$PKG" install -y "$p" || warn "could not install: $p"; done
            fi
            ;;
        pacman)
            if [ "$DRY_RUN" = 1 ]; then dryrun_note "would: pacman -S --needed --noconfirm $*"; return 0; fi
            if ! pacman -S --needed --noconfirm "$@"; then
                warn "batch install failed; retrying packages individually"
                local p; for p in "$@"; do pacman -S --needed --noconfirm "$p" || warn "could not install: $p"; done
            fi
            ;;
        *) die "install_packages: unknown package manager '$PKG'" ;;
    esac
}

# Convenience: the native package set for the active distro.
native_packages() {
    case "$DISTRO" in
        fedora) prereq_packages_fedora; fedora_packages ;;
        arch)   prereq_packages_arch;   arch_packages ;;
        *)      die "native_packages: unsupported distro '$DISTRO'" ;;
    esac
}
