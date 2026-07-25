#!/usr/bin/env bash
# post-install.sh — unified niri + noctalia setup for lario's machines.
# Run after a clean CachyOS (niri/noctalia edition) install, or on an existing
# machine to converge it. Idempotent: safe to rerun. Needs interactive sudo.
#
# What it does (in order):
#   1. repo packages (packages.txt) with docker/podman conflict handling
#   2. AUR packages (packages-aur.txt) via paru, slack conflict handling
#   3. cline CLI via npm (user prefix ~/.local)
#   4. deploy bin/ -> ~/.local/bin (cp -u, newer wins)
#   5. deploy projects/ -> ~/Projects, build nosleep, run cli-tools-installer
#      --all + niri-spaces
#   6. backup + deploy configs (niri, noctalia, niri-spaces) + splashboard
#      terminal splash (banner text prompted at the start of the run)

#   7. create standard dirs, enable cups/bluetooth, flathub remote
#   8. zsh + oh-my-zsh plugins as login shell; remove alacritty + fish stack
#   9. validate niri config, print next steps

#
# The hermes fleet is NOT set up here — see optional/setup-hermes-fleet.sh.
set -uo pipefail

BUNDLE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
msg()  { printf '\033[1;32m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33mwarning:\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31merror:\033[0m %s\n' "$*" >&2; exit 1; }

[ "$(id -u)" -ne 0 ] || die "run as your user, not root (sudo is used where needed)"
command -v pacman >/dev/null || die "pacman not found — this script is for Arch/CachyOS"

msg "requesting sudo up front ..."
sudo -v || die "sudo required"

# ------------------------------------------------ 0. per-machine questions
# Splashboard banner: the only per-machine difference in the terminal splash
# ("Cachy AI" / "Big Cachy" / "Mini Cachy"). Asked up front so the rest of the
# run is unattended. Non-interactive runs: set SPLASH_NAME=... in the env;
# otherwise the banner already configured on this machine (or "Cachy AI") is kept.
SPLASH_DEFAULT="Cachy AI"
if [ -f "$HOME/.splashboard/home.dashboard.toml" ]; then
    _cur=$(awk -F'"' '/^id = "hero"$/{h=1} h && /^format = /{print $2; exit}' \
        "$HOME/.splashboard/home.dashboard.toml")
    [ -n "$_cur" ] && SPLASH_DEFAULT="$_cur"
fi
if [ -z "${SPLASH_NAME:-}" ]; then
    if [ -t 0 ]; then
        read -r -p "Terminal splash banner for this machine [$SPLASH_DEFAULT]: " SPLASH_NAME
    fi
    SPLASH_NAME="${SPLASH_NAME:-$SPLASH_DEFAULT}"
fi
msg "splash banner: $SPLASH_NAME"

# ---------------------------------------------------------------- 1. packages
read_list() { grep -vE '^\s*(#|$)' "$1"; }

mapfile -t PKGS < <(read_list "$BUNDLE/packages.txt")

# Docker rule: never swap an existing container runtime provider.
if pacman -Q docker >/dev/null 2>&1; then
    msg "docker present -> using docker-compose (skipping podman-docker)"
    PKGS+=(docker-compose)
elif pacman -Q podman-docker >/dev/null 2>&1; then
    msg "podman-docker present -> keeping podman (podman-compose)"
    PKGS+=(podman-compose)
else
    msg "no container runtime -> installing docker + docker-compose"
    PKGS+=(docker docker-compose)
fi

