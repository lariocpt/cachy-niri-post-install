#!/usr/bin/env bash
# setup-hermes-fleet.sh — STANDALONE hermes agent fleet setup (STUB).
#
# Deliberately separate from post-install.sh (never called by it): the fleet
# currently lives on l-dev-ai and will be moved to big-cachy later. Until the
# fleet definition (images/compose) is migrated, this script only verifies the
# prerequisites that the fleet tooling (lario-fleet) depends on.
#
# lario-fleet expects docker (or podman-docker shim) containers named
# "hermes-<name>-agent" with the hermes binary at /opt/hermes/bin/hermes.
set -uo pipefail

msg() { printf '\033[1;32m==>\033[0m %s\n' "$*"; }

msg "checking prerequisites for the hermes fleet ..."
ok=1
if command -v docker >/dev/null; then
    msg "docker CLI: $(docker --version 2>/dev/null || echo present)"
else
    echo "MISSING: docker CLI (install docker or podman-docker)"; ok=0
fi
for t in lario-fleet grim slurp ghostty; do
    command -v "$t" >/dev/null && msg "$t: ok" || { echo "MISSING: $t"; ok=0; }
done

echo
if docker ps --format '{{.Names}}' 2>/dev/null | grep -q '^hermes-.*-agent$'; then
    msg "hermes agents already running:"
    docker ps --format '{{.Names}}' | grep '^hermes-.*-agent$'
else
    echo "No hermes agents running yet."
    echo
    echo "TODO (when migrating the fleet from l-dev-ai to big-cachy):"
    echo "  1. Export/pull the hermes agent images from l-dev-ai."
    echo "  2. Bring over the fleet's compose/run definitions."
    echo "  3. Start containers named hermes-<name>-agent."
    echo "  4. Test with: lario-fleet          (interactive menu)"
    echo "               Super+Shift+H         (fleet menu)"
    echo "               Super+Shift+6         (send screenshot to an agent)"
fi
[ "$ok" -eq 1 ] || exit 1
