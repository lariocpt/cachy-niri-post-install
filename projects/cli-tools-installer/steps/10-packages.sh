#!/usr/bin/env bash
# Step 10 — native packages. Runs as root (install.sh re-invokes it under sudo).
# Enables required repos, then installs the CLI/terminal toolset from the distro repos.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
. "$HERE/../lib/common.sh"
# shellcheck source=../lib/pkgmap.sh
. "$HERE/../lib/pkgmap.sh"

detect_distro
require_supported_distro
distro_banner

if [ "$DRY_RUN" != 1 ] && [ "$(id -u)" -ne 0 ]; then
    die "this step needs root. Run it through ./install.sh (it will sudo), or with sudo."
fi

setup_repos

msg "installing native CLI/terminal packages ..."
# native_packages prints one package name per line; intentional word-split into args.
# shellcheck disable=SC2046
install_packages $(native_packages)

msg "native package step complete."
