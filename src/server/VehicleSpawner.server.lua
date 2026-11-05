--[[
	VehicleSpawner - finds the car you imported and makes it driveable.

	No mesh is hardcoded here, on purpose. The Tesla model is licensed content you
	import yourself, so this script's job is to recognise whatever you dropped in.
	Recognition order:

	  1. A part already tagged Role = "Root" (or an attribute VehicleRole) - the
	     explicit path, use it if the heuristics ever guess wrong.
	  2. The model's PrimaryPart.
	  3. The largest BasePart in the model.

	Wheels are named-part matches (wheel/tire/tyre/rim/hub), one kept per corner,
	because a Toolbox car usually has four sensibly named tyres and a dozen
	"WheelDetail001" junk parts that must NOT become suspension anchors.

	There is deliberately no fallback car. If nothing is found the server prints
	exactly what it searched for and the game tells the player, rather than
	silently driving around a cardboard box and making you think your import broke
	the physics.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Remotes = require(ReplicatedStorage:WaitForChild("Remotes"))
local CarBuilder = require(ReplicatedStorage:WaitForChild("CarBuilder"))

local WHEEL_WORDS = { "wheel", "tire", "tyre", "rim", "hub" }
local SEAT_WORDS = { "seat", "driver", "chair" }

local function roleOf(inst)
	return inst:GetAttribute("Role") or inst:GetAttribute("VehicleRole")
end

local function isCarModel(model)
	if not model:IsA("Model") then
		return false
	end
	local hasSeat = model:FindFirstChild("Seat", true) or model:FindFirstChildOfClass("VehicleSeat")
	local partCount = 0
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			partCount = partCount + 1
			if partCount > 60 then
				break
			end
		end
	end
	-- a real car is >= 5 parts (chassis + 4 wheels); below that it is a decal or a prop
	return partCount >= 5, partCount, hasSeat ~= nil
end

local function nameMatches(part, words)
	local n = string.lower(part.Name)
	for _, w in ipairs(words) do
		if n:find(w, 1, true) then
			return true
		end
	end
	return false
end

local function volumeOf(part)
	local s = part.Size
	return math.max(0.001, s.X * s.Y * s.Z)
end

local function findCandidate()
	local searched = {}
	local roots = { Workspace, ReplicatedStorage, ServerStorage }
	for _, container in ipairs(roots) do
		searched[#searched + 1] = container:GetFullName()
		for _, model in ipairs(container:GetChildren()) do
			local ok = isCarModel(model)
			if ok then
				return model, searched
			end
		end
	end
	-- second pass: a tagged model anywhere in the tree beats an untagged one
	for _, container in ipairs(roots) do
		for _, d in ipairs(container:GetDescendants()) do
			if d:IsA("BasePart") and roleOf(d) == "Root" then
				return d.Parent, searched
			end
		end
	end
	return nil, searched
end

local function tag(model)
	-- root
	local root
	local taggedRoot = nil
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") and roleOf(d) == "Root" then
			taggedRoot = d
			break
		end
	end
	if taggedRoot ~= nil then
		root = taggedRoot
	elseif model.PrimaryPart ~= nil then
		root = model.PrimaryPart
	else
		local best, bestVol = nil, -1
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("BasePart") then
				local v = volumeOf(d)
				if v > bestVol then
					bestVol, best = v, d
				end
			end
		end
		root = best
	end
	if root == nil then
		return nil, "no BasePart"
	end

	root:SetAttribute("Role", "Root")
	model:SetAttribute("VehicleRoot", root.Name)
	-- the chassis must be the assembly root, or the actuators fight each other
	-- across two separate assemblies and the car twitches in place
	model.PrimaryPart = root

	-- wheels: pick the biggest match in each of the four quadrants
	local picked = {}
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") and d ~= root and nameMatches(d, WHEEL_WORDS) then
			local rel = root.CFrame:PointToObjectSpace(d.Position)
			local qx = rel.X >= 0 and 1 or -1
			local qz = rel.Z >= 0 and 1 or -1
			local key = qx .. "_" .. qz
			local cur = picked[key]
			if cur == nil or volumeOf(d) > volumeOf(cur) then
				picked[key] = d
			end
		end
	end
	-- The controller only looks for wheels inside a folder named "CarParts", and it
	-- finds the seat by the literal name "Seat" (FindFirstChild("Seat", true)).
	-- Tagging parts is therefore not enough on its own - a normally-rigged Toolbox
	-- car has its wheels loose under the Model, and that hits
	-- "needs 2+ tagged wheels" and crashes the binding.
	local carParts = model:FindFirstChild("CarParts")
	if carParts == nil then
		carParts = Instance.new("Folder")
		carParts.Name = "CarParts"
		carParts.Parent = model
	end
	local wheelCount = 0
	for _, w in pairs(picked) do
		w:SetAttribute("Role", "Wheel")
		if w.Parent ~= carParts then
			w.Parent = carParts
		end
		wheelCount = wheelCount + 1
	end

	-- seat
	local seat = model:FindFirstChildOfClass("VehicleSeat")
	if seat == nil then
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("VehicleSeat") then
				seat = d
				break
			end
		end
	end
	if seat == nil then
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("BasePart") and nameMatches(d, SEAT_WORDS) and d ~= root then
				seat = d
				break
			end
		end
	end
	if seat ~= nil then
		seat:SetAttribute("Role", "Seat")
		if seat.Name ~= "Seat" and model:FindFirstChild("Seat") == nil then
			seat.Name = "Seat"
		end
	end

	return {
		Root = root,
		Wheels = wheelCount,
		Seat = seat,
	}
end

local function announce(text)
	warn("[VehicleSpawner] " .. text)
	task.spawn(function()
		local ev = Remotes.Get("Notify")
		if ev then
			ev:FireAllClients("Vehicle", text)
		end
	end)
end

local SPAWN_AT = Vector3.new(0, 0, -40) -- on the launch apron, away from the default spawn

-- Binds an already-tagged model: publishes the attributes the other services key
-- off, drops it on the apron, then hands the assembly to the player.
local function prepare(model, info, player, spawnPos)
	model:SetAttribute("Ready", true)
	if player ~= nil then
		-- WantedService and MissionService both resolve "this player's car" through
		-- this; without it the first car in Workspace wins for everybody
		model:SetAttribute("Owner", player.Name)
		model.Name = player.Name .. "_Vehicle"
	end

	if info.Wheels == 0 then
		announce(
			"no parts named wheel/tire/tyre/rim/hub in "
				.. model.Name
				.. " - suspension is disabled, the car will sit on its raw boxes"
		)
	end
	if info.Seat == nil then
		announce("no seat found in " .. model.Name .. " - keyboard input only, no gamepad")
	end

	-- position BEFORE unanchoring: an unanchored assembly dropped before the ground
	-- exists under it free-falls forever and trips the fall recovery
	if model.PrimaryPart == nil then
		model.PrimaryPart = info.Root
	end
	model:PivotTo(CFrame.new(spawnPos or SPAWN_AT))

	if player ~= nil then
		task.spawn(function()
			-- ownership is per-ASSEMBLY and belongs on the root part of it; calling it
			-- on every descendant is wasteful and wrong once the wheels are welded.
			-- Async first (the non-deprecated API), plain call as fallback so this also
			-- runs in older Studio builds.
			local ok = false
			if info.Root.SetNetworkOwnerAsync then
				ok = pcall(function()
					info.Root:SetNetworkOwnerAsync(player)
				end)
			end
			if not ok and info.Root.SetNetworkOwner then
				ok = pcall(function()
					info.Root:SetNetworkOwner(player)
				end)
			end
			if not ok then
				warn("[VehicleSpawner] could not hand the car to " .. player.Name .. " - physics stays server-owned")
			end
		end)
	end
	return info
end

local spawned = {}
local demoTaken = false

local function spawnDemo(player)
	local model = CarBuilder.Build(nil).model
	model.Parent = Workspace
	local info = tag(model)
	if info == nil then
		announce("the built-in demo chassis failed to bind, which means CarBuilder is broken")
		return nil
	end
	prepare(model, info, player, SPAWN_AT)
	return model
end

local function claim()
	local model = findCandidate()
	if model == nil then
		return nil
	end
	model.Parent = Workspace
	return model
end

local function onPlayerAdded(player)
	local function give()
		-- an imported model always wins. Once one player has claimed it, everyone
		-- else gets their own demo chassis instead of sharing a single car.
		local model = claim()
		if model ~= nil then
			local info = tag(model)
			if info == nil then
				announce("found a model named " .. model.Name .. " but could not pick a chassis part from it")
				return
			end
			prepare(model, info, player, SPAWN_AT)
			spawned[player] = model
			announce(
				"bound "
					.. model.Name
					.. " -> root '"
					.. info.Root.Name
					.. "', "
					.. info.Wheels
					.. " wheel(s)"
					.. (info.Seat ~= nil and (", seat '" .. info.Seat.Name .. "'") or ", no seat (keyboard only)")
			)
			return
		end

		if demoTaken and player ~= nil then
			-- second player onward: no imported model to claim, so give them a demo
			-- car of their own rather than failing
			local demo = spawnDemo(player)
			if demo ~= nil then
				spawned[player] = demo
			end
			return
		end

		demoTaken = true
		local demo = spawnDemo(player)
		if demo ~= nil then
			spawned[player] = demo
			announce(
				"no imported model found, so the built-in demo chassis is bound -"
					.. " drop your Tesla model into Workspace or ServerStorage and rejoin to replace it"
			)
		end
	end

	-- Two waits, and both matter:
	--  * the city is generated asynchronously, and a car unanchored before the deck
	--    exists under it free-falls until the fall recovery resets it - which reads
	--    as "the physics is broken", not as "you spawned 3 seconds early"
	--  * a Toolbox paste lands a frame or two after join, so claiming too eagerly
	--    misses an imported model that is clearly present
	task.spawn(function()
		local ready = ReplicatedStorage:FindFirstChild("CityReady")
		if ready ~= nil and Workspace:FindFirstChild("GeneratedCity") == nil then
			ready.Event:Wait()
		end
		task.wait(1.5)
		give()
	end)
end

Players.PlayerAdded:Connect(onPlayerAdded)
for _, p in ipairs(Players:GetPlayers()) do
	task.spawn(onPlayerAdded, p)
end

Players.PlayerRemoving:Connect(function(player)
	spawned[player] = nil
end)
