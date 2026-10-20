#!/bin/sh
# Builds OpenTTD (https://www.openttd.org/, GPL-2.0-only) for the site, from
# the 15.3 release with the Emscripten port it carries (os/emscripten), with
# these changes (openttd.diff beside this script):
# - the play page writes the game's files before it runs main() and keeps the
#   player's own files (settings, saved games, high scores) itself, instead of
#   the files built into openttd.data and an IndexedDB mount; pre.js no longer
#   picks the drivers, the page passes them;
# - the page sizes the game to its game area (wg_resize), and the game's own
#   full screen (its option, Alt+Enter and a saved setting) is off, with the
#   rest of the Display options (resolution, refresh rate, acceleration);
# - the game in progress is written to /wg/snapshot.sav when the page asks,
#   and /wg/restore.sav is loaded when it asks (Resume);
# - multiplayer, online content and the Social options tab are left out of
#   the menus (single player only), and so are the Quit buttons and Ctrl+Q: the page is the game's
#   window, so there is nothing to quit to; the page asks the game to write the
#   settings, hotkeys and high scores it would write as it quits;
# - music: OpenMSX plays through FluidSynth (built here without its audio
#   drivers, threads or glib) with the TimGM6mb sound font, and its warnings
#   about the songs stay out of the page's console.
# main() is run by the play page (INVOKE_RUN=0).
#
# The game's data zip holds what the build makes for openttd.data (base set
# metadata, the original sprites OpenTTD adds, the title game), without the
# TrueType fonts (this build has no FreeType), the languages the page offers
# that the base set's own font draws (English, American English, German,
# French, Spanish and Brazilian Portuguese), the script compatibility
# files and the docs the game shows. OpenGFX, OpenSFX and OpenMSX are served
# as released, and TimGM6mb.sf2 as packaged by MuseScore.
#
# Needs git, cmake, ninja, a host C++ compiler, zip, curl and emsdk 3.1.57
# (OpenTTD's own Dockerfile version; source emsdk_env.sh first).
# Usage: sh build.sh [work dir]
# Writes openttd.js and openttd.wasm next to this script, and the files for R2
# to <work dir>/r2/openttd/ (upload them to wasmgame-files under the same keys).
# For a newer OpenTTD, copy this folder to openttd-<new rev>-p1 and change the
# revision below; a change to the build here takes the next -p number.
set -eu

OPENTTD_REV=14ec60f248547d4d062a1160f0fc26d742319888 # 15.3
FLUIDSYNTH_REV=v2.5.7
OPENGFX=8.0
OPENSFX=1.0.3
OPENMSX=0.4.2
TIMGM6MB=https://raw.githubusercontent.com/musescore/musescore-old/90c33ef9d87b3f5ff92efd3b07d89eb455fb1fef/mscore/share/sound/TimGM6mb.sf2
EMSDK_VERSION=3.1.57
LANGS="english english_US german french spanish brazilian_portuguese"

here=$(cd "$(dirname "$0")" && pwd)
work=${1:-${TMPDIR:-/tmp}/openttd-build}
src=$work/OpenTTD

case "$(emcc --version | head -1)" in
  *" $EMSDK_VERSION "*) ;;
  *) echo "warning: built and tested with emsdk $EMSDK_VERSION" >&2 ;;
esac

# Emscripten fetches these ports as GitHub archives; clone them instead.
. "$here/ports.sh"
port zlib madler/zlib v1.2.13 zlib-1.2.13 https://github.com/madler/zlib/archive/refs/tags/v1.2.13.tar.gz
port sdl2 libsdl-org/SDL release-2.28.4 SDL-release-2.28.4 https://github.com/libsdl-org/SDL/archive/release-2.28.4.zip

mkdir -p "$work"
# A checkout left by an earlier build is reset, so this folder's diff is the one applied.
[ -d "$src" ] || git clone -q https://github.com/OpenTTD/OpenTTD.git "$src"
git -C "$src" -c advice.detachedHead=false checkout -q -f "$OPENTTD_REV"
git -C "$src" clean -q -fd src os
git -C "$src" apply "$here/openttd.diff"
# OpenTTD's liblzma port, installed as its Dockerfile does.
cp "$src/os/emscripten/ports/liblzma.py" "$(dirname "$(which emcc)")/tools/ports/contrib/liblzma.py"