# CachyOS desktop-settings packages are mutually exclusive (all provide
# cachyos-desktop-settings). Ours is cachyos-niri-noctalia; with --noconfirm the
# conflict prompt auto-answers "No" and sinks the whole batch, so remove any
# other installed provider (e.g. cachyos-gnome-settings on a GNOME install) first.
if ! pacman -Q cachyos-niri-noctalia >/dev/null 2>&1; then
    mapfile -t SETTINGS_PKGS < <(pacman -Qq | grep '^cachyos-' || true)
    if [ ${#SETTINGS_PKGS[@]} -gt 0 ]; then
        while read -r provider; do
            [ -n "$provider" ] || continue
            msg "removing $provider (conflicts with cachyos-niri-noctalia) ..."
            sudo pacman -Rns --noconfirm "$provider" || warn "could not remove $provider — cachyos-niri-noctalia will fail to install"
        done < <(pacman -Qi "${SETTINGS_PKGS[@]}" 2>/dev/null | awk '/^Name/{n=$3} /^Provides/ && /cachyos-desktop-settings/ && n!="cachyos-niri-noctalia" {print n}')
    fi
fi

# VirtualBox rule: we standardize on the dkms host modules (they rebuild for the
# cachyos kernel). virtualbox-host-modules-arch conflicts with virtualbox-host-dkms;
# with --noconfirm the "Remove virtualbox-host-modules-arch?" prompt auto-answers
# "No" and sinks the whole batch, so swap it out first. -Rdd because virtualbox
# itself depends on VIRTUALBOX-HOST-MODULES — the dkms package restores the
# provider moments later in the batch install.
if pacman -Q virtualbox-host-modules-arch >/dev/null 2>&1 \
   && ! pacman -Q virtualbox-host-dkms >/dev/null 2>&1; then
    msg "replacing virtualbox-host-modules-arch with virtualbox-host-dkms ..."
    sudo pacman -Rdd --noconfirm virtualbox-host-modules-arch \
        || warn "could not remove virtualbox-host-modules-arch — virtualbox-host-dkms will fail to install"
fi

msg "installing ${#PKGS[@]} repo packages (pacman --needed) ..."
if ! sudo pacman -S --needed --noconfirm "${PKGS[@]}"; then
    warn "batch install failed (often a transient mirror error) — retrying the batch once ..."
    sleep 5
    if ! sudo pacman -S --needed --noconfirm "${PKGS[@]}"; then
        warn "batch failed twice. If downloads were crawling, fix mirrors first:"
        warn "    sudo cachyos-rate-mirrors     # then rerun this script"
        warn "falling back to per-package install so one bad package can't sink the rest ..."
        for p in "${PKGS[@]}"; do
            sudo pacman -S --needed --noconfirm "$p" || warn "could not install: $p"
        done
    fi
fi

# ------------------------------------------------------------------- 2. AUR
if ! command -v paru >/dev/null; then
    msg "installing paru ..."
    sudo pacman -S --needed --noconfirm paru || die "paru unavailable"
fi
while IFS= read -r pkg; do
    if [ "$pkg" = "slack-desktop-wayland" ] && pacman -Qq 2>/dev/null | grep -qE '^slack-desktop'; then
        msg "a slack package is already installed — skipping $pkg"
        continue
    fi
    if pacman -Q "$pkg" >/dev/null 2>&1; then
        msg "$pkg already installed"
    else
        msg "installing (AUR): $pkg"
        paru -S --needed --noconfirm "$pkg" || warn "could not install AUR package: $pkg"
    fi
done < <(read_list "$BUNDLE/packages-aur.txt")

# ------------------------------------------------------------------ 3. cline
if ! command -v npm >/dev/null; then
    if command -v fnm >/dev/null; then
        msg "npm missing — installing node LTS via fnm ..."
        fnm install --lts && eval "$(fnm env)" || warn "fnm node install failed"
    else
        warn "npm and fnm both missing — cline skipped"
    fi
fi
if command -v npm >/dev/null; then
    npm config set prefix "$HOME/.local"
    if command -v cline >/dev/null; then
        msg "cline already installed ($(cline --version 2>/dev/null || echo '?'))"
    else
        msg "installing cline CLI (npm -g, prefix ~/.local) ..."
        npm install -g cline || warn "cline install failed"
    fi
fi

# ----------------------------------------------------------------- 4. bin
# Deploy bundled binaries BEFORE cli-tools-installer runs: its need() checks
# skip anything already on PATH, so pre-seeding avoids slow cargo builds and
# GitHub refetches of tools we already carry (croft, qo, pik, sigye, slackatui,
# herdr, redthread, surge, opn, ...).
msg "deploying bundled terminal apps -> ~/.local/bin (newer wins) ..."
mkdir -p "$HOME/.local/bin"
cp -u "$BUNDLE/bin/"* "$HOME/.local/bin/"
for f in "$BUNDLE/bin/"*; do chmod +x "$HOME/.local/bin/$(basename "$f")" 2>/dev/null || true; done
case ":$PATH:" in *":$HOME/.local/bin:"*) ;; *) export PATH="$HOME/.local/bin:$PATH" ;; esac

# -------------------------------------------------- 5. projects + cli tools
mkdir -p "$HOME/Projects/personal"
if [ ! -d "$HOME/Projects/personal/cli-tools-installer" ]; then
    msg "deploying cli-tools-installer -> ~/Projects/personal/"
    cp -r "$BUNDLE/projects/cli-tools-installer" "$HOME/Projects/personal/"
else
    msg "~/Projects/personal/cli-tools-installer already present — leaving it (git-managed)"
