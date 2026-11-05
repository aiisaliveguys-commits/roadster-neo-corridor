# ROADSTER: Neo Corridor

A Roblox vertical slice: a driveable, **flyable** angular sports car in a procedural open
city, with GTA-V-flavoured wanted levels, checkpoint missions and an in-car radio.

Everything that needs a GPU or a fat runner runs in **GitHub Actions**, not on a dev box.
You only ever download an artifact.

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
src/shared/                 ReplicatedStorage (Config, CarController)
src/server/                 ServerScriptService
src/client/                 StarterPlayerScripts
src/server/CityGen.lua        procedural blocks, towers, skyway corridor
test/harness.lua              headless physics suite (lua5.1 test/harness.lua)
tools/                        token + security audit scripts
```

## Working locally

```bash
sudo apt-get install -y lua5.1     # syntax gate + test runner
brew install stylua rojo            # or the GitHub releases for your platform

stylua -f .stylua.toml src test     # format
lua5.1 test/harness.lua             # physics suite, ~1s
rojo build --output roadster.rbxlx  # place file to open in Studio
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
- [x] headless physics suite wired into CI
- [ ] city generator, police/wanted, missions, HUD, radio (next)
- [ ] `SetNetworkOwnerAsync` path for published play
