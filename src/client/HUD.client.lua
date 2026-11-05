--[[
	HUD - speed, mode, boost, stars, cash, minimap, toasts.

	Everything it displays is read from Model attributes the controller already
	writes, so the HUD has no state of its own and cannot drift out of sync with
	the simulation. That is the whole reason the controller publishes attributes in
	the first place.

	One layout choice worth defending: the mode pill is the loudest element on
	screen. In a car that can fly, "am I on wheels or on thrusters" is the single
	most important thing to know, and it is exactly what you lose sight of when you
	are looking at a speed dial.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local H = Config.HUD
local Car = Config.Car

local player = Players.LocalPlayer
local gui = Instance.new("ScreenGui")
gui.Name = "CyberRoadsterHUD"
gui.ResetOnSpawn = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.IgnoreGuiInset = true
gui.Parent = player:WaitForChild("PlayerGui")

local function make(cls, props)
	local o = Instance.new(cls)
	for k, v in pairs(props) do
		o[k] = v
	end
	o.Parent = props._parent or gui
	return o
end

local function corner(parent)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, 8)
	c.Parent = parent
	return c
end

-- ---------------------------------------------------------------- background
local function panel(props)
	local f = make("Frame", {
		BackgroundColor3 = Color3.fromRGB(8, 10, 16),
		BackgroundTransparency = 0.25,
		BorderSizePixel = 0,
		Active = false,
	})
	corner(f)
	for k, v in pairs(props) do
		f[k] = v
	end
	return f
end

-- ---------------------------------------------------------------- speed dial
local dial = panel({
	Size = UDim2.fromOffset(H.SpeedoSize, H.SpeedoSize * 0.42),
	Position = UDim2.new(0, 24, 1, -24),
	AnchorPoint = Vector2.new(0, 1),
})
local speedText = make("TextLabel", {
	Parent = dial,
	BackgroundTransparency = 1,
	Size = UDim2.new(1, -18, 0.6, 0),
	Position = UDim2.new(0, 9, 0, 4),
	Font = Enum.Font.RobotoMono,
	TextXAlignment = Enum.TextXAlignment.Left,
	TextColor3 = H.Accent,
	Text = "0",
	TextSize = 46,
})
local unitText = make("TextLabel", {
	Parent = dial,
	BackgroundTransparency = 1,
	Size = UDim2.new(0.6, 0, 0.34, 0),
	Position = UDim2.new(0, 11, 0.58, 0),
	Font = Enum.Font.Gotham,
	TextXAlignment = Enum.TextXAlignment.Left,
	TextColor3 = Color3.fromRGB(150, 160, 175),
	Text = "studs/s",
	TextSize = 13,
})
local altText = make("TextLabel", {
	Parent = dial,
	BackgroundTransparency = 1,
	Size = UDim2.new(0.42, 0, 0.34, 0),
	Position = UDim2.new(0.56, 0, 0.58, 0),
	Font = Enum.Font.Gotham,
	TextXAlignment = Enum.TextXAlignment.Right,
	TextColor3 = Color3.fromRGB(150, 160, 175),
	Text = "alt 0",
	TextSize = 13,
	Visible = H.ShowAltitude,
})
local bar = make("Frame", {
	Parent = dial,
	BackgroundColor3 = Color3.fromRGB(255, 255, 255),
	BackgroundTransparency = 0.72,
	BorderSizePixel = 0,
	Size = UDim2.new(1, -18, 0, 5),
	Position = UDim2.new(0, 9, 0, 0),
	AnchorPoint = Vector2.new(0, 1),
})
corner(bar)
local barFill = make("Frame", {
	Parent = bar,
	BackgroundColor3 = H.Accent,
	BorderSizePixel = 0,
	Size = UDim2.new(0, 0, 1, 0),
})
corner(barFill)
local boostBar = make("Frame", {
	Parent = dial,
	BackgroundColor3 = Color3.fromRGB(255, 255, 255),
	BackgroundTransparency = 0.8,
	BorderSizePixel = 0,
	Size = UDim2.new(1, -18, 0, 3),
	Position = UDim2.new(0, 9, 1, -20),
	AnchorPoint = Vector2.new(0, 1),
})
corner(boostBar)
local boostFill = make("Frame", {
	Parent = boostBar,
	BackgroundColor3 = Color3.fromRGB(255, 170, 60),
	BorderSizePixel = 0,
	Size = UDim2.new(1, 0, 1, 0),
})
corner(boostFill)

-- ---------------------------------------------------------------- mode pill
local pill = panel({
	Size = UDim2.fromOffset(150, 30),
	Position = UDim2.new(0.5, 0, 1, -22),
	AnchorPoint = Vector2.new(0.5, 1),
})
local pillText = make("TextLabel", {
	Parent = pill,
	BackgroundTransparency = 1,
	Size = UDim2.new(1, 0, 1, 0),
	Font = Enum.Font.GothamBold,
	TextColor3 = H.Accent,
	Text = "GROUND",
	TextSize = 15,
})
local keyHint = make("TextLabel", {
	Parent = gui,
	BackgroundTransparency = 1,
	Size = UDim2.new(1, 0, 0, 16),
	Position = UDim2.new(0, 0, 1, -52),
	AnchorPoint = Vector2.new(0, 1),
	Font = Enum.Font.Gotham,
	TextColor3 = Color3.fromRGB(120, 130, 145),
	TextSize = 12,
	Text = ("W/S drive  A/D steer  SPACE climb  %s toggle aero  SHIFT boost  H radio  R station  M mission"):format(
		Car.ToggleKeyCode.Name
	),
	TextXAlignment = Enum.TextXAlignment.Center,
})

-- ---------------------------------------------------------------- stars + cash
local starBox = make("Frame", {
	Parent = gui,
	BackgroundTransparency = 1,
	Size = UDim2.fromOffset(140, 22),
	Position = UDim2.new(1, -24, 0, 62),
	AnchorPoint = Vector2.new(1, 0),
})
make("UIListLayout", {
	Parent = starBox,
	FillDirection = Enum.FillDirection.Horizontal,
	Padding = UDim.new(0, 2),
	SortOrder = Enum.SortOrder.LayoutOrder,
})
local starFrames = {}
for i = 1, Config.Wanted.MaxStars do
	local st = make("TextLabel", {
		Parent = starBox,
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(20, 20),
		LayoutOrder = i,
		Font = Enum.Font.GothamBold,
		Text = "*",
		TextSize = 22,
		TextColor3 = Color3.fromRGB(70, 74, 86),
		TextTransparency = 0.4,
	})
	starFrames[i] = st
end
local cashText = make("TextLabel", {
	Parent = gui,
	BackgroundTransparency = 1,
	Size = UDim2.fromOffset(160, 24),
	Position = UDim2.new(1, -24, 0, 30),
	AnchorPoint = Vector2.new(1, 0),
	Font = Enum.Font.GothamBold,
	TextXAlignment = Enum.TextXAlignment.Right,
	TextColor3 = H.Cash,
	Text = "$0",
	TextSize = 20,
})
local modeGlow = make("Frame", {
	Parent = gui,
	BackgroundColor3 = H.Danger,
	BorderSizePixel = 0,
	BackgroundTransparency = 1,
	Size = UDim2.new(1, 0, 1, 0),
})

-- ---------------------------------------------------------------- minimap
local map = panel({
	Size = UDim2.fromOffset(H.MinimapSize, H.MinimapSize),
	Position = UDim2.new(1, -24, 0, 92),
	AnchorPoint = Vector2.new(1, 0),
})
make("UICorner", { Parent = map, CornerRadius = UDim.new(1, 0) })
local mapClip = make("Frame", {
	Parent = map,
	BackgroundTransparency = 1,
	Size = UDim2.new(1, -8, 1, -8),
	Position = UDim2.new(0, 4, 0, 4),
})
make("UICorner", { Parent = mapClip, CornerRadius = UDim.new(1, 0) })
local rot = make("Frame", {
	Parent = mapClip,
	BackgroundTransparency = 1,
	Size = UDim2.fromScale(1, 1),
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.new(0.5, 0, 0.5, 0),
	Rotation = 0,
})
local me = make("Frame", {
	Parent = rot,
	BackgroundColor3 = H.Accent,
	BorderSizePixel = 0,
	Size = UDim2.fromOffset(7, 7),
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
})
make("UICorner", { Parent = me, CornerRadius = UDim.new(1, 0) })
-- a wedge so you can read which way you are facing without a needle
local nose = make("Frame", {
	Parent = rot,
	BackgroundColor3 = H.Accent,
	BackgroundTransparency = 0.55,
	BorderSizePixel = 0,
	Size = UDim2.fromOffset(2, 46),
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.fromScale(0.5, 0.5),
})
local copsBox = make("Frame", {
	Parent = mapClip,
	BackgroundTransparency = 1,
	Size = UDim2.fromScale(1, 1),
})

-- ---------------------------------------------------------------- toasts
local toastBox = make("Frame", {
	Parent = gui,
	BackgroundTransparency = 1,
	Size = UDim2.fromOffset(360, 120),
	Position = UDim2.new(0.5, 0, 0, 40),
	AnchorPoint = Vector2.new(0.5, 0),
})
make("UIListLayout", {
	Parent = toastBox,
	FillDirection = Enum.FillDirection.Vertical,
	Padding = UDim.new(0, 4),
	HorizontalAlignment = Enum.HorizontalAlignment.Center,
	SortOrder = Enum.SortOrder.LayoutOrder,
})

local function toast(text, color)
	local t = make("TextLabel", {
		Parent = toastBox,
		BackgroundColor3 = Color3.fromRGB(8, 10, 16),
		BackgroundTransparency = 0.2,
		BorderSizePixel = 0,
		Size = UDim2.fromOffset(340, 26),
		LayoutOrder = os.clock() * 1000 % 100000,
		Font = Enum.Font.GothamMedium,
		Text = text,
		TextColor3 = color or Color3.fromRGB(235, 240, 250),
		TextSize = 14,
	})
	corner(t)
	task.spawn(function()
		for i = 0, 1, 0.04 do
			t.BackgroundTransparency = 0.2 + i * 0.8
			t.TextTransparency = i * 0.9
			task.wait(0.03)
		end
		t:Destroy()
	end)
end

local Remotes = require(ReplicatedStorage:WaitForChild("Remotes"))
local notifyEv = Remotes.Get("Notify")
if notifyEv ~= nil then
	notifyEv.OnClientEvent:Connect(function(kind, text)
		local col = Color3.fromRGB(235, 240, 250)
		if kind == "wanted" or kind == "busted" then
			col = H.Danger
		elseif kind == "mission" then
			col = H.Accent
		elseif kind == "cash" then
			col = H.Cash
		end
		toast(text, col)
	end)
end

-- ---------------------------------------------------------------- data wiring
local carModel = nil
local function findCar()
	for _, m in ipairs(Workspace:GetChildren()) do
		if m:IsA("Model") and m:GetAttribute("VehicleRoot") ~= nil then
			return m
		end
	end
	return nil
end

local stats = player:FindFirstChild("leaderstats") or player:WaitForChild("leaderstats", 10)
local cashVal = stats and stats:FindFirstChild("Cash")
local starVal = stats and stats:FindFirstChild("Wanted")
if cashVal ~= nil then
	cashVal:GetPropertyChangedSignal("Value"):Connect(function()
		cashText.Text = "$" .. cashVal.Value
	end)
	cashText.Text = "$" .. cashVal.Value
end
if starVal ~= nil then
	local function paintStars()
		for i, f in ipairs(starFrames) do
			local on = i <= starVal.Value
			f.TextColor3 = on and H.Danger or Color3.fromRGB(70, 74, 86)
			f.TextTransparency = on and 0 or 0.4
		end
	end
	starVal:GetPropertyChangedSignal("Value"):Connect(paintStars)
	paintStars()
end

local MAP_RANGE = 620 -- studs shown from centre to edge

local function update()
	carModel = carModel or findCar()
	if carModel == nil or carModel.PrimaryPart == nil then
		return
	end
	local speed = carModel:GetAttribute("Speed") or 0
	local alt = carModel:GetAttribute("Altitude") or 0
	local mode = carModel:GetAttribute("Mode") or "GROUND"
	local boost = carModel:GetAttribute("Boost") or Car.BoostCapacity

	speedText.Text = tostring(math.floor(speed))
	barFill.Size = UDim2.fromScale(math.min(1, speed / Car.FlightSpeed), 1)
	boostFill.Size = UDim2.fromScale(math.max(0, math.min(1, boost / Car.BoostCapacity)), 1)
	if H.ShowAltitude then
		altText.Text = "alt " .. math.floor(alt)
	end
	pillText.Text = mode
	if mode == "FLIGHT" then
		pillText.TextColor3 = H.Accent
		pill.BackgroundColor3 = Color3.fromRGB(0, 34, 48)
	elseif mode == "LANDING" then
		pillText.TextColor3 = Color3.fromRGB(255, 170, 60)
		pill.BackgroundColor3 = Color3.fromRGB(40, 26, 6)
	else
		pillText.TextColor3 = Color3.fromRGB(200, 210, 225)
		pill.BackgroundColor3 = Color3.fromRGB(14, 16, 22)
	end

	-- wanted glow: cheap, and it is visible in peripheral vision where a star
	-- count is not
	if starVal ~= nil and starVal.Value > 0 then
		modeGlow.BackgroundTransparency = 1 - math.min(0.16, 0.035 * starVal.Value)
	else
		modeGlow.BackgroundTransparency = 1
	end

	-- minimap
	local pos = carModel.PrimaryPart.Position
	local look = carModel.PrimaryPart.CFrame.LookVector
	rot.Rotation = math.deg(math.atan2(-look.X, -look.Z)) + 180
	local mapSize = H.MinimapSize - 8
	for _, ch in ipairs(copsBox:GetChildren()) do
		ch:Destroy()
	end
	local pf = Workspace:FindFirstChild("Police")
	if pf ~= nil then
		for _, cop in ipairs(pf:GetChildren()) do
			local b = cop:FindFirstChild("Body")
			if b ~= nil then
				local rel = b.Position - pos
				local dx, dz = rel.X, rel.Z
				-- rotate the world into the player's frame so the map turns with
				-- the car instead of the car dot spinning on a fixed map
				local a = math.atan2(-look.X, -look.Z)
				local rx = dx * math.cos(a) - dz * math.sin(a)
				local rz = dx * math.sin(a) + dz * math.cos(a)
				local sx = 0.5 + (rz / MAP_RANGE) * 0.5
				local sy = 0.5 + (rx / MAP_RANGE) * 0.5
				if sx >= -0.05 and sx <= 1.05 and sy >= -0.05 and sy <= 1.05 then
					local dot = make("Frame", {
						Parent = copsBox,
						BackgroundColor3 = H.Danger,
						BorderSizePixel = 0,
						Size = UDim2.fromOffset(6, 6),
						AnchorPoint = Vector2.new(0.5, 0.5),
						Position = UDim2.fromScale(sx, sy),
					})
					make("UICorner", { Parent = dot, CornerRadius = UDim.new(1, 0) })
				end
			end
		end
	end
end

RunService.RenderStepped:Connect(update)

-- mission launch key, so the slice is playable without a GUI button
local UIS = game:GetService("UserInputService")
UIS.InputBegan:Connect(function(input, processed)
	if processed then
		return
	end
	if input.KeyCode == Enum.KeyCode.M then
		local ev = Remotes.Get("LaunchMission")
		if ev ~= nil then
			ev:FireServer()
		end
	end
end)
