--[[
	WantedService - stars, and the things that chase you.

	Two decisions worth stating because they are what make a wanted system feel
	like a game instead of a timer:

	* Stars are EARNED by behaviour and LOST by distance. The decay clock restarts
	  on every new offence, so hiding under the corridor for six seconds is worth
	  more than driving calmly - which is exactly the GTA beat we are stealing.
	* Cops are chase-and-pin, not shoot. A flying car cannot be shot at in a way
	  that reads fairly, but it CAN be forced to land: arrest only fires while you
	  are slow and touching a cruiser. So the punishment for a high star count is
	  "you must come down", which the flight model already makes interesting.

	Cop AI is a steering rate limit, not a path finder. It will clip through
	buildings sometimes; that is intentional. An imperfect chaser you can outdrive
	plays better than a perfect one you cannot, and a navmesh for a procedurally
	generated city is a whole other week.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Remotes = require(ReplicatedStorage:WaitForChild("Remotes"))
local W = Config.Wanted

local PlayerState = require(game:GetService("ReplicatedStorage"):WaitForChild("PlayerState"))

local TICK = 1 / 20
local TURN_RATE = 3.2 -- rad/s - the whole reason a cop can be shaken at speed
local DESPAWN_FAR = 900

local police = Instance.new("Folder")
police.Name = "Police"
police.Parent = Workspace

--------------------------------------------------------------------------------
-- car lookup
--------------------------------------------------------------------------------
local function carFor(player)
	local model = Workspace:FindFirstChild(player.Name .. "_Vehicle")
	if model == nil then
		for _, m in ipairs(Workspace:GetChildren()) do
			if m:IsA("Model") and m:GetAttribute("VehicleRoot") ~= nil then
				local owner = m:GetAttribute("Owner")
				if owner == nil or owner == player.Name then
					model = m
					break
				end
			end
		end
	end
	if model == nil or model.PrimaryPart == nil then
		return nil
	end
	local root = model.PrimaryPart
	local vel = root.AssemblyLinearVelocity
	return {
		Model = model,
		Pos = root.Position,
		Vel = vel,
		Speed = Vector3.new(vel.X, 0, vel.Z).Magnitude,
		Altitude = root.Position.Y,
		Grounded = model:GetAttribute("Grounded") ~= false,
	}
end

--------------------------------------------------------------------------------
-- cruisers
--------------------------------------------------------------------------------
local function makeCruiser(pos)
	local model = Instance.new("Model")
	model.Name = "Cruiser"

	local body = Instance.new("Part")
	body.Name = "Body"
	body.Size = Vector3.new(10, 3.2, 20)
	body.Color = Color3.fromRGB(22, 24, 30)
	body.Material = Enum.Material.Metal
	body.TopSurface = Enum.SurfaceType.Smooth
	body.BottomSurface = Enum.SurfaceType.Smooth
	body.CFrame = CFrame.new(pos)
	body.Parent = model

	local light = Instance.new("Part")
	light.Name = "Beacon"
	light.Size = Vector3.new(6, 1.2, 2)
	light.Material = Enum.Material.Neon
	light.Color = Color3.fromRGB(60, 120, 255)
	light.CanCollide = false
	light.CFrame = body.CFrame * CFrame.new(0, 2.2, 0)
	light.Parent = model

	model.PrimaryPart = body

	-- one LinearVelocity with world RelativeTo: cheap, stable, and it cannot
	-- tumble the way an unanchored box chasing a player at 195 studs/s does
	local drive = Instance.new("LinearVelocity")
	drive.Attachment0 = body:FindFirstChildOfClass("Attachment")
		or (function()
			local a = Instance.new("Attachment")
			a.Name = "WorldRef"
			a.Parent = body
			return a
		end)()
	drive.RelativeTo = Enum.ActuatorRelativeTo.World
	drive.VelocityFactor = 1
	drive.MaxForce = 1e9
	drive.Enabled = true
	drive.Parent = body

	-- keep it on the ground: without this the box skips over every kerb
	local hold = Instance.new("BodyPosition")
	hold.Attachment0 = drive.Attachment0
	hold.MaxForce = Vector3.new(0, 1e6, 0)
	hold.Position = Vector3.new(0, pos.Y, 0)
	hold.D = 200
	hold.P = 12000
	hold.Parent = body

	return {
		Model = model,
		Body = body,
		Drive = drive,
		Hold = hold,
		Beacon = light,
		Heading = math.atan2(-body.CFrame.LookVector.X, -body.CFrame.LookVector.Z),
	}
end

local function despawn(cop)
	if cop.Model ~= nil then
		cop.Model:Destroy()
	end
end

--------------------------------------------------------------------------------
-- per-player heat
--------------------------------------------------------------------------------
local state = {}

local function stateFor(player)
	local s = state[player]
	if s == nil then
		s = { cops = {}, airTime = 0, lastOffence = -1e9, cooldown = 0, bustCooldown = 0 }
		state[player] = s
	end
	return s
end

local function notify(player, kind, text)
	local ev = Remotes.Get("Notify")
	if ev ~= nil then
		ev:FireClient(player, kind, text)
	end
end

local function spawnCops(player, s, target, count)
	local have = #s.cops
	for i = have + 1, count do
		local ang = math.random() * math.pi * 2
		local r = 260 + math.random() * 120
		local pos = target + Vector3.new(math.cos(ang) * r, 0, math.sin(ang) * r)
		local cop = makeCruiser(Vector3.new(pos.X, 2, pos.Z))
		cop.Model.Parent = police
		s.cops[#s.cops + 1] = cop
	end
	-- shed extras quietly when stars drop
	while #s.cops > count do
		despawn(table.remove(s.cops))
	end
end

local function step(dt)
	for _, player in ipairs(Players:GetPlayers()) do
		local s = stateFor(player)
		local car = carFor(player)
		local stars = PlayerState.stars(player)
		local now = os.clock()

		if stars ~= nil and car ~= nil then
			-- ---- earn stars ----
			if car.Grounded and car.Altitude < 6 then
				s.airTime = 0
			else
				s.airTime = s.airTime + dt
			end

			local off = 0
			if s.airTime > W.AirborneGrace and car.Altitude < W.FlyAltitude then
				-- low and fast over the streets: the classic
				off = math.max(off, W.FlyInCity)
			end
			if car.Altitude >= W.FlyAltitude and car.Altitude < 220 and car.Speed > W.StreetSpeed then
				off = math.max(off, W.FlyInCity + 1)
			end
			if car.Speed > W.StreetSpeed and car.Grounded and car.Altitude < 12 then
				off = math.max(off, 1)
			end
			if off > 0 and now - s.lastOffence > 4 then
				s.lastOffence = now
				local before = stars.Value
				local after = PlayerState.addStars(player, off, true)
				if after ~= before then
					notify(player, "wanted", "+" .. off .. " star" .. (off > 1 and "s" or ""))
				end
			end

			-- ---- decay: nothing new, and no cruiser close enough to have seen you ----
			if stars.Value > 0 and now - s.lastSeen > W.DecayNoWitness and now - s.lastOffence > W.DecayNoWitness then
				s.lastSeen = now
				PlayerState.addStars(player, -1, false)
				notify(player, "wanted", "star lost")
			end

			-- ---- cops ----
			spawnCops(player, s, car.Pos, stars.Value * W.CopPerStar)
			for i = #s.cops, 1, -1 do
				local cop = s.cops[i]
				local to = car.Pos - cop.Body.Position
				local flat = Vector3.new(to.X, 0, to.Z)
				local dist = flat.Magnitude
				if dist > DESPAWN_FAR then
					despawn(cop)
					table.remove(s.cops, i)
				else
					if dist > 1 then
						local wantHeading = math.atan2(-flat.X, -flat.Z)
						local err = wantHeading - cop.Heading
						while err > math.pi do
							err = err - math.pi * 2
						end
						while err < -math.pi do
							err = err + math.pi * 2
						end
						local maxStep = TURN_RATE * dt
						cop.Heading = cop.Heading + math.max(-maxStep, math.min(maxStep, err))
					end
					local fwd = Vector3.new(-math.sin(cop.Heading), 0, -math.cos(cop.Heading))
					cop.Body.CFrame = CFrame.new(cop.Body.Position + Vector3.new(0, 0, 0), cop.Body.Position + fwd)
					cop.Drive.LineVelocity = Vector3.new(fwd.X * W.CopSpeed, 0, fwd.Z * W.CopSpeed)
					-- alternating beacon: a square wave is enough, no TweenService
					cop.Beacon.Color = (math.floor(now * 4) % 2 == 0) and Color3.fromRGB(60, 120, 255) or Color3.fromRGB(255, 60, 70)

					if dist < W.ArrestRange and car.Speed < W.ArrestSpeed and s.bustCooldown < now then
						s.bustCooldown = now + 6
						local cash = PlayerState.addCash(player, -W.ArrestFine)
						PlayerState.clearStars(player)
						for _, c in ipairs(s.cops) do
							despawn(c)
						end
						s.cops = {}
						notify(player, "busted", "BUSTED  -" .. W.ArrestFine .. "  (cash " .. cash .. ")")
						break
					end
				end
			end
			if #s.cops > 0 then
				s.lastSeen = now
			end
		end
	end
end

task.spawn(function()
	while true do
		task.wait(TICK)
		local ok, err = pcall(step, TICK)
		if not ok then
			warn("[WantedService] " .. tostring(err))
		end
	end
end)

Players.PlayerRemoving:Connect(function(player)
	local s = state[player]
	if s ~= nil then
		for _, cop in ipairs(s.cops) do
			despawn(cop)
		end
		state[player] = nil
	end
end)
