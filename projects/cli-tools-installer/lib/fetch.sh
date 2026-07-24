#!/usr/bin/env bash
# GitHub-release binary fetcher. Sourced by steps/20-binaries.sh.
# Depends on lib/common.sh (msg/warn/error, LOCAL_BIN, FORCE, DRY_RUN, have, dryrun_note).
#
# Honors GH_TOKEN / GITHUB_TOKEN to avoid the 60-req/hr unauthenticated API limit.

# fetch_github_binary <repo> <asset-grep> <mode> <name-inside-archive> <target-name>
#   mode: "direct" (raw binary), "zip", or any tar flag string (e.g. xz, xJ, xj, z).
# Returns 0 on success, 1 on any failure (so callers can chain `|| fallback`).
fetch_github_binary() {
    local repo="$1" pat="$2" mode="$3" bin="$4" target="$5"
    local dest="$LOCAL_BIN/$target"

    if [ "$FORCE" != 1 ] && [ -x "$dest" ]; then
        msg "$target already present ($dest) — skipping (use --force to refresh)"
        return 0
    fi
    if [ "$DRY_RUN" = 1 ]; then
        dryrun_note "would fetch $target from $repo -> $dest"
        return 0
    fi
    have curl || { error "curl is required for $target"; return 1; }

    local -a auth=()
    local tok="${GH_TOKEN:-${GITHUB_TOKEN:-}}"
    [ -n "$tok" ] && auth=(-H "Authorization: Bearer $tok")

    msg "fetching $target from $repo ..."
    local url
    url=$(curl -fsSL "${auth[@]}" "https://api.github.com/repos/$repo/releases/latest" 2>/dev/null \
          | grep browser_download_url | grep -E "$pat" | grep -v sha256 | cut -d'"' -f4 | head -1)
    if [ -z "$url" ]; then
        warn "no release asset matching '$pat' for $repo"
        return 1
    fi

    install -d "$LOCAL_BIN"
    local tmp rc=0
    tmp=$(mktemp -d)
    case "$mode" in
        direct)
            if curl -fsSL "${auth[@]}" -o "$dest" "$url"; then chmod 0755 "$dest"; else rc=1; fi
            ;;
        zip)
            if curl -fsSL "${auth[@]}" -o "$tmp/a.zip" "$url" && have unzip && unzip -o "$tmp/a.zip" -d "$tmp" >/dev/null 2>&1; then
                local f; f=$(find "$tmp" -type f -name "$bin" | head -1)
                if [ -n "$f" ]; then install -m0755 "$f" "$dest"; else warn "$bin not found in zip"; rc=1; fi
            else
                have unzip || warn "unzip not installed (needed for $target)"
                rc=1
            fi
            ;;
        *)  # tar: pass mode straight through as the tar flag(s)
            if curl -fsSL "${auth[@]}" "$url" | tar "$mode" -C "$tmp" 2>/dev/null; then
                local f; f=$(find "$tmp" -type f -name "$bin" | head -1)
                if [ -n "$f" ]; then install -m0755 "$f" "$dest"; else warn "$bin not found in tarball"; rc=1; fi
            else
                rc=1
            fi
            ;;
    esac
    rm -rf "$tmp"

    if [ "$rc" -eq 0 ] && [ -x "$dest" ]; then
        msg "installed $target -> $dest"
        return 0
    fi
    warn "failed to install $target from $repo"
    return 1
}
