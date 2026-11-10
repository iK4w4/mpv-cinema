# Third-party components

This repository's own files — `mpv.conf`, `input.conf`,
`profiles.conf`, `script-opts/uosc.conf`, `script-opts/wave.conf`,
`script-opts/thumbfast.conf`, `scripts/wave.lua`, `README.md` —
are MIT licensed (see `LICENSE`).

The following components are bundled under their own licenses
and are not covered by that MIT license. Their headers and
license notices are kept intact in the files themselves.

- **uosc** (`scripts/uosc/`, `fonts/uosc_icons.otf`,
  `fonts/uosc_textures.ttf`) — by Tomáš Klaen,
  GNU General Public License v3.0,
  https://github.com/tomasklaen/uosc
- **thumbfast** (`scripts/thumbfast.lua`) — by po5,
  Mozilla Public License 2.0 (see the header of the file),
  https://github.com/po5/thumbfast
- **memo** (`scripts/memo.lua`) — by po5,
  Mozilla Public License 2.0,
  https://github.com/po5/memo
- **autodeint** (`scripts/autodeint.lua`) — automatic
  deinterlace detection, an mpv community script, bundled as-is,
  https://github.com/mpv-player/mpv/wiki/User-Scripts
- **Shaders** (`shaders/*.glsl`):
  - FSRCNNX (`F8.glsl`, `F16.glsl`, `F8_LA.glsl`) — by igv,
    GNU General Public License v3.0,
    https://github.com/igv/FSRCNNX
  - Anime4K (`Anime4K_*.glsl`) — by bloc97, MIT License
    (see the headers of the files),
    https://github.com/bloc97/Anime4K
  - KrigBilateral (`krigbl.glsl`) — by Shiandow,
    GNU General Public License v3.0 (see the header of the file)
  - SSIM (`ssimsr.glsl`, `ssimds.glsl`) — by igv,
    GNU General Public License v3.0,
    https://github.com/igv/SSimSuperRes
  - nlmeans (`nlmeans_HQ.glsl`, `nlmeans_L_HQ.glsl`) — by
    an3223 and Clément Bœsch, GNU General Public License v3.0
    (see the headers of the files)
- **Fonts**:
  - Clear Sans (`fonts/ClearSans-Bold.ttf`) — by Intel,
    Apache License 2.0
  - JetBrains Mono (`fonts/JetBrainsMono-Regular.ttf`) — by
    JetBrains, SIL Open Font License 1.1
  - The uosc fonts above are part of uosc (GPL-3.0).
