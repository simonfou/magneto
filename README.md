# magneto

A music visualizer in the style of **Magnetosphere**, the iTunes 8+ visualizer by Robert Hodgin: glowing particle clusters orbiting a few white stars, breathing with the music. Built with Godot 4.7.

On Linux it listens to **Spotify only**. Discord, games and everything else never reach it. On Windows it listens to everything the PC plays except Discord.

## Run it

**Linux**: `./run.sh`, or "Magneto" in the KDE menu. Start Spotify; the visualizer wires itself to it within ~2 s.

Needs:
- Godot 4.7.1 at `~/.local/bin/godot`
- PipeWire (`pw-link`) and `gdbus`, both standard on Fedora KDE
- Spotify

**Windows**: unzip `magneto-windows.zip` and run `magneto.exe`. Needs Windows 10 version 2004 or later; `LISEZMOI.txt` in the zip covers the rest, in French.

## Controls

| Key | Action |
|---|---|
| Right-click | Menu: mode, auto, fullscreen, meters, quit |
| `1`–`7` | Lock a mode (remembered across runs) |
| `0` or `A` | Back to Auto: a new random mode on each song |
| `N` | Next mode |
| `F` / `F11` | Fullscreen |
| `D` | Level meters (bass, mid, treble, beat, loudness) |
| `Esc` | Quit |

## What you see

Seven modes, six of them modelled on frames of the original:

| # | Mode | Look |
|---|---|---|
| 1 | Bokeh | Sparse coloured dots and big soft out-of-focus discs around white stars |
| 2 | Bubbles | Glass spheres around the stars, dots stuck on their surface |
| 3 | Field lines | Thin curved lines arcing from star to star |
| 4 | Urchin | Straight needles bursting out of the stars |
| 5 | Ribbons | Wide flat ribbons twisting around the stars |
| 6 | Aurora | Long turbulent green and violet filaments (our own) |
| 7 | Black holes | Black moons beside each star that eclipse it and swallow nearby dots |

The scene follows the music:
- **Bass, mid and treble** inflate the clusters, spin them and make them sparkle.
- **Beats** push the particles out and the camera in, gently.
- **Loudness** sets how much shows: a quiet passage is little more than the stars, a loud one fills the screen.
- **Stars come and go**, between none and five, a new count every 8–25 s, landing on a beat.
- **A mode change** morphs over 6 s, marked by a brief colour wash of the background, as in the original.

## How the audio works

**Linux.** Godot can only open a microphone, so the app opens the default mic. Then `spotify.gd` rewires PipeWire with `pw-link`: Spotify's output goes into the visualizer's input, and the mic is unplugged. It re-checks every 1.5 s and reads the song title over MPRIS (`gdbus`). The captured sound goes to a muted bus, so nothing is played back.

**Windows.** A small native extension (`native/`, class `LoopbackCapture`) uses the Windows process-loopback API to capture everything except Discord. A song change is detected from the short silence between tracks.

## Project layout

| Path | What |
|---|---|
| `main.gd` | Wires the parts together. Owns the modes, particle materials, camera and background wash |
| `audio.gd` | Capture and analysis: levels, beats, loudness |
| `nodes.gd` | The magnetic nodes: how many, where they roam, their stars and bubbles |
| `ui.gd` | Meters, song announcements, menu, keys |
| `spotify.gd` | PipeWire routing and track info (Linux) |
| `modes.gd` | The seven modes, as overrides of one set of defaults |
| `shaders/` | Particle physics (`*_process`), drawing (`*_draw`), stars, bubbles |
| `native/` | Windows capture extension (C++, godot-cpp submodule); built libraries are in `bin/` |
| `packaging/` | Windows build script and its French readme |

## Development

Command-line flags go after `--`, for example `./run.sh -- --mode=2`:

| Flag | Effect |
|---|---|
| `--mode=N` | Lock mode N (0-based) for this run only |
| `--nodes=N` | Fixed number of stars |
| `--shot=x.png --frames=N` | Save frame N and quit |
| `--wash=F` | Start a background wash F frames before the shot |
| `--tone` | Feed a 70 Hz test tone instead of Spotify |
| `--selftest` | Feed the test tone, print levels, quit |
| `--meter` | Print live levels, quit |
| `--dump=x.csv` | Log raw band levels every frame, for tuning the beat detection |

Tests that don't touch the screen or the speakers:

```sh
# Levels from the test tone, no window
godot --display-driver headless --audio-driver PulseAudio --path . -- --selftest

# A screenshot from an invisible compositor (renders on the GPU)
kwin_wayland --virtual --width 1600 --height 900 --socket wl-magneto --exit-with-session \
  "godot --display-driver wayland --audio-driver PulseAudio --path $PWD -- --tone --shot=/tmp/x.png --frames=600"
```

The virtual compositor runs at 60 fps, so count frames at 60 per second there.

**Windows build:** `packaging/build-windows.sh` writes `build/magneto-windows.zip`. It needs only Godot and its 4.7.1 export templates.

**Rebuilding the capture extension** is only needed after a change under `native/src/`:

```sh
sudo dnf install mingw64-gcc-c++ mingw64-winpthreads-static scons
cd native && scons platform=windows use_mingw=yes target=template_release
```
