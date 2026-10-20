# OpenTTD in the browser

This fork is the web build of [OpenTTD](https://github.com/OpenTTD/OpenTTD) that runs on wasmga.me. Play it at **https://wasmga.me/games/openttd**.

It is OpenTTD 15.3 built with its own Emscripten port, for single player: multiplayer, online content, the Social options tab and Quit are left out, and the page owns full screen. The music is OpenMSX played through FluidSynth with the TimGM6mb sound font. The game can also save and load the game in progress on request (`wg_request_snapshot()` and `wg_restore()`), which the page uses to resume a game.

## What's here

- Branch `wasmgame` (this one) is upstream commit [`14ec60f`](https://github.com/OpenTTD/OpenTTD/commit/14ec60f248547d4d062a1160f0fc26d742319888) (15.3) with our changes on top as commits, so `git log` and the diff against `14ec60f` show everything we changed.
- [`wasmgame/`](../wasmgame) holds the build script and the same changes as `openttd.diff` against that commit. `build.sh` starts from a fresh upstream checkout, applies it and builds, and its header comment lists each change.

## Building

Needs git, cmake, ninja, a host C++ compiler, zip, curl and emsdk 3.1.57 (source `emsdk_env.sh` first).

```sh
sh wasmgame/build.sh /tmp/openttd-build
```

It builds FluidSynth 2.5.7 as a static library, the host tools, then the game, and writes `openttd.js` and `openttd.wasm` next to the script. Under `<work dir>/r2/openttd/` go the game's data zip (base set metadata, languages, script libraries and docs), OpenGFX, OpenSFX and OpenMSX as released, and the sound font.

## Running it

The page runs `main()` itself (`INVOKE_RUN=0`) with `-v sdl -s sdl -m fluidsynth:soundfont=/soundfont/TimGM6mb.sf2 -r <width>x<height>`, after writing the data zip to `/`, the base sets to `/baseset` (OpenMSX unpacked, since music sets aren't read from tars) and the player's files to `/home/web_user/.openttd`. `wg_resize(w, h)` follows the page's size, `wg_save_files()` writes the settings, hotkeys and high scores, and for a snapshot `wg_request_snapshot()` writes `/wg/snapshot.sav` between two ticks (`wg_snapshot_count()` goes up when it's done); `wg_restore()` loads `/wg/restore.sav`.

## Licence

Same as upstream: GPL-2.0-only (see `COPYING.md`). FluidSynth is LGPL-2.1-or-later, OpenGFX and OpenMSX GPL-2.0, OpenSFX CC BY-SA 3.0, TimGM6mb GPL-2.0. Our changes are under the same licence as the files they change.
