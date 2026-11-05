--[[
	MissionService - a ring chain, paid per ring.

	Rings are laid along ROAD LINES, not through buildings. That is not
	decoration: a checkpoint chain that cuts across blocks teaches the player to
	fly, and this game is supposed to be about a car that can fly but does not
	have to. Ground-level rings on the streets make the driving model the fast
	route and the corridor the risky shortcut.

	GroundOnlyAfter is the rule that keeps it that way: from ring N onward the car
	must be on wheels when it crosses. Enforced on the server, because a client
	rule in a network-owned-assembly game is just a suggestion.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Remotes = require(ReplicatedStorage:WaitForChild("Remotes"))
local M = Config.Mission

local PlayerState = require(game:GetService("ReplicatedStorage"):WaitForChild("PlayerState"))

local ringsFolder = Instance.new("Folder")
ringsFolder.Name = "Missions"
ringsFolder.Parent = Workspace

local pitch = Config.City.Block + Config.City.Road
local centre = (Config.City.GridSize - 1) / 2

local function lane(i)
	-- snap an index onto the road gutter between blocks
	return (i - centre) * pitch - pitch / 2
end

local function makeRing(pos, index)
	local ring = Instance.new("Part")
	ring.Name = "Ring_" .. index
	ring.Shape = Enum.PartType.Cylinder
	ring.Size = Vector3.new(2, M.RingRadius * 2, M.RingRadius * 2)
	ring.Material = Enum.Material.Neon
	ring.Color = Color3.fromRGB(0, 229, 255)
	ring.Transparency = 0.35
	ring.CanCollide = false
	ring.CanQuery = false
	ring.Anchored = true
	ring.CFrame = CFrame.new(pos) * CFrame.Angles(0, 0, math.rad(90))
	ring.Parent = ringsFolder
	return ring
end

local function buildRoute(seed)
	local rng = seed
	local function rnd()
		rng = (rng * 1103515245 + 12345) % 2147483648
		return rng / 2147483648
	end
	local route = {}
	local i = 0
	while #route < M.Rings and i < 200 do
		i = i + 1
		local ax = math.floor(rnd() * Config.City.GridSize) - centre
		local az = math.floor(rnd() * Config.City.GridSize) - centre
		local pos = Vector3.new(lane(ax), 6, lane(az))
		local ok = true
		if #route > 0 then
			local prev = route[#route]
			local d = (pos - prev).Magnitude
			-- not too close (no free chain), not too far (no unreachable ring)
			if d < 120 or d > 700 then
				ok = false
			end
		end
		if ok then
			route[#route + 1] = pos
		end
	end
	return route
end

local state = {}

local function stateFor(player)
	local s = state[player]
	if s == nil then
		s = { active = false, index = 0, route = nil, rings = {}, deadline = 0 }
		state[player] = s
	end
	return s
end

local function clearRings(s)
	for _, r in ipairs(s.rings) do
		r:Destroy()
	end
	s.rings = {}
end

local function notify(player, kind, text)
	local ev = Remotes.Get("Notify")
	if ev ~= nil then
		ev:FireClient(player, kind, text)
	end
end

local function finish(player, s, completed)
	clearRings(s)
	s.active = false
	s.index = 0
	if completed then
		local cash = PlayerState.addCash(player, M.FinishReward)
		notify(player, "mission", "ROUTE CLEARED  +" .. M.FinishReward .. "  (cash " .. cash .. ")")
	else
		notify(player, "mission", "route expired")
	end
end

local function carFor(player)
	for _, m in ipairs(Workspace:GetChildren()) do
		if m:IsA("Model") and m:GetAttribute("VehicleRoot") ~= nil and m.PrimaryPart ~= nil then
			local owner = m:GetAttribute("Owner")
			if owner == nil or owner == player.Name then
				return m, m.PrimaryPart
			end
		end
	end
	return nil
end

local function start(player)
	local s = stateFor(player)
	if s.active then
		finish(player, s, false)
	end
	s.route = buildRoute(os.time() % 2147483647)
	clearRings(s)
	for i, pos in ipairs(s.route) do
		s.rings[i] = makeRing(pos, i)
	end
	-- only the current ring is bright; the rest are dimmed ghosts, so the player
	-- always knows which one counts without reading a number
	for i = 2, #s.rings do
		s.rings[i].Transparency = 0.8
	end
	s.index = 1
	s.active = true
	s.deadline = os.clock() + M.TimeLimit
	notify(player, "mission", "route started - " .. #s.route .. " rings, " .. M.TimeLimit .. "s")
end

local launch = Remotes.Get("LaunchMission")
if launch ~= nil then
	launch.OnServerEvent:Connect(function(player)
		task.spawn(start, player)
	end)
end

task.spawn(function()
	while true do
		task.wait(1 / 20)
		local ok, err = pcall(function()
			local now = os.clock()
			for _, player in ipairs(Players:GetPlayers()) do
				local s = state[player]
				if s ~= nil and s.active then
					if now > s.deadline then
						finish(player, s, false)
					else
						local model, root = carFor(player)
						if root ~= nil then
							local target = s.rings[s.index]
							if target ~= nil then
								-- proximity, not "inside the torus": forgiving, and it
								-- does not depend on the ring being oriented so you can
								-- thread it at 200 studs/s. The ring is a marker you
								-- drive near, not a hoop you must hit dead centre.
								local d = (root.Position - target.Position).Magnitude
								if d < M.RingRadius + 6 then
									if s.index > M.GroundOnlyAfter and root.AssemblyLinearVelocity.Magnitude < 400 then
										local grounded = model:GetAttribute("Grounded")
										if grounded == false then
											notify(player, "mission", "landed wheels only past ring " .. M.GroundOnlyAfter)
										else
											local cash = PlayerState.addCash(player, M.RewardPerRing)
											target.Transparency = 0.95
											s.index = s.index + 1
											local nextRing = s.rings[s.index]
											if nextRing ~= nil then
												nextRing.Transparency = 0.35
											end
											notify(player, "mission", ("ring %d/%d  +%d"):format(s.index - 1, #s.route, M.RewardPerRing))
											if s.index > #s.route then
												finish(player, s, true)
											end
										end
									else
										notify(player, "mission", "too fast to bank a ring")
									end
								end
							end
						end
					end
				end
			end
		end)
		if not ok then
			warn("[MissionService] " .. tostring(err))
		end
	end
end)

Players.PlayerRemoving:Connect(function(player)
	local s = state[player]
	if s ~= nil then
		clearRings(s)
		state[player] = nil
	end
end)
