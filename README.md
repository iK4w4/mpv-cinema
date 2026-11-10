# mpv config

A fast, minimal mpv setup for Windows: uosc interface, a speech
waveform track above the timeline, and upscaler profiles for
anime and HD video. No shuffle or loop controls — this is a
video player, not a music player.

## Install

Requires mpv. The [Shinchiro Windows build](https://github.com/shinchiro/mpv-winbuild-cmake)
is one option; any recent mpv build works.

```text
# Windows, portable install (recommended)
git clone https://github.com/iK4w4/mpv-cinema.git portable_config
# then move portable_config/ next to mpv.exe

# or, per-user install
git clone https://github.com/iK4w4/mpv-cinema.git %APPDATA%\mpv
```

`portable_config/` next to `mpv.exe` takes precedence over
`%APPDATA%\mpv\`. On Linux/macOS, clone to `~/.config/mpv`
instead — the Windows-only options in `mpv.conf` (`gpu-api=d3d11`,
`d3d11-adapter`) need to be removed or changed there.

Do not add `scripts/autoload.lua`: it turns one opened file into
a whole-directory playlist. `autoload=no` is already set in
`script-opts/uosc.conf`.

## What is in here

| File | What it does |
| --- | --- |
| `mpv.conf` | Windows + NVIDIA defaults, 50% start volume, half-screen window, no always-on interpolation |
| `profiles.conf` | FSRCNNX / FSRCNNX+ / FSRCNNX-Anime / Anime4K upscalers (Ctrl+1–4), auto 4K downscale, auto Anime deband, HDR tone-mapping, 5.1/7.1 downmix |
| `input.conf` | Key bindings and the uosc menu |
| `scripts/wave.lua` | Speech waveform track (see below) |
| `scripts/uosc/` | uosc 5.13.0 interface |
| `scripts/thumbfast.lua` | Timeline thumbnails |
| `scripts/memo.lua` | Recent-files menu (`h`) |
| `scripts/autodeint.lua` | Automatic deinterlace detection (`Ctrl+D`) |
| `shaders/` | Only the shaders the profiles actually use |
| `fonts/` | Subtitle and OSD fonts, uosc icons |

## Waveform

`scripts/wave.lua` decodes the audio of the opened file once,
caches the peaks under `cache/waveforms/`, and draws a waveform
track above the uosc controls, on the same time axis as the
timeline. Cyan is speech, grey is silence. It appears
automatically — no key press needed.

- `w` / `W` — hide / show the track
- `Alt+Right` / `Alt+Left` — jump to the next / previous speech segment

It needs a decoder: `ffmpeg.exe` next to `mpv.exe` is preferred,
otherwise mpv encodes the audio itself (slower, first time per
file only). Streams are not processed, local files only. See
`script-opts/wave.conf` for the height, threshold and sample rate.

## Keys

| Key | Action |
| --- | --- |
| `Tab` | Toggle UI |
| `d` | Cycle deband |
| `Ctrl+D` | Auto deinterlace detect |
| `g` | Toggle interpolation |
| `c` | Clear shaders |
| `Ctrl+1` / `Ctrl+2` / `Ctrl+3` / `Ctrl+4` | FSRCNNX / FSRCNNX+ / FSRCNNX-Anime / Anime4K |
| `n` | Cycle denoise shaders |
| `h` | Recent files |
| `b` | Open file |
| `Alt+C` | Chapters |
| `F1` | Dialogue loudness normalisation |
| `a` | Toggle audio normalisation |
| `y` / `Y` | Load / select subtitles |
| `Alt+J` / `Alt+K` | Subtitle size |
| `Z` / `z` | Subtitle delay |
| `Right` / `Left` | Frame step / back |
| `w` | Hide / show waveform |
| `Alt+Right` / `Alt+Left` | Next / previous speech segment |
| `/` | Console |

## Notes

- uosc's self-update needs its `ziggy-windows.exe` helper, which
  is intentionally not committed (platform binaries do not belong
  in a config repository). Get it from a uosc release if the
  in-player update check is wanted; everything else works
  without it.
- `cache/`, `watch_later/` and `script-opts/memo-history.log`
  are runtime state and are ignored by git (see `.gitignore`).
- Third-party scripts keep their own licenses. See
  `THIRD-PARTY.md`. The config files and `scripts/wave.lua`
  in this repository are MIT licensed (see `LICENSE`).
