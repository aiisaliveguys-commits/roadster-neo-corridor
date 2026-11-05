--[[
	Main - server entry point.

	Order matters here more than it looks like it does: the city has to exist
	before the spawner pivots a car onto it (a car unanchored before the ground
	under it exists falls forever), and the remotes have to exist before either
	service tries to fire them. PlayerAdded handlers are wired before generation
	completes, and both services wait on the same BindableEvent, so a player who
	joins mid-generation is not silently skipped.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("Config"))

-- create the remotes first: every service below fires them, and a client that
-- joins during city generation would otherwise find nothing to wait for
require(ReplicatedStorage:WaitForChild("Remotes")).Ensure()

local ready = Instance.new("BindableEvent")
ready.Name = "CityReady"
-- kept after firing: VehicleSpawner may run its join handler either before or after
-- generation finishes, and it must be able to check for the event AND for the city
-- folder, not just wait on an event that already fired
ready.Archivable = false
ready.Parent = ReplicatedStorage

local CityGenerator = require(game:GetService("ReplicatedStorage"):WaitForChild("CityGenerator"))

local city
task.spawn(function()
	local t0 = os.clock()
	city = CityGenerator.Generate(Workspace, 20261105)
	print(
		string.format(
			"[Main] city built: %d parts, extent %.0f studs, deck at y=%.0f, %d rooftop pads, %.1fs",
			city.PartCount,
			city.Extent,
			city.DeckY,
			#city.RooftopPads,
			os.clock() - t0
		)
	)
	-- the baseplate is now redundant scenery; leaving it under the city is how you
	-- get a mystery floor you cannot see when you fly below the map
	local bp = Workspace:FindFirstChild("Baseplate") or Workspace:FindFirstChild("Baseplate")
	if bp ~= nil then
		bp.Transparency = 1
		bp.CanCollide = false
		bp.CanQuery = false
	end
	local lighting = game:GetService("Lighting")
	if Config.City.Night ~= false then
		lighting.ClockTime = 21.5
		lighting.Brightness = 1.5
		lighting.Ambient = Color3.fromRGB(26, 30, 44)
		lighting.OutdoorAmbient = Color3.fromRGB(26, 30, 44)
		lighting.FogEnd = 2400
		lighting.FogColor = Color3.fromRGB(22, 26, 38)
		lighting.GlobalShadows = true
	end
	ready:Fire(city)
end)

-- leaderstats must exist before the client looks for it: the HUD waits on this
-- folder, and a timeout there shows up as "the cash counter never updates", which
-- reads like a HUD bug and not like a missing instance
local Players = game:GetService("Players")
local PlayerState = require(game:GetService("ReplicatedStorage"):WaitForChild("PlayerState"))
local function attach(player)
	PlayerState.attach(player)
end
Players.PlayerAdded:Connect(attach)
for _, p in ipairs(Players:GetPlayers()) do
	attach(p)
end

-- The three services are sibling Scripts, so each can be disabled on its own while
-- tuning. CityGenerator and PlayerState live in ReplicatedStorage as ModuleScripts:
-- Rojo strips only .server/.client from a generated instance name (not .module), so a
-- "X.module.lua" in src/server would arrive named "X.module" and every
-- WaitForChild("X") would hang forever. ReplicatedStorage + a plain .lua is the
-- boring fix that keeps names exact. Both are only required by server code.
for _, name in ipairs({ "VehicleSpawner", "WantedService", "MissionService" }) do
	local s = script.Parent:FindFirstChild(name)
	if s == nil then
		warn("[Main] missing service: " .. name)
	else
		s.Enabled = true
	end
end
