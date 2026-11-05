--[[
	Bootstrap - the only thing the client has to do.

	CarController reads its own input (keyboard when unoccupied, VehicleSeat when
	occupied) and publishes its state as Model attributes, so there is no "driving
	LocalScript" to write and nothing to keep in sync between two places. This
	script's whole job is to find the car and instantiate the controller exactly
	once per car.

	The once-per-car guard is not paranoia: the spawner re-parents the model, and a
	second controller on the same assembly means two LinearVelocity + two
	AngularVelocity fighting each other, which shows up as a car that jitters and
	will absolutely not reproduce from reading the physics code.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local CarController = require(ReplicatedStorage:WaitForChild("CarController"))

local player = Players.LocalPlayer

local active = nil
local boundCar = nil

local function attach(car)
	if car:GetAttribute("VehicleRoot") == nil then
		return
	end
	if boundCar == car then
		return
	end
	if active ~= nil then
		active:Destroy()
		active = nil
	end
	boundCar = car

	-- ServerAuthoritative = true means the server runs the physics and replicates
	-- the assembly; instantiating here as well would double-solve it.
	if Config.ServerAuthoritative then
		print("[Bootstrap] server-authoritative: client controller not instantiated")
		return
	end

	local ok, ctrl = pcall(CarController.new, car)
	if not ok then
		warn("[Bootstrap] CarController.new failed: " .. tostring(ctrl))
		return
	end
	active = ctrl
	ctrl:Start()
	local bound = ctrl:bindFlightKey()
	if bound ~= false then
		print("[Bootstrap] aero bound to " .. Config.Car.ToggleKeyCode.Name)
	end
	print("[Bootstrap] driving " .. car.Name)
end

local function scan()
	for _, m in ipairs(Workspace:GetChildren()) do
		if m:IsA("Model") and m:GetAttribute("VehicleRoot") ~= nil then
			local owner = m:GetAttribute("Owner")
			if owner == nil or owner == player.Name then
				attach(m)
				return true
			end
		end
	end
	return false
end

if not scan() then
	-- the spawner tags the root and sets VehicleRoot, so watching that single
	-- attribute is both cheaper and race-free compared with polling children
	Workspace.DescendantAdded:Connect(function(d)
		if d:IsA("Model") then
			task.defer(scan)
		end
	end)
	-- and a slow poll as a belt-and-braces: attribute writes do not always raise
	-- DescendantAdded on an already-parented model
	task.spawn(function()
		while active == nil and not Config.ServerAuthoritative do
			task.wait(0.5)
			if scan() then
				break
			end
		end
	end)
end
