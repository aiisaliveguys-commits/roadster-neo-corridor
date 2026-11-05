# ROADSTER: Neo Corridor

A Roblox vertical slice: a driveable, **flyable** angular sports car in a procedural open
city, with GTA-V-flavoured wanted levels, checkpoint missions and an in-car radio.

**➡ [Download the place file from the latest release](
https://github.com/aiisaliveguys-commits/roadster-neo-corridor/releases/latest)** — open the
`.rbxlx` in Roblox Studio, press Play. City, car, HUD, wanted system and missions are all in
the file; there is nothing to import and nothing to configure. See
[docs/PLAYING.md](docs/PLAYING.md).

Everything heavier than a Lua parse runs in **GitHub Actions**, not on a dev box: you only
ever download an artifact.

## Why the workflow is shaped like this

Studio is Windows-only and cannot run in this project's CI, so the interesting risk in a
vehicle game is not "does it open" but "does the physics behave". That is verified headlessly:

```
test/harness.lua          real CarController module
                          + fake engine (CFrame/Vector3/raycast)
                          + a rigid-body integrator that models VectorForce,
                            LinearVelocity and AngularVelocity the way Roblox's
                            solver actually resolves them
```

The suite asserts behaviour - does it accelerate, does it turn without spinning out,
does it climb, does it hold altitude, does it hand control back to the wheels after
landing - so a regression in tuning shows up as a red CI run instead of as a car that
drives like a shopping trolley.

That harness has already earned its keep. It caught four bugs that no amount of reading
the code would have found:

| Bug found | Symptom it would have shipped as |
|---|---|
| gravity double-counted in the spring law | car launches to 157 studs instead of settling |
| per-wheel force not divided by wheel count | 6-wheel car sits higher than a 4-wheel car |
| damper active with no ground contact | car catapults itself off thin air |
| `VelocityFactor` treated as a rate | config said 1.15 g, car delivered 0.28 g |

## Layout

```
default.project.json        Rojo mapping: src -> Roblox services
src/shared/   -> ReplicatedStorage   (ModuleScripts, plain .lua)
src/server/   -> ServerScriptService (.server.lua -> Script, .module stays ModuleScript)
src/client/   -> StarterPlayerScripts (.client.lua -> LocalScript)

  shared/    Config.lua  CarController.lua  Remotes.lua  CityGenerator.lua  PlayerState.lua
  server/    main  VehicleSpawner  WantedService  MissionService
  client/    Bootstrap  HUD  Radio
```

The filename suffix is the class mapping, and it is load-bearing: with plain `.lua`
names Rojo built every server file as a **ModuleScript**, which parses, opens in Studio,
and executes nothing. `tools/check_place.py` asserts the artifact contains real `Script`
instances, because that bug passed a syntax gate, the physics suite and `rojo build`.

```
test/harness.lua              headless physics suite (lua5.1 test/harness.lua)
test/config_drift.lua         the harness Config mirror must match the real Config
tools/check_place.py          validates the built .rbxlx, not the source
tools/                        token + security audit scripts
docs/PLAYING.md               how to get this running on your PC
```

## Working locally

```bash
sudo apt-get install -y lua5.1     # syntax gate + test runner
brew install stylua rojo            # or the GitHub releases for your platform

stylua -f .stylua.toml src test     # format
lua5.1 test/config_drift.lua        # tuning mirror in sync
lua5.1 test/harness.lua             # physics suite, ~1s
rojo build --output dist/roadster.rbxlx
python3 tools/check_place.py dist/roadster.rbxlx   # the artifact, not the source
```

`rojo build` is the only step that touches Studio-visible output, and it is fast - CI does
it on every push and uploads `roadster.rbxlx` as an artifact, so a machine with 2 GB of RAM
never has to render or bake anything.

## Controls (once the driving script lands)

| Key | Ground | Air |
|---|---|---|
| `W`/`S` | throttle / reverse | pitch down / up |
| `A`/`D` | steer | yaw |
| `Q`/`E` | - | roll |
| `Space` | hop (above 70 studs/s) | climb, then altitude-hold on release |
| `F` | engage aero | disengage to LANDING |
| `Left Shift` | boost (energy-budgeted) | boost |
| `Left Ctrl` | handbrake | - |
| `H` / `R` | radio on/off / next station | same |

## Security posture (public repo)

The `security-audit` job re-checks these on every push and on a schedule, and writes its
findings into the run summary:

- `pull_request` runs with `permissions: contents: read` and no secrets; no
  `pull_request_target`, so a fork PR cannot reach anything privileged
- no `github.event.*` user text interpolated into a `run:` block
- no token/private-key shaped strings committed
- no `git push` from CI
- **no publish workflow** - Roblox credentials never live in a public repo. When
  auto-publish is wanted, that job goes in a private repo and receives the place file as an
  artifact, or uses a revocable Open Cloud API key instead of a login cookie

To check a token's real blast radius:

```bash
GH_TOKEN=... bash tools/token-audit.sh
```

## Status

- [x] config module, drive model, flight model, landing, boost, HUD attributes
- [x] headless physics suite wired into CI (18 checks, 1 tracked known-open)
- [x] procedural city, elevated corridor, rooftop pads
- [x] built-in demo chassis (`CarBuilder`) so the file is playable untouched
- [x] vehicle binding for a model you import (no hardcoded mesh), wanted stars, chase
      cruisers, ring missions, HUD, radio
- [x] place-file artifact check in CI (`tools/check_place.py`)
- [ ] audio wired: `Config.Radio.DJIntro` / `AdBump` / `Config.Voice.*` are `0` until
      you upload the mp3s in `audio/` and paste ids
- [ ] `VehicleConstraint`-free physics verified in Studio - the harness models the
      solver, it does not replace it
- [ ] multiplayer: one car per player is wired, but the mission/wanted loop is solo-tuned
