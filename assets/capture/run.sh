#!/bin/sh
# Regenerates the README screenshots and assets/demo.gif in a new Alacritty window, using your shell and Neovim config.
# Run from the repo root (macOS, needs ffmpeg). The terminal running this script needs Screen Recording permission.
cd "$(dirname "$0")/../.." || exit 1
ALACRITTY="$(command -v alacritty || echo /Applications/Alacritty.app/Contents/MacOS/alacritty)"
shoot() {
  "$ALACRITTY" --title NeoContDemo --working-directory "$PWD" \
  -o window.dynamic_title=false -o window.dimensions.columns=150 -o window.dimensions.lines=36 \
  -e nvim -c "luafile assets/capture/demo.lua"
}
shoot # screenshots
# Animated tour: frames are grabbed while it runs, then turned into a GIF
FRAMES="$(mktemp -d)"
NEOCONT_FRAMES="$FRAMES" shoot
ffmpeg -y -loglevel error -f concat -safe 0 -i "$FRAMES/list.txt" \
  -vf "fps=10,scale=900:-1:flags=lanczos,mpdecimate,split[a][b];[a]palettegen[p];[b][p]paletteuse=dither=none" \
  -fps_mode vfr assets/demo.gif # mpdecimate drops repeated frames
rm -rf "$FRAMES"
