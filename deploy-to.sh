#!/usr/bin/env bash
# deploy-to.sh <host> — rsync this bundle to <host>:~/niri-post-setup and print
# the command to run it there (sudo is interactive, hence ssh -t).
set -euo pipefail
[ $# -eq 1 ] || { echo "usage: $0 <ssh-host>   (e.g. $0 cachyos-mini-mobile)"; exit 1; }
HOST="$1"
BUNDLE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "==> rsyncing bundle to $HOST:~/niri-post-setup (incremental) ..."
rsync -a --info=progress2 "$BUNDLE/" "$HOST:niri-post-setup/"

cat <<EOF

Bundle deployed. Run it there with:

    ssh -t $HOST '~/niri-post-setup/post-install.sh'

EOF
