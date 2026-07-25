#!/usr/bin/env bash
# Step 20 — GitHub-release fallback binaries into ~/.local/bin. Runs as the user.
# Only fetches tools that are NOT already on PATH (the package step may have provided
# some, e.g. mdfried/doxx/xan on Arch), unless --force is given.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
. "$HERE/../lib/common.sh"
# shellcheck source=../lib/fetch.sh
. "$HERE/../lib/fetch.sh"

detect_distro
require_supported_distro

[ "$(id -u)" -eq 0 ] && warn "running as root: binaries will land in root's ~/.local/bin, not yours"

install -d "$LOCAL_BIN"

# Fetch only if missing (or --force).
need() { [ "$FORCE" = 1 ] || ! have "$1"; }

cargo_install_try() {  # <cargo install args...>
    if [ "$DRY_RUN" = 1 ]; then dryrun_note "would: cargo install $*"; return 0; fi
    have cargo || { warn "cargo not available for source fallback"; return 1; }
    msg "trying: cargo install $*"
    cargo install "$@"
}

# broot ships ONE multi-arch zip (build/<target>/broot), so extract the x86_64 linux
# binary explicitly — the generic fetcher's "first match" could grab the wrong arch.
install_broot() {
    local dest="$LOCAL_BIN/broot"
    if [ "$DRY_RUN" = 1 ]; then dryrun_note "would fetch broot (multi-arch zip) -> $dest"; return 0; fi
    have curl  || { warn "curl required for broot"; return 1; }
    have unzip || { warn "unzip required for broot (install it first)"; return 1; }
    local -a auth=(); local tok="${GH_TOKEN:-${GITHUB_TOKEN:-}}"
    [ -n "$tok" ] && auth=(-H "Authorization: Bearer $tok")
    local url
    url=$(curl -fsSL "${auth[@]}" https://api.github.com/repos/Canop/broot/releases/latest 2>/dev/null \
          | grep browser_download_url | grep -E 'broot_.*\.zip"' | cut -d'"' -f4 | head -1)
    [ -n "$url" ] || { warn "broot: no release zip found"; return 1; }
    local tmp; tmp=$(mktemp -d); local rc=0
    if curl -fsSL "${auth[@]}" -o "$tmp/broot.zip" "$url" && unzip -o "$tmp/broot.zip" -d "$tmp" >/dev/null 2>&1; then
        local f
        f=$(find "$tmp" -type f -path '*x86_64-unknown-linux-musl/broot' | head -1)
        [ -n "$f" ] || f=$(find "$tmp" -type f -path '*x86_64-linux/broot' | head -1)
        if [ -n "$f" ]; then install -m0755 "$f" "$dest"; else warn "broot: x86_64 linux binary not in zip"; rc=1; fi
    else
        rc=1
    fi
    rm -rf "$tmp"
    if [ "$rc" -eq 0 ] && [ -x "$dest" ]; then msg "installed broot -> $dest"; return 0; fi
    return 1
}

# yazi ships both `yazi` and `ya` in a per-target zip; install both.
install_yazi() {
    if [ "$DRY_RUN" = 1 ]; then dryrun_note "would fetch yazi + ya (musl zip) -> $LOCAL_BIN"; return 0; fi
    have curl  || { warn "curl required for yazi"; return 1; }
    have unzip || { warn "unzip required for yazi"; return 1; }
    local -a auth=(); local tok="${GH_TOKEN:-${GITHUB_TOKEN:-}}"
    [ -n "$tok" ] && auth=(-H "Authorization: Bearer $tok")
    local url
    url=$(curl -fsSL "${auth[@]}" https://api.github.com/repos/sxyazi/yazi/releases/latest 2>/dev/null \
          | grep browser_download_url | grep -E 'yazi-x86_64-unknown-linux-musl\.zip"' | cut -d'"' -f4 | head -1)
    [ -n "$url" ] || { warn "yazi: no musl zip asset found"; return 1; }
    local tmp; tmp=$(mktemp -d); local rc=0
    if curl -fsSL "${auth[@]}" -o "$tmp/yazi.zip" "$url" && unzip -o "$tmp/yazi.zip" -d "$tmp" >/dev/null 2>&1; then
        local y a; y=$(find "$tmp" -type f -name yazi | head -1); a=$(find "$tmp" -type f -name ya | head -1)
        if [ -n "$y" ]; then install -m0755 "$y" "$LOCAL_BIN/yazi"; else warn "yazi binary not in zip"; rc=1; fi
        [ -n "$a" ] && install -m0755 "$a" "$LOCAL_BIN/ya"
    else rc=1; fi
    rm -rf "$tmp"
    [ "$rc" -eq 0 ] && [ -x "$LOCAL_BIN/yazi" ] && { msg "installed yazi (+ya) -> $LOCAL_BIN"; return 0; }
    return 1
}

