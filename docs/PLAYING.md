# Playing it on your PC

**The short version:** download `ROADSTER-Neo-Corridor.rbxlx` from the [latest release](
https://github.com/aiisaliveguys-commits/roadster-neo-corridor/releases/latest),
double-click it, press **Play**. A demo car and the whole city are inside the file, so
there is nothing to import and nothing to configure. Everything below is the long version.

One thing cannot be removed: Roblox places only run inside Roblox **Studio** on your
machine (Studio is what publishes and hosts the place), so "open in Studio, press Play" is
the floor. Windows 10/11 is the only path that works: **Roblox Studio** (which builds and publishes
the place) ships for Windows and macOS, not Linux. Roblox Player alone is not enough — a
`.rbxlx` file is not something the player can open.

## 1. Install

- [Roblox Studio](https://www.roblox.com/create) — one installer, includes the player.

## 2. Get the place file

Either source works and both are produced by the same CI job:

- **Releases** (recommended): the release asset is the plain `.rbxlx`, no unzip, and it
  survives a repo being cleaned of old workflow runs.
- **Actions → newest green run → Artifacts → `roadster-place`**: always the absolute latest
  commit, but it is a zip and old runs expire after 30 days.

If the artifact is missing, the build job failed — open the run and read the red step. The
log is the whole point of having CI do this.

## 3. Open it

Double-click `roadster.rbxlx`, or Studio → **File → Open from File…**.

You will see an essentially **empty viewport**. That is expected: the city is procedurally
generated when the place runs, not baked into the file. Press **Play** and it builds.

## 4. (Optional) Swap in your Tesla model

The place file already contains a built-in demo chassis, built by `src/shared/CarBuilder.lua`,
so it drives with no import. It is a box-wedge with four box wheels — deliberately simple,
because it is a fallback and not the product.

**Your imported model always wins.** The spawner looks for one first; only when there is
nothing to claim does it build the demo car. So importing is still the supported path, just
no longer a required one. Geometry note: those wheel offsets are the tuned numbers — see
`CarBuilder`'s header — and the headless suite asserts the built car produces exactly the
same hub height, track, wheelbase and radius the physics was tested against.

1. In Studio, open the **Toolbox** (View → Toolbox) and find your Tesla-partnered model, or
   drag in a `.rbxm`/`.rbxmx` you already own.
2. Put it in **ServerStorage** (recommended) or **Workspace**. (Demo car is currently in play?
   It is only built when nothing is claimable, so rejoin after importing.)
3. Name it something obvious, e.g. `CyberRoadster`.
4. If the model has no PrimaryPart: select the biggest chassis part → right-click →
   **Set Primary Part** (or set `Model.PrimaryPart` in Properties). The spawner can pick
   the largest part by itself, but an explicit PrimaryPart removes all doubt.
5. **Publish, then re-join** — the spawner claims the car about 1.5 s after you join, so a
   model dragged in mid-session is not picked up until the next session.

What the spawner does with it, printed to **Output** (View → Output):

```
[VehicleSpawner] bound CyberRoadster -> root 'Body', 4 wheel(s), seat 'DriverSeat'
```

Wheel detection is by part name (`wheel`/`tire`/`tyre`/`rim`/`hub`), biggest per corner.
If it prints `no parts named wheel/...` the car still drives but sits on its raw boxes.
You can override everything by setting attributes: `Role = "Root"` on one part,
`Role = "Wheel"` on exactly four, `Role = "Seat"` on the seat.

## 5. Audio (optional)

The six mp3s are in this repo at `audio/dispatch/*.mp3` and `audio/radio/*.mp3`. They are
**not** wired in yet: `Config.Radio.DJIntro`, `Config.Radio.AdBump` and every
`Config.Voice.*` are `0`, and `Stations[].Tracks` hold placeholder public audio ids.

To use your own: Studio → **Creator Store → Audio** (or your create dashboard) → upload the
mp3 → copy the asset id → set it in `ReplicatedStorage → Config` under those keys. The game
plays fine with them left at `0` — the radio just shows the station card with silence.

Note that uploaded audio is moderated and, on an unverified account, may not play for
others. Test with the ids set to `0` first if something seems missing.

## 6. Publish and play

Studio → **File → Publish to Roblox As…** → give it a name → keep it private.
Then play it two ways:

- **Play Solo** (the ▶ button in Studio) — fastest loop, and this slice is built for it:
  the client runs the physics and owns the assembly, so no replication needed.
- **Roblox Player** — from the game's page on roblox.com, press Play. Same place, real
  client/server split.

## Controls

| Key | Ground | Air |
|---|---|---|
| `W` / `S` | throttle / reverse | nose down / up |
| `A` / `D` | steer | — |
| `Q` / `E` | — | yaw left / right |
| `Z` / `X` | — | roll |
| `Space` | hop above ~70 studs/s | climb, release to hold altitude |
| `F` | engage aero | disengage → LANDING |
| `Left Shift` | boost (budgeted) | boost |
| `Left Ctrl` | handbrake | — |
| `H` / `R` | radio on/off, next station | same |
| `M` | start/abort mission run | same |

`M` and not `T`: `T` is Roblox's default chat key and would eat the input.

## If it does not behave

Check **Output** first — every script here tags its lines (`[Main]`, `[VehicleSpawner]`,
`[Bootstrap]`), and a wrong model binding looks completely different from a physics bug.

| Symptom | Almost always |
|---|---|
| toast says `no car model found` | the model was added after you joined, or is in a place the spawner does not search (Workspace / ReplicatedStorage / ServerStorage only) |
| car sinks through the floor on spawn | the model has a PrimaryPart that is not part of the chassis assembly |
| car twitches in place | two controllers on one assembly — re-enter Play instead of pressing Play twice |
| car accelerates far too gently | `Car.DriveTimeConstant` / `DriveMaxG` — the force ceiling is what you feel, not `DriveSpeed` |
| no stars appear | flying above `Wanted.FlyAltitude` (90) is legal by design; only low-and-fast over streets is an offence |

## Known-open physics items

`test/harness.lua` tracks two behaviours as unverified outside Studio (`hover drift`,
`post-landing speed`). They are listed in the CI run summary. If you get in there and the
hover feels fine, say so and I will close them out rather than leave them looking like bugs.