fi
if [ ! -d "$HOME/Projects/niri-spaces" ]; then
    msg "deploying niri-spaces -> ~/Projects/"
    cp -r "$BUNDLE/projects/niri-spaces" "$HOME/Projects/"
else
    msg "updating niri-spaces CLI + layouts in ~/Projects/niri-spaces"
    cp "$BUNDLE/projects/niri-spaces/niri-spaces" "$HOME/Projects/niri-spaces/niri-spaces"
    cp "$BUNDLE/projects/niri-spaces/install.sh"  "$HOME/Projects/niri-spaces/install.sh"
    cp "$BUNDLE/projects/niri-spaces/autostart"   "$HOME/Projects/niri-spaces/autostart"
    cp "$BUNDLE/projects/niri-spaces/spaces/"*.space "$HOME/Projects/niri-spaces/spaces/" 2>/dev/null || true
fi

# nosleep — keep-awake TUI (Rust). Prefer an existing git-managed checkout;
# otherwise deploy the bundled snapshot. Built from source (cargo is in
# packages.txt via rust); incremental, so rerunning with no changes is fast.
if [ ! -d "$HOME/Projects/personal/nosleep" ]; then
    msg "deploying nosleep -> ~/Projects/personal/"
    cp -r "$BUNDLE/projects/nosleep" "$HOME/Projects/personal/"
else
    msg "~/Projects/personal/nosleep already present — leaving it (git-managed)"
fi
# Dead rustup shims in ~/.cargo/bin (rustup present, no default toolchain)
# shadow the pacman toolchain and error out — probe for a cargo+rustc pair that
# actually runs. cargo resolves rustc via PATH, so pin RUSTC past the shims too.
CARGO=""
if cargo --version >/dev/null 2>&1 && rustc --version >/dev/null 2>&1; then
    CARGO=cargo
elif /usr/bin/cargo --version >/dev/null 2>&1 && /usr/bin/rustc --version >/dev/null 2>&1; then
    CARGO=/usr/bin/cargo
    export RUSTC=/usr/bin/rustc
fi
if [ -n "$CARGO" ]; then
    msg "building nosleep -> ~/.local/bin/nosleep ..."
    ( cd "$HOME/Projects/personal/nosleep" \
        && "$CARGO" build --release --locked \
        && install -m0755 target/release/nosleep "$HOME/.local/bin/nosleep" ) \
        || warn "nosleep build failed — build manually: cd ~/Projects/personal/nosleep && cargo build --release"
else
    warn "no working cargo on PATH — nosleep not built (install rust, then rerun)"
fi

msg "running cli-tools-installer --all (terminal toolset, color-ghostty hook) ..."
( cd "$HOME/Projects/personal/cli-tools-installer" && ./install.sh --all --distro arch ) \
    || warn "cli-tools-installer reported errors — rerun it manually: ~/Projects/personal/cli-tools-installer/install.sh --all"

# The installer's --all does not run its niri-spaces step (26 isn't wired into its
# dispatch), so wire niri-spaces up directly: symlinks the CLI into ~/.local/bin
# and seeds ~/.config/niri-spaces (our unified layouts overwrite it right after).
msg "installing niri-spaces (project install.sh) ..."
"$HOME/Projects/niri-spaces/install.sh" || warn "niri-spaces install reported errors"

