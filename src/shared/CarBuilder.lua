--[[
	CarBuilder - a placeholder chassis, used ONLY when no model has been imported.

	Read VehicleSpawner first: an imported Tesla model always wins. This exists so
	that opening the place file in Studio is enough to drive - otherwise the first
	run of a freshly built game is "an empty city and a toast telling me to go
	import something", which is not a playable thing to hand someone.

	Geometry is not decoration, it IS the suspension tuning:

  The controller reads, per wheel: Radius = max(Size.Y, Size.Z) * 0.5, and a hub
  offset taken from the wheel's position relative to the chassis. Equilibrium is
  where the spring force equals 1 g, i.e. deflect == RideSag, i.e.

	  hubHeight = Radius + SuspensionTravel - RideSag + RideSag = R + travel

  so hub 1.6 with R 1.4 sits the chassis centre 3.6 + 1.6 = 5.2 above the deck.
  Those numbers are the ones the headless suite already drives, which is the point:
  the demo chassis and the tested chassis have to agree or "passes in CI" and
  "feels right in Studio" are two different physics setups.

	Wheels are boxes on purpose. A Cylinder wheel needs CanCollide=false plus
	Massless plus a rotation, and a chamfered box reads closer to a Cybertruck than
	a smooth tyre would anyway.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local C = Config.Car

local CarBuilder = {}

local HUB_Y = 1.6
local WHEEL_R = 1.4
local HUB_X, HUB_Z = 3.1, 3.9

local function part(props)
	local p = Instance.new("Part")
	p.Anchored = false
	p.CanCollide = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for k, v in pairs(props) do
		if k ~= "_parent" then
			p[k] = v
		end
	end
	if props._parent then
		p.Parent = props._parent
	end
	return p
end

function CarBuilder.Build(targetPosition)
	local model = Instance.new("Model")
	model.Name = "ROADSTER_DEMO"

	local chassis = part({
		Name = "Chassis",
		Size = Vector3.new(6.4, 1.6, 13.5), -- matches the wheel track below
		Color = Color3.fromRGB(168, 172, 178),
		Material = Enum.Material.Metal,
		ReflectionIntensity = 0.6,
		_parent = model,
	})

	-- the angular bed and nose. Non-colliding: the assembly's collision is the
	-- chassis box, and letting a cosmetic wedge participate in contact resolution
	-- means the car can catch a kerb on an invisible corner
	local bed = part({
		Name = "Bed",
		Size = Vector3.new(6.0, 2.0, 5.4),
		Color = Color3.fromRGB(160, 164, 170),
		Material = Enum.Material.Metal,
		CFrame = CFrame.new(0, 1.4, 3.6),
		CanCollide = false,
		_parent = model,
	})
	local nose = part({
		Name = "Nose",
		Size = Vector3.new(6.0, 1.0, 4.0),
		Color = Color3.fromRGB(160, 164, 170),
		Material = Enum.Material.Metal,
		CFrame = CFrame.new(0, 0.5, -5.4) * CFrame.Angles(math.rad(12), 0, 0),
		CanCollide = false,
		_parent = model,
	})
	local cabin = part({
		Name = "Cabin",
		Size = Vector3.new(5.6, 1.7, 6.2),
		Color = Color3.fromRGB(38, 42, 52),
		Material = Enum.Material.Glass,
		Transparency = 0.35,
		CFrame = CFrame.new(0, 1.6, -0.6),
		CanCollide = false,
		_parent = model,
	})
	local bar = part({
		Name = "LightBar",
		Size = Vector3.new(5.8, 0.3, 0.4),
		Color = Color3.fromRGB(255, 250, 220),
		Material = Enum.Material.Neon,
		CFrame = CFrame.new(0, 0.45, -6.6),
		CanCollide = false,
		_parent = model,
	})

	-- wheels, in a folder: the controller deliberately only looks inside
	-- "CarParts", so a model whose wheels are scattered loose has to be
	-- restructured the same way (see VehicleSpawner.Restructure)
	local carParts = Instance.new("Folder")
	carParts.Name = "CarParts"
	carParts.Parent = model

	local spots = {
		Vector3.new(-HUB_X, HUB_Y, -HUB_Z),
		Vector3.new(HUB_X, HUB_Y, -HUB_Z),
		Vector3.new(-HUB_X, HUB_Y, HUB_Z),
		Vector3.new(HUB_X, HUB_Y, HUB_Z),
	}
	for i, off in ipairs(spots) do
		local w = Instance.new("Part")
		w.Name = "Wheel" .. i
		w.Size = Vector3.new(1.1, WHEEL_R * 2, WHEEL_R * 2)
		w.Color = Color3.fromRGB(24, 24, 26)
		w.Material = Enum.Material.Rubber
		-- the controller flips these itself; set them here as well so the model is
		-- correct even if it is inspected before the controller starts
		w.CanCollide = false
		w.CanQuery = false
		w.CanTouch = false
		w.Massless = true
		w.Parent = carParts
		w.CFrame = CFrame.new(chassis.Position + off)
		w:SetAttribute("Role", "Wheel")
	end

	local seat = Instance.new("VehicleSeat")
	seat.Name = "Seat" -- the controller looks up "Seat" by name, not by class
	seat.Size = Vector3.new(2.2, 0.5, 2.4)
	seat.Color = Color3.fromRGB(30, 32, 36)
	seat.Material = Enum.Material.SmoothPlastic
	seat.Occupant = nil
	seat.Parent = model
	seat.CFrame = chassis.CFrame * CFrame.new(-1.5, 1.35, -1.4)
	seat:SetAttribute("Role", "Seat")

	model.PrimaryPart = chassis
	model:SetAttribute("VehicleRoot", chassis.Name)
	model:SetAttribute("Grounded", true)
	model:SetAttribute("Mode", "GROUND")

	local out = { model = model, body = chassis, seat = seat, wheels = carParts }
	if targetPosition then
		-- lift by exactly the rest height so the car settles two studs instead of
		-- dropping through the deck and triggering the fall recovery
		model:PivotTo(CFrame.new(targetPosition + Vector3.new(0, HUB_Y + WHEEL_R + C.SuspensionTravel + 2, 0)))
	end
	-- Returns a table, not a bare Model: the headless harness needs the chassis and
	-- seat handles to drive it. VehicleSpawner uses .model.
	return out, model
end

return CarBuilder
