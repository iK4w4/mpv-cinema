# mpv-cinema

[![YouTube](https://img.shields.io/badge/YouTube-@iK4w4-FF0000?logo=youtube&logoColor=white)](https://www.youtube.com/@iK4w4)
[![Telegram](https://img.shields.io/badge/Telegram-@iK4w4-26A5E4?logo=telegram&logoColor=white)](https://t.me/iK4w4)
[![Telegram Bot](https://img.shields.io/badge/Telegram_Bot-@AskKawaBot-26A5E4?logo=telegram&logoColor=white)](https://t.me/AskKawaBot)

My personal mpv setup for Windows — a clean uosc interface, a
speech waveform above the timeline, and upscaler profiles for
anime and HD video. Fast by default: the heavy stuff (shaders,
interpolation) stays off until you ask for it with a key.

No shuffle, no loop buttons, no music-player clutter. This is a
video player, set up for watching videos.

by iK4w4 ([@iK4w4](https://t.me/iK4w4))

## Install

You need mpv first. The
[Shinchiro Windows build](https://github.com/shinchiro/mpv-winbuild-cmake)
is a good one; any recent mpv build works.

```text
# Windows, portable install (recommended)
git clone https://github.com/iK4w4/mpv-cinema.git portable_config
# then move portable_config/ next to mpv.exe

# or, per-user install
git clone https://github.com/iK4w4/mpv-cinema.git %APPDATA%\mpv
```

`portable_config/` next to `mpv.exe` wins over `%APPDATA%\mpv\`
if both exist. On Linux/macOS, clone to `~/.config/mpv`
instead — but remove the Windows-only lines in `mpv.conf`
(`gpu-api=d3d11`, `d3d11-adapter`) first, and set `gpu-api` to
what your system supports.

One warning: do **not** add `scripts/autoload.lua`. It turns
one opened file into a whole-directory playlist. `autoload=no`
is already set in `script-opts/uosc.conf`.

## Features

- **Speech waveform** — a waveform track sits above the uosc
  controls on the same time axis as the timeline. Cyan is
  speech, grey is silence. It builds itself when a file opens;
  no key press needed. Jump between speech segments with
  `Alt+Right` / `Alt+Left`, hide the track with `w`.
- **Upscalers on keys, not always on** — `Ctrl+1` to `Ctrl+4`
  apply FSRCNNX, FSRCNNX+, FSRCNNX-Anime, or Anime4K. Profiles
  restore cleanly, so nothing leaks into the next file.
- **Smart auto-profiles** — 4K files get clean downscaling,
  folders with "anime" in the path get debanding, HDR gets
  tone-mapping, and 5.1/7.1 audio is downmixed to stereo
  without losing the side channels.
- **uosc interface** — dark glass look, cyan accent, nothing
  stays on screen: every element fades out when the cursor
  goes idle.
- **Sane defaults** — 50% start volume, half-screen window,
  position saved on quit, Japanese audio preferred with
  English subtitles, anime signs and karaoke placement left
  untouched.

## The waveform

`scripts/wave.lua` decodes the audio of the opened file once,
caches the peaks under `cache/waveforms/`, and draws the
track. It prefers `ffmpeg.exe` next to `mpv.exe`; without it,
mpv encodes the audio itself (slower, first time per file
only). Local files only — streams are not processed. Height,
speech threshold and sample rate live in
`script-opts/wave.conf`.

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

## What's in here

| File | What it does |
| --- | --- |
| `mpv.conf` | Windows + NVIDIA defaults, renderer, sync, subtitle style |
| `profiles.conf` | The upscaler profiles and the auto-profiles |
| `input.conf` | Key bindings and the uosc menu |
| `scripts/wave.lua` | The speech waveform track |
| `scripts/uosc/` | uosc 5.13.0 interface |
| `scripts/thumbfast.lua` | Timeline thumbnails |
| `scripts/memo.lua` | Recent-files menu (`h`) |
| `scripts/autodeint.lua` | Automatic deinterlace detection (`Ctrl+D`) |
| `shaders/` | Only the shaders the profiles actually use |
| `fonts/` | Subtitle and OSD fonts, uosc icons |

## Notes

- uosc's self-update needs its `ziggy-windows.exe` helper,
  which is intentionally not committed — platform binaries do
  not belong in a config repository. Get it from a uosc
  release if you want the in-player update check; everything
  else works without it.
- `cache/`, `watch_later/` and `script-opts/memo-history.log`
  are runtime state and are ignored by git (see `.gitignore`).
- The config is tuned on an RTX 4060 Ti. On another GPU,
  delete the `d3d11-adapter` line in `mpv.conf`.

## Feedback

- **Bugs & ideas** — open an
  [issue](https://github.com/iK4w4/mpv-cinema/issues).
- **Questions** — message [@AskKawaBot](https://t.me/AskKawaBot)
  on Telegram.
- Like it? A ⭐ star helps other people find it.

## Credits

- Interface: [uosc](https://github.com/tomasklaen/uosc) by
  Tomáš Klaen (GPL-3.0).
- Thumbnails: [thumbfast](https://github.com/po5/thumbfast)
  and recent files: [memo](https://github.com/po5/memo), both
  by po5 (MPL-2.0).
- Shaders: FSRCNNX and SSIM by igv, Anime4K by bloc97,
  KrigBilateral by Shiandow, nlmeans by an3223 and Clément
  Bœsch.
- Full license details for every bundled piece are in
  [THIRD-PARTY.md](THIRD-PARTY.md) — third-party files keep
  their own licenses.
- Find the author on Telegram (https://t.me/iK4w4) and
  YouTube (https://www.youtube.com/@iK4w4).

## License

MIT — see [LICENSE](LICENSE). Copyright (c) 2026
iK4w4. The MIT license covers this repository's own files
only; bundled third-party components keep their own licenses
(see [THIRD-PARTY.md](THIRD-PARTY.md)).