# ---------------------------------------------------------------- 6. configs
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP="$HOME/.config/pre-niri-post-setup-$STAMP.tar.gz"
to_back=()
for d in niri noctalia niri-spaces; do [ -d "$HOME/.config/$d" ] && to_back+=(".config/$d"); done
if [ ${#to_back[@]} -gt 0 ]; then
    msg "backing up existing configs -> $BACKUP"
    tar czf "$BACKUP" -C "$HOME" "${to_back[@]}" || die "config backup failed — aborting before overwrite"
fi
msg "deploying unified configs (niri, noctalia, niri-spaces) ..."
mkdir -p "$HOME/.config"
rsync -a --delete "$BUNDLE/configs/niri/"        "$HOME/.config/niri/"
rsync -a --delete "$BUNDLE/configs/niri-spaces/" "$HOME/.config/niri-spaces/"
rsync -a          "$BUNDLE/configs/noctalia/"    "$HOME/.config/noctalia/"

# App-launcher desktop entries + icons (from mini-mobile's curated set); an entry
# is only installed when its Exec target exists on this machine.
msg "deploying launcher desktop entries + icons ..."
mkdir -p "$HOME/.local/share/applications"
[ -d "$BUNDLE/configs/local-share/icons" ] && rsync -a "$BUNDLE/configs/local-share/icons/" "$HOME/.local/share/icons/"
for d in "$BUNDLE/configs/local-share/applications/"*.desktop; do
    [ -f "$d" ] || continue
    execline=$(grep -m1 '^Exec=' "$d" | cut -d= -f2-)
    # Exec targets with spaces are quoted ("/path with spaces/bin" %F) — take the
    # quoted string whole; otherwise the first word.
    case $execline in
        \"*) execbin=${execline#\"}; execbin=${execbin%%\"*} ;;
        *)   execbin=${execline%% *} ;;
    esac
    if command -v "$execbin" >/dev/null 2>&1 || [ -x "$execbin" ]; then
        cp -u "$d" "$HOME/.local/share/applications/"
    else
        msg "  skipping $(basename "$d") ($execbin not present here)"
    fi
done
command -v update-desktop-database >/dev/null && update-desktop-database "$HOME/.local/share/applications" 2>/dev/null
command -v gtk-update-icon-cache >/dev/null && gtk-update-icon-cache -q -t "$HOME/.local/share/icons/hicolor" 2>/dev/null
true

# Splashboard: terminal splash — machine-name banner at home, local git info
# (branch/status + recent commits) inside repos. Identical config on every
# machine; only the banner text differs (prompted at the top of this script).
# Changed dashboards are backed up alongside as .bak-$STAMP; settings.toml is
# user preferences and only seeded when missing.
msg "deploying splashboard dashboards (banner: $SPLASH_NAME) ..."
mkdir -p "$HOME/.splashboard"
_esc=$(printf '%s' "$SPLASH_NAME" | sed 's/[&/\]/\\&/g')
for f in home.dashboard.toml project.dashboard.toml; do
    _tmp=$(mktemp)
    sed "s/@@SPLASH_NAME@@/$_esc/" "$BUNDLE/configs/splashboard/$f" > "$_tmp"
    if [ -f "$HOME/.splashboard/$f" ] && cmp -s "$_tmp" "$HOME/.splashboard/$f"; then
        rm -f "$_tmp"; continue
    fi
    [ -f "$HOME/.splashboard/$f" ] && cp -a "$HOME/.splashboard/$f" "$HOME/.splashboard/$f.bak-$STAMP"
    install -m0644 "$_tmp" "$HOME/.splashboard/$f"
    rm -f "$_tmp"
done
[ -f "$HOME/.splashboard/settings.toml" ] \
    || install -m0644 "$BUNDLE/configs/splashboard/settings.toml" "$HOME/.splashboard/settings.toml"
command -v splashboard >/dev/null \
    || warn "splashboard binary not on PATH — splash renders once bin-sync provides it"

SPMARK="# >>> splashboard >>>"
if [ -f "$HOME/.zshrc" ] && ! grep -qF "$SPMARK" "$HOME/.zshrc"; then
    msg "wiring splashboard into .zshrc ..."
    cat >> "$HOME/.zshrc" <<'SPRC'

# >>> splashboard >>>
# Splash on new shells and on cd into a project. Safe to remove.
command -v splashboard >/dev/null && eval "$(splashboard init zsh)"
# <<< splashboard <<<
SPRC
fi

# -------------------------------------------------------- 7. dirs + services
mkdir -p "$HOME/Pictures/Wallpapers" "$HOME/Pictures/Screenshots" "$HOME/Videos/Recordings"

# Keep the CachyOS Hello popup from opening at every login: a user-level
# autostart entry with Hidden=true overrides the system one in /etc/xdg/autostart.
msg "disabling cachyos-hello autostart popup ..."
mkdir -p "$HOME/.config/autostart"
hello_desktop="$HOME/.config/autostart/cachyos-hello.desktop"
if [ -f "$hello_desktop" ]; then
    grep -q '^Hidden=true' "$hello_desktop" || sed -i '/^\[Desktop Entry\]/a Hidden=true' "$hello_desktop"
else
    printf '[Desktop Entry]\nType=Application\nName=CachyOS Hello\nHidden=true\n' > "$hello_desktop"
fi

msg "enabling printing (cups) ..."
sudo systemctl enable --now cups.socket cups.service cups.path 2>/dev/null || warn "could not enable cups"
if pacman -Q bluez >/dev/null 2>&1; then
    sudo systemctl enable --now bluetooth.service 2>/dev/null || warn "could not enable bluetooth"
fi
if command -v flatpak >/dev/null; then
    flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo 2>/dev/null \
        || warn "could not add flathub remote"
fi

# --------------------------- 8. shell: zsh + oh-my-zsh, drop fish/alacritty
CURRENT_SHELL=$(getent passwd "$USER" | cut -d: -f7)
if [ "$CURRENT_SHELL" != "/usr/bin/zsh" ] && command -v zsh >/dev/null; then
    msg "setting login shell to zsh ..."
    sudo chsh -s /usr/bin/zsh "$USER" || warn "could not chsh to zsh"
fi

# Richer oh-my-zsh plugin set — only replaces the untouched omz default.
if [ -f "$HOME/.zshrc" ] && grep -q '^plugins=(git)$' "$HOME/.zshrc"; then
    msg "enriching oh-my-zsh plugins (git sudo extract fzf zoxide) ..."
    sed -i 's/^plugins=(git)$/plugins=(git sudo extract fzf zoxide)/' "$HOME/.zshrc"
fi

# Arch zsh plugin packages: autosuggestions, history-substring-search, and
# syntax highlighting (which must be sourced last).
ZMARK="# >>> niri-post-setup zsh plugins >>>"
if [ -f "$HOME/.zshrc" ] && ! grep -qF "$ZMARK" "$HOME/.zshrc"; then
    msg "wiring zsh-autosuggestions + history-substring-search + syntax-highlighting ..."
    cat >> "$HOME/.zshrc" <<'ZRC'

# >>> niri-post-setup zsh plugins >>>
[ -f /usr/share/zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh ] && \
    source /usr/share/zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh
if [ -f /usr/share/zsh/plugins/zsh-history-substring-search/zsh-history-substring-search.zsh ]; then
    source /usr/share/zsh/plugins/zsh-history-substring-search/zsh-history-substring-search.zsh
    bindkey '^[[A' history-substring-search-up
    bindkey '^[[B' history-substring-search-down
fi
[ -f /usr/share/zsh/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh ] && \
    source /usr/share/zsh/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
# <<< niri-post-setup zsh plugins <<<
ZRC
fi

# micro is the default editor everywhere, including for git.
EDMARK="# >>> niri-post-setup editor >>>"
for rc in "$HOME/.zshrc" "$HOME/.bashrc"; do
    [ -f "$rc" ] || continue
    grep -qF "$EDMARK" "$rc" && continue
    msg "setting EDITOR=micro in $(basename "$rc") ..."
    cat >> "$rc" <<'ERC'

# >>> niri-post-setup editor >>>
export EDITOR=micro
export VISUAL=micro
# <<< niri-post-setup editor <<<
ERC
done
if command -v git >/dev/null && [ "$(git config --global core.editor 2>/dev/null)" != "micro" ]; then
    msg "setting git core.editor = micro ..."
    git config --global core.editor micro
fi

# We standardize on ghostty + zsh: drop alacritty and the fish stack.
if pacman -Q alacritty >/dev/null 2>&1; then
    msg "removing alacritty ..."
    sudo pacman -Rns --noconfirm alacritty || warn "could not remove alacritty"
fi
FISH_PKGS=()
for p in cachyos-fish-config fisher fish-autopair fish-pure-prompt fish; do
    pacman -Q "$p" >/dev/null 2>&1 && FISH_PKGS+=("$p")
done
if [ ${#FISH_PKGS[@]} -gt 0 ]; then
    if [ "$(getent passwd "$USER" | cut -d: -f7)" = "/usr/bin/zsh" ]; then
        msg "removing fish stack: ${FISH_PKGS[*]} ..."
        sudo pacman -Rns --noconfirm "${FISH_PKGS[@]}" || warn "could not remove fish packages"
    else
        warn "login shell is not zsh — keeping fish so you aren't locked out; rerun after fixing chsh"
    fi
fi

# ---------------------------------------------------------------- 9. verify
msg "validating niri config ..."
niri validate -c "$HOME/.config/niri/config.kdl" || die "niri config INVALID — restore from $BACKUP"

msg "running color-ghostty once (theme rotation sanity check) ..."
"$HOME/.local/bin/color-ghostty" && grep -m1 '^theme =' "$HOME/.config/ghostty/config" || warn "color-ghostty check failed"

cat <<'EOF'

──────────────────────────────────────────────────────────────
 Done. Next steps:
   1. Log out, and pick the "Niri" session at the login screen.
      (Noctalia + niri-spaces workspaces start automatically.)
   2. Key shortcuts:  Super+Shift+4/3 screenshots   Super+Shift+5 record
                      Super+Shift+6 fleet vision    Super+Shift+H fleet menu
                      Super+Shift+Y yazi            Super+Ctrl+Shift+S spaces menu
      (also as buttons in Noctalia's Control Center shortcut row)
   3. Hermes fleet: run optional/setup-hermes-fleet.sh when ready (separate, never automatic).
──────────────────────────────────────────────────────────────
EOF
