# cli-tools-installer

Cross-distro installer for the **niricritty CLI / terminal toolset** — extracted from the
[niricritty](https://github.com/) distro so it can be run standalone on any machine.

It sets up:

- **ghostty** + its **changing-colors** rotation (a random built-in theme on each new
  interactive ghostty shell, via `color-ghostty`),
- **yazi** + **image rendering** (preview backends: imagemagick, ffmpeg, resvg, poppler,
  7zip, jq, chafa — rendered inline through ghostty's graphics protocol),
- command-line document viewers: **markdown** (`glow`, `mdfried`), **Excel** (`xleak`,
  `xan` for CSV), **Word** (`doxx`), plus the `.env` TUI (`lazyenv`),
- the core terminal utilities the niri environment uses (`fd`, `ripgrep`, `fzf`, `zoxide`,
  `broot`, `wl-clipboard`, `less`, `micro`, `zsh` + plugins, `starship`),
- terminal messaging clients (TUI, in place of the GUI apps): `concord` (Discord),
  `siggy` (Signal), `slackatui` (Slack).

GUI apps and the niri/waybar desktop layer are **out of scope** (kept minimal).

> **Companion project:** file-type *open-with* associations (what yazi does when you press
> Enter) are owned by **`yazi-opener-config`** (a Rust app). This installer only lays down
> yazi's `[mgr]` + `[preview]` sections; it never touches `[opener]`/`[open]`.

## Platforms

| Distro | Package manager | Status |
|---|---|---|
| **Fedora 44** | `dnf`/`dnf5` | **Proven** (developed + verified here) |
| **Arch / CachyOS** | `pacman` | Implemented, **unverified**. On CachyOS, `pacman` pulls its optimized (v3/v4) builds automatically. |

Detection reads `/etc/os-release` `ID`/`ID_LIKE` (not `command -v`, since a host can have
both `pacman` and `dnf`). Override with `--distro fedora|arch`.

**Fedora notes:** `yazi`, `starship`, `resvg`, `broot` and the comms TUIs aren't in Fedora
repos, so they come from the binaries step (prebuilt binaries, or `cargo` for `slackatui`
and `resvg`). Full `ffmpeg` is not installed — it conflicts with the preinstalled
`ffmpeg-free`, which already provides the `ffmpeg` binary `ffmpegthumbnailer` needs; run
`dnf swap ffmpeg-free ffmpeg --allowerasing` yourself if you want the full build. The
package step uses `--skip-unavailable`, so any package missing from your repos is skipped
rather than failing the batch.

## Usage

```bash
git clone <local path>/cli-tools-installer && cd cli-tools-installer
./install.sh            # interactive menu
```

Or non-interactively:

```bash
./install.sh --all              # packages -> binaries -> configs
./install.sh --packages         # native distro packages (uses sudo)
./install.sh --binaries         # GitHub-release fallback binaries -> ~/.local/bin
./install.sh --configs          # color-ghostty + shell hook + yazi base config
./install.sh --dry-run --all    # show everything it would do; change nothing
./install.sh --distro arch --binaries
./install.sh --force --binaries # re-download even if already present
```

Set `GH_TOKEN` (or `GITHUB_TOKEN`) to avoid GitHub's unauthenticated API rate limit when
fetching release binaries.

## How it works

| Step | Script | Privilege | What it does |
|---|---|---|---|
| Packages | `steps/10-packages.sh` | root (auto-sudo) | enables repos (Fedora: RPM Fusion + ghostty COPR), installs the native toolset; a missing package falls back to per-package install so the batch never sinks |
| Binaries | `steps/20-binaries.sh` | user | fetches tools missing from the distro repos into `~/.local/bin` (prebuilt where possible, else `cargo`). The comms TUIs `concord`/`siggy`/`slackatui` (any distro); on Fedora also `yazi`/`starship`/`broot`/`xan`/`mdfried`/`doxx`/`xleak`/`lazyenv`; on Arch only `xleak`/`lazyenv`. Skips anything already present |
| Configs | `steps/30-configs.sh` | user | installs **Oh My Zsh** (cloned; guarded activation in `~/.zshrc`, skipped if it already uses oh-my-zsh), `color-ghostty` + a guarded interactive shell hook, seeds `~/.config/ghostty/config`, writes yazi's `[mgr]`/`[preview]` |

All steps are **idempotent**: re-running skips work already done, sentinel-guarded rc blocks
are added once, and existing user files are backed up (`*.bak-<epoch>`) before modification.

### yazi.toml coordination contract

`~/.config/yazi/yazi.toml` is shared with `yazi-opener-config`:

- **this installer owns** `[mgr]` and `[preview]`,
- **`yazi-opener-config` owns** `[opener]` and `[open]`.

If the file already has `[mgr]`/`[preview]`, this installer leaves it alone. If it exists but
lacks them (e.g. the opener tool wrote first), the two sections are prepended above the
existing content so `[opener]`/`[open]` survive. Either install order is safe.

## Verify (Fedora)

```bash
./install.sh --all
# native tools
for t in yazi fd rg fzf zoxide micro glow chafa jq 7z pdftoppm resvg ffmpeg starship ghostty; do command -v "$t" || echo "MISSING $t"; done
# fallback binaries
for t in xan mdfried doxx xleak lazyenv; do command -v "$t" || echo "MISSING $t"; done
# ghostty colour rotation: open two ghostty windows, compare:
grep '^theme =' ~/.config/ghostty/config        # differs per window; ~/.cache/ghostty_theme_history grows
# yazi image preview (inside ghostty, NOT tmux):
ghostty -e yazi                                  # hover a PNG/SVG/PDF/video/json -> inline preview
# CLI viewers:
glow README.md ; mdfried README.md ; xan view -p -A some.csv ; doxx some.docx ; xleak -i some.xlsx
```

## Layout

```
install.sh            entrypoint (menu + flags + sudo orchestration)
lib/common.sh         distro detection, logging, backups, sentinel-block append
lib/fetch.sh          GitHub-release binary fetcher
lib/pkgmap.sh         cross-distro package map + repo setup + batch install
steps/10|20|30-*.sh   packages / binaries / configs
assets/               vendored color-ghostty, yazi base config, ghostty seed, shell hooks
```

## Related projects

- **yazi-opener-config** — Rust app owning yazi's open-with associations (`[opener]`/`[open]`).
- **smartopen** (`cli-rust-menu`) — a configurable "smart opener" binary; `yazi-opener-config`
  can route yazi through it (`--engine smartopen`).
- **niricritty** — the Arch distro this toolset originates from.
