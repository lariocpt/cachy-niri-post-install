# niri-post-setup

Unified niri + Noctalia setup for lario's machines (big-cachy, cachyos-mini-mobile,
l-dev-ai). Run `post-install.sh` after a clean CachyOS (niri/noctalia edition)
install, or on an existing machine to converge it. Idempotent — rerunning is safe.

## Rollout

```bash
# On this machine:
~/Projects/personal/niri-post-setup/post-install.sh

# To another machine (passwordless SSH assumed; sudo prompts interactively there):
~/Projects/personal/niri-post-setup/deploy-to.sh cachyos-mini-mobile
ssh -t cachyos-mini-mobile '~/niri-post-setup/post-install.sh'
```

Then log out and pick the **Niri** session at the login screen. The display manager
(GDM here, SDDM on mini-mobile) and the bootloader are never touched.

## What you get

- **Noctalia shell** on niri (mini-mobile's config as the base), plus Control Center
  shortcut buttons for the capture/fleet/yazi actions below.
- **Unified shortcuts** (also in niri's hotkey overlay, `Super+Shift+/`):
  | Keys | Action |
  |---|---|
  | `Super+Shift+4` / `Super+Shift+3` | region / fullscreen screenshot (grim → swappy) |
  | `Super+Shift+5` / `Super+Ctrl+Shift+5` | toggle region / fullscreen recording (wf-recorder) |
  | `Super+Shift+6` | send a region screenshot to the Agent Fleet (`lario-fleet --vision`) |
  | `Super+Shift+H` | Agent Fleet menu (`lario-fleet --popup`) |
  | `Super+Shift+Y` | yazi in ghostty |
  | `Super+Ctrl+Shift+S` | niri-spaces menu |
- **niri-spaces** startup layout — ws 1: zenith + brave-origin; ws 2: terminal +
  firefox (`~/.config/niri-spaces/`, edit `spaces/*.space` + `autostart`).
  The bundled `niri-spaces` CLI implements the README's `load/start/menu/list`
  (the original hardcoded script is preserved as `niri-spaces.orig` in the project).
- **cli-tools-installer** (`~/Projects/personal/cli-tools-installer`) run with
  `--all`: the whole terminal toolset (yazi + previews, glow/mdfried/doxx/xan/xleak,
  fd/rg/fzf/zoxide/broot/starship, concord/siggy/slackatui, carbonyl, gitui, …)
  and the **color-ghostty** theme rotation incl. its shell hook.
- **Residual terminal apps** not covered by the installer (see `bin-sync.txt`):
  agy, endcord, termscp, marksman, micromamba, intelli-shell, splashboard, … →
  `~/.local/bin` (`cp -u`, a newer local copy is never clobbered). The binaries are
  not in git — they live in the on-disk bundle and on the NFS share:
  `/mnt/cachy-nfs/niri-post-setup/bin/` (server: `l-dev-ai:/srv/Lario.cachy-nfs`).
- **App union** of mini-mobile + l-dev-ai (repo + AUR + `cline` via npm) — see
  `packages.txt` / `packages-aur.txt`.
- **zsh + oh-my-zsh everywhere**: login shell set to zsh, omz plugins enriched to
  `(git sudo extract fzf zoxide)` (only if still the untouched default), plus
  zsh-autosuggestions / history-substring-search / syntax-highlighting from the
  Arch packages. **alacritty and the fish stack are removed** — ghostty is the
  terminal (incl. Noctalia's launcher `terminalCommand`, now `ghostty -e`).
- **Launcher icons**: mini-mobile's curated `.desktop` entries + icons deploy to
  `~/.local/share`; entries whose app isn't present on a machine are skipped.
- **micro is the default editor**: `EDITOR`/`VISUAL=micro` exported in `.zshrc` +
  `.bashrc` (guarded block), and `git config --global core.editor micro`.

## What gets installed (full application list)

Mirrors `packages.txt`, `packages-aur.txt`, `bin-sync.txt` and the
cli-tools-installer — update this section when those change.

**Desktop shell — niri + Noctalia** (repo packages):
niri, noctalia-shell, cachyos-niri-noctalia, xwayland-satellite, grim, slurp,
swappy, wf-recorder, wl-clipboard, libnotify, ghostty, foot, fuzzel, swaybg,
waybar, wdisplays, blueman.

**GUI applications** (repo packages):
brave-origin (`brave-origin-bin` — used by the ws1 startup layout), chromium,
claude-desktop, freedownloadmanager, gimp, krita, gparted,
intellij-idea-community-edition, libreoffice-fresh, onlyoffice-bin, mumble,
smplayer, thunderbird, vscodium, warpinator, flatpak (+ flathub remote).

**Terminal / CLI** (repo packages):
zsh (+ autosuggestions, syntax-highlighting, history-substring-search), 7zip,
zenith, fnm, npm, uv, rclone, opencode, ollama, yazi, jq.

**Dev tools** (repo packages):
cmake, ninja, python-pipx, terraform, vulkan-tools, vulkan-headers,
spirv-headers, python-huggingface-hub, linux-cachyos-headers.

**Virtualization / containers** (repo packages):
virtualbox (+ host-dkms), qemu-system-x86, edk2-ovmf, virtiofsd; docker +
docker-compose — or podman-compose instead if podman-docker is already present.

**Printing** (repo packages):
cups, cups-filters, cups-pdf, ghostscript, gsfonts, gutenprint, hplip,
system-config-printer, the foomatic-db set, python-pyqt5, python-reportlab.

**AUR** (via paru, which is itself installed if missing):
slack-desktop-wayland (skipped when any slack package is present), rustdesk-bin.

**npm** (user prefix `~/.local`): cline.

**cli-tools-installer `--all`** — native: file, ffmpeg, ffmpegthumbnailer,
resvg, poppler, imagemagick, chafa, fd, ripgrep, fzf, zoxide, broot, less,
micro, tree, lynx, rtorrent, starship, glow, mdfried, doxx, xan; GitHub/cargo
fallbacks when not in repos: xleak, lazyenv, gitui, concord, siggy, slackatui,
carbonyl, csvi, gittop, harlequin, croft, qo, surge, pik, herdr, sigye,
redthread, critique; plus the color-ghostty theme rotation + shell hook and
yazi base config.

**Bundled prebuilt binaries** (`bin/` → `~/.local/bin`, newer-wins; see
`bin-sync.txt` for provenance): agy, color-kitty, croft, csv2gspread, dotstate,
eget, endcord, gfold, hl, herdr, intelli-shell, lario-fleet,
lario-gdrive-bisync, lla, llama-swap, marksman, micromamba, niricritty-record,
niri-startup-workspaces (legacy), onecli, opn, pik, qo, redthread,
secret-agent, sigye, slackatui, smartopen, splashboard, surge, termscp,
toast-linux-amd64, tuime.

## Deliberate exclusions / conflict rules

- Hardware/boot-specific: AMD ucode/graphics/ROCm, hhd (handheld daemon), GRUB/limine
  + snapper hooks, sddm. Never installed by this bundle.
- Docker: existing runtime is kept (docker → docker-compose; podman-docker →
  podman-compose); only if neither exists is docker installed.
- Slack: `slack-desktop-wayland` only when no slack package present (mini-mobile
  keeps `slack-desktop`; its extra flatpak Slack was intentionally not replicated).
- Brave: stable `brave-origin-bin` (CachyOS repo) is the one browser variant this
  bundle installs; the startup layout launches `brave-origin`. Nightly/beta
  variants are not replicated — remove a machine-local nightly manually if you
  don't want two.
- l-dev-ai's python venv shims (flask, openai, huggingface-cli stubs, …), static
  2024 ffmpeg/ffprobe (would shadow repo ffmpeg), machine-local symlinks
  (llama.cpp builds, ncl, main-model), `ghostty`/`psql` wrapper scripts, MuseScore
  AppImage, and its personal niri-spaces layouts (t2-mono-*, playground, system)
  were not replicated.
- `ollama` is installed from the repos (correct GPU support per machine), not the
  copied binary.
- **Hermes fleet**: `optional/setup-hermes-fleet.sh` (stub) — run manually when the
  fleet moves to big-cachy. post-install.sh never touches it.

## Verifying (per machine)

```bash
niri validate                             # config OK
niri-spaces list                          # main + web
cline --version && opencode --version
color-ghostty && grep '^theme =' ~/.config/ghostty/config
~/Projects/personal/cli-tools-installer/install.sh --dry-run --all   # nothing left to do
```