msg "fetching tools missing from the distro repos into $LOCAL_BIN (skipping any already present) ..."

# xan — CSV viewer. In Arch extra; not in Fedora repos.
if need xan; then
    fetch_github_binary medialab/xan 'x86_64-unknown-linux-(musl|gnu)\.tar\.(gz|xz)"' xz xan xan \
        || cargo_install_try xan \
        || warn "xan unavailable (fallback failed)"
fi

# mdfried — rendered markdown viewer. In Arch repos; not in Fedora.
if need mdfried; then
    fetch_github_binary benjajaja/mdfried 'mdfried.*linux.*tar\.(gz|xz)"' xz mdfried mdfried \
        || cargo_install_try --git https://github.com/benjajaja/mdfried.git \
        || warn "mdfried unavailable (fallback failed)"
fi

# doxx — Word .docx viewer. In Arch repos; not in Fedora.
if need doxx; then
    fetch_github_binary bgreenwell/doxx 'doxx.*linux.*tar\.(gz|xz)"' xz doxx doxx \
        || cargo_install_try doxx \
        || warn "doxx unavailable (fallback failed)"
fi

# xleak — Excel viewer. Not packaged on Fedora OR Arch.
if need xleak; then
    fetch_github_binary bgreenwell/xleak 'x86_64-unknown-linux-musl\.tar\.xz"' xJ xleak xleak \
        || fetch_github_binary bgreenwell/xleak 'x86_64-unknown-linux-musl\.tar\.gz"' xz xleak xleak \
        || warn "xleak unavailable (fallback failed)"
fi

# lazyenv — .env TUI. Not packaged on Fedora OR Arch.
if need lazyenv; then
    fetch_github_binary lazynop/lazyenv 'linux_amd64\.tar\.gz"' xz lazyenv lazyenv \
        || warn "lazyenv unavailable (fallback failed)"
fi

# broot — Rust tree viewer / file navigator. In Arch extra; not in Fedora repos.
if need broot; then
    install_broot \
        || cargo_install_try broot \
        || warn "broot unavailable (fallback failed)"
fi

# yazi — file manager. In Arch extra; not in Fedora repos.
if need yazi; then
    install_yazi \
        || cargo_install_try --locked yazi-fm yazi-cli \
        || warn "yazi unavailable (fallback failed)"
fi

# starship — shell prompt. In Arch extra; not in Fedora repos.
if need starship; then
    fetch_github_binary starship/starship 'starship-x86_64-unknown-linux-musl\.tar\.gz"' xz starship starship \
        || cargo_install_try starship \
        || warn "starship unavailable (fallback failed)"
fi

# resvg — SVG previewer for yazi. In Arch extra; not packaged on Fedora and has no reliable
# prebuilt binary, so it's left to the user (avoids a slow source build in this step).
if need resvg; then
    warn "resvg (yazi SVG preview) isn't packaged on Fedora — install with: cargo install resvg"
fi
# gitui — terminal UI for git
if need gitui; then
    fetch_github_binary extrawurst/gitui 'gitui-linux-x86_64\.tar\.gz"' xz gitui gitui \
        || warn "gitui unavailable (fallback failed)"
fi

# --- terminal messaging clients (TUI replacements for the GUI apps; niche, in no repo) ---
# concord -> Discord TUI
if need concord; then
    fetch_github_binary chojs23/concord 'concord-x86_64-unknown-linux-gnu\.tar\.xz"' xJ concord concord \
        || cargo_install_try --git https://github.com/chojs23/concord \
        || warn "concord unavailable (fallback failed)"
fi
# siggy -> Signal TUI
if need siggy; then
    fetch_github_binary johnsideserf/siggy 'siggy-.*x86_64-unknown-linux-gnu\.tar\.gz"' xz siggy siggy \
        || cargo_install_try --git https://github.com/johnsideserf/siggy \
        || warn "siggy unavailable (fallback failed)"
