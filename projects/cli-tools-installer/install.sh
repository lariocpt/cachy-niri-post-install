#!/usr/bin/env bash
# cli-tools-installer — cross-distro (Fedora + Arch/CachyOS) installer for the
# niricritty CLI/terminal toolset: ghostty (+ changing colors), yazi (+ image
# rendering), and command-line viewers for markdown / Excel / Word.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STEPS="$ROOT/steps"
# shellcheck source=lib/common.sh
. "$ROOT/lib/common.sh"

chmod +x "$STEPS"/*.sh 2>/dev/null || true

usage() {
    cat <<'EOF'
cli-tools-installer

Usage: ./install.sh [action] [options]

Actions (no action => interactive menu):
  --all                 packages -> binaries -> configs (full install)
  --packages            native distro packages only (uses sudo)
  --binaries            GitHub-release fallback binaries only (~/.local/bin)
  --configs             color-ghostty + shell hook + yazi base config only

Options:
  --distro fedora|arch  override auto-detection (default: read /etc/os-release)
  --force               re-download / overwrite even if already present
  --dry-run             print what would happen; change nothing
  -h, --help            show this help

Companion: yazi-opener-config (Rust app) owns yazi's open-with associations.
EOF
}

ACTION=""
DISTRO_OVERRIDE="${DISTRO_OVERRIDE:-}"

while [ "$#" -gt 0 ]; do
    case "$1" in
        --all|--packages|--binaries|--configs)
            if [ -n "$ACTION" ]; then die "only one action at a time (got --$ACTION and $1)"; fi
            ACTION="${1#--}"
            ;;
        --distro)
            shift; DISTRO_OVERRIDE="${1:-}"
            [ -n "$DISTRO_OVERRIDE" ] || die "--distro needs an argument (fedora|arch)"
            ;;
        --distro=*) DISTRO_OVERRIDE="${1#*=}" ;;
        --force)    FORCE=1 ;;
        --dry-run)  DRY_RUN=1 ;;
        -h|--help)  usage; exit 0 ;;
        *)          die "unknown argument: $1 (see --help)" ;;
    esac
    shift
done

# Validate override early.
case "$DISTRO_OVERRIDE" in
    ""|fedora|arch) ;;
    *) die "--distro must be 'fedora' or 'arch' (got '$DISTRO_OVERRIDE')" ;;
esac

export DRY_RUN FORCE DISTRO_OVERRIDE
detect_distro
require_supported_distro

run_packages() {
    if [ "$DRY_RUN" = 1 ]; then
        "$STEPS/10-packages.sh"
    else
        msg "system packages require root — invoking sudo ..."
        sudo env DRY_RUN="$DRY_RUN" FORCE="$FORCE" DISTRO_OVERRIDE="$DISTRO_OVERRIDE" "$STEPS/10-packages.sh"
    fi
}
run_binaries() { "$STEPS/20-binaries.sh"; }
run_configs()  { "$STEPS/30-configs.sh"; }

footer() {
    printf '\n%sAll done.%s\n' "$GREEN" "$RESET"
    if ! local_bin_on_path; then
        printf '  Note: %s is not on PATH yet — restart your shell / re-login.\n' "$LOCAL_BIN"
    fi
    printf '  Tip: run yazi inside ghostty (not tmux) for inline image previews.\n'
    printf '  For open-with associations, install the companion: yazi-opener-config.\n'
}

do_full() { run_packages; run_binaries; run_configs; footer; }

menu() {
    clear 2>/dev/null || true
    printf '%s%s== cli-tools-installer ==%s\n' "$BOLD" "$CYAN" "$RESET"
    distro_banner
    local_bin_on_path || warn "$LOCAL_BIN is not on PATH (the configs step will add it)"
    printf '\n  [1] Full install (packages -> binaries -> configs)\n'
    printf '  [2] Native packages only (sudo)\n'
    printf '  [3] GitHub-binary tools only (~/.local/bin)\n'
    printf '  [4] Configs only (color-ghostty + shell hook + yazi base)\n'
    printf '  [5] Exit\n\n'
    local choice; read -r -p "  Choose [1-5]: " choice
    printf '\n'
    case "$choice" in
        1) do_full ;;
        2) run_packages ;;
        3) run_binaries ;;
        4) run_configs; footer ;;
        5) exit 0 ;;
        *) warn "invalid choice: $choice"; sleep 1 2>/dev/null || true; menu ;;
    esac
}

case "$ACTION" in
    all)      do_full ;;
    packages) run_packages ;;
    binaries) run_binaries ;;
    configs)  run_configs; footer ;;
    "")       menu ;;
esac