# FluidSynth, a static library with nothing but the synth and MIDI player.
fs=$work/fluidsynth
[ -d "$fs" ] || git clone -q --depth 1 -b "$FLUIDSYNTH_REV" https://github.com/FluidSynth/fluidsynth.git "$fs"
git -C "$fs" submodule update -q --init --depth 1 gcem
off=""
for o in threads openmp libsndfile network ipv6 aufile alsa jack pulseaudio pipewire sdl3 oss dbus ladspa \
  libinstpatch midishare readline native-dls systemd; do off="$off -Denable-$o=OFF"; done
# shellcheck disable=SC2086
emcmake cmake -S "$fs" -B "$work/fluidsynth-build" -G Ninja -DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=OFF \
  -Dosal=embedded -Denable-floats=ON -DGCEM_INCLUDE_DIR="$fs/gcem/include" $off > /dev/null
ninja -C "$work/fluidsynth-build" libfluidsynth > /dev/null
inc=$work/fluidsynth-include
rm -rf "$inc"
mkdir -p "$inc/fluidsynth"
cp "$fs"/include/fluidsynth/*.h "$work/fluidsynth-build/include/fluidsynth/version.h" "$inc/fluidsynth/"
cp "$work/fluidsynth-build/include/fluidsynth.h" "$inc/"

# The tools that make the language files and such, for this computer.
cmake -S "$src" -B "$work/host" -G Ninja -DOPTION_TOOLS_ONLY=ON > /dev/null
ninja -C "$work/host" tools > /dev/null

# The game.
emcmake cmake -S "$src" -B "$work/build" -G Ninja -DHOST_BINARY_DIR="$work/host" -DCMAKE_BUILD_TYPE=Release \
  -DOPTION_USE_ASSERTS=OFF -DFluidsynth_INCLUDE_DIR="$inc" \
  -DFluidsynth_LIBRARY="$work/fluidsynth-build/src/libfluidsynth.a" > /dev/null
ninja -C "$work/build" openttd
cp "$work/build/openttd.js" "$work/build/openttd.wasm" "$here/"

# The data zip.
stage=$work/data
rm -rf "$stage"
mkdir -p "$stage/baseset" "$stage/lang" "$stage/docs"
cp "$work"/build/baseset/* "$stage/baseset/"
rm -f "$stage"/baseset/*.ttf
for l in $LANGS; do cp "$work/build/lang/$l.lng" "$stage/lang/"; done
cp -r "$src/bin/ai" "$src/bin/game" "$stage/"
rm -f "$stage/ai/CMakeLists.txt" "$stage/game/CMakeLists.txt"
for f in README.md CREDITS.md CONTRIBUTING.md COPYING.md known-bugs.md changelog.md; do cp "$src/$f" "$stage/"; done
cp "$src"/docs/admin_network.md "$src"/docs/debugging_desyncs.md "$src"/docs/desync.md "$src"/docs/directory_structure.md \
  "$src"/docs/eints.md "$src"/docs/fonts.md "$src"/docs/linkgraph.md "$src"/docs/logging_and_performance_metrics.md \
  "$src"/docs/multiplayer.md "$src"/docs/savegame_format.md "$src"/docs/symbol_server.md "$stage/docs/"
find "$stage" -exec touch -d 2000-01-01T00:00:00Z {} +
mkdir -p "$work/r2/openttd"
rm -f "$work/data.zip"
(cd "$stage" && find . -type f | LC_ALL=C sort | sed 's|^\./||' | TZ=UTC zip -q -X -9 -@ "$work/data.zip")
hash=$(sha256sum "$work/data.zip" | cut -c1-12)
mv "$work/data.zip" "$work/r2/openttd/data-$hash.zip"
echo "data: $work/r2/openttd/data-$hash.zip"

# The base sets as released, and the sound font.
curl -fsSL -o "$work/r2/openttd/opengfx-$OPENGFX-all.zip" "https://cdn.openttd.org/opengfx-releases/$OPENGFX/opengfx-$OPENGFX-all.zip"
curl -fsSL -o "$work/r2/openttd/opensfx-$OPENSFX-all.zip" "https://cdn.openttd.org/opensfx-releases/$OPENSFX/opensfx-$OPENSFX-all.zip"
curl -fsSL -o "$work/r2/openttd/openmsx-$OPENMSX-all.zip" "https://cdn.openttd.org/openmsx-releases/$OPENMSX/openmsx-$OPENMSX-all.zip"
curl -fsSL -o "$work/r2/openttd/TimGM6mb.sf2" "$TIMGM6MB"
ls -l "$work/r2/openttd"