fi
# slackatui -> Slack TUI (no prebuilt release -> built from source; this is slow)
if need slackatui; then
    cargo_install_try --git https://github.com/MasonLiebe/slackatui \
        || warn "slackatui unavailable (try: cargo install --git https://github.com/MasonLiebe/slackatui)"
fi

msg "binary fallback step complete."
local_bin_on_path || warn "$LOCAL_BIN is not on PATH — run the configs step or add it yourself."
# carbonyl — terminal web browser
if need carbonyl; then
    fetch_github_binary fathyb/carbonyl 'carbonyl\.linux-amd64\.zip"' zip carbonyl carbonyl \
        || warn "carbonyl unavailable (fallback failed)"
fi

# csvi — terminal CSV editor
if need csvi; then
    fetch_github_binary hymkor/csvi 'csvi-.*-linux-amd64\.zip"' zip csvi csvi \
        || warn "csvi unavailable (fallback failed)"
fi

# gittop — terminal UI for git repo stats
if need gittop; then
    fetch_github_binary hjr265/gittop 'gittop_.*_linux_amd64\.tar\.gz"' xz gittop gittop \
        || warn "gittop unavailable (fallback failed)"
fi

# harlequin — SQL IDE (needs pipx or similar, falling back to warning if pipx isn't used here, wait, let's try pipx)
if need harlequin; then
    if have pipx; then
        if [ "$DRY_RUN" = 1 ]; then dryrun_note "would: pipx install harlequin"; else pipx install harlequin || warn "harlequin pipx install failed"; fi
    else
        warn "harlequin unavailable (pipx not installed)"
    fi
fi

# carbonyl — terminal browser
if need carbonyl; then
    if [ "$DRY_RUN" = 1 ]; then
        dryrun_note "would fetch carbonyl (linux-amd64 zip) -> $LOCAL_BIN/carbonyl"
    else
        CARBONYL_URL=$(curl -fsSL https://api.github.com/repos/fathyb/carbonyl/releases/latest | grep browser_download_url | grep 'carbonyl.linux-amd64.zip' | cut -d'"' -f4 | head -1)
        if [ -n "$CARBONYL_URL" ]; then
            TMP_CARBONYL=$(mktemp -d)
            if curl -fsSL -o "$TMP_CARBONYL/carbonyl.zip" "$CARBONYL_URL" && unzip -q "$TMP_CARBONYL/carbonyl.zip" -d "$TMP_CARBONYL"; then
                CARBONYL_EXTRACT_DIR=$(find "$TMP_CARBONYL" -maxdepth 1 -type d -name "carbonyl-*" | head -1)
                if [ -n "$CARBONYL_EXTRACT_DIR" ]; then
                    rm -rf "$HOME/.local/share/carbonyl"
                    mv "$CARBONYL_EXTRACT_DIR" "$HOME/.local/share/carbonyl"
                    ln -sf "$HOME/.local/share/carbonyl/carbonyl" "$LOCAL_BIN/carbonyl"
                    msg "installed carbonyl -> $LOCAL_BIN/carbonyl"
                else
                    warn "carbonyl unavailable (extracted dir not found)"
                fi
            else
                warn "carbonyl unavailable (download/unzip failed)"
            fi
            rm -rf "$TMP_CARBONYL"
        else
            warn "carbonyl unavailable (release asset not found)"
        fi
    fi
fi

# various Rust CLI tools from opn shortcuts — these ARE on crates.io under
# their own names (verified: croft, pik, zenith, herdr, sigye).
for t in croft pik zenith herdr sigye; do
    if need $t; then
        cargo_install_try $t || warn "$t unavailable (fallback failed)"
    fi
done

# qo, surge, redthread are custom builds NOT on crates.io — the same-name
# crates there are unrelated, name-squatted, or broken (surge 0.2.0 is a music
# daemon with yanked deps; redthread 0.0.0 is a binary-less placeholder).
# Never `cargo install` these; they come pre-seeded from the post-install
# bundle bin/ or /mnt/cachy-nfs/niri-post-setup/bin/.
for t in qo surge redthread; do
    need $t && warn "$t is a custom build (not on crates.io) — copy it from the post-install bundle bin/ or /mnt/cachy-nfs/niri-post-setup/bin/"
done
