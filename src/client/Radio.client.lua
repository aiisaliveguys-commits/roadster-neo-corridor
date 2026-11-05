--[[
	Radio - one Sound, an explicit station index, and a DJ bump that actually
	interrupts instead of overlapping.

	Why a SoundGroup: the radio has to duck under dispatch VO, and with a group you
	lower one Volume instead of hunting for every Sound instance in the tree.

	Asset IDs come from Config.Radio, so uploading your own mp3s is a config edit
	and not a code edit. A zero id means "nothing uploaded yet" and the radio shows
	the station name on screen but plays silence, rather than erroring every frame
	in Output like an unhandled SoundId would.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local R = Config.Radio

local group = SoundService:FindFirstChild("RadioGroup")
if group == nil then
	group = Instance.new("SoundGroup")
	group.Name = "RadioGroup"
	group.Volume = R.Volume
	group.Parent = SoundService
end

local sound = Instance.new("Sound")
sound.Name = "Radio"
sound.Looped = true
sound.Volume = 1
sound.Parent = group

local intro = Instance.new("Sound")
intro.Name = "DJIntro"
intro.Looped = false
intro.Volume = 1
intro.Parent = group

local station = 1
local on = false
local adTimer = 0

local function stations()
	return R.Stations or {}
end

local function hasAudio(id)
	return type(id) == "number" and id > 0
end

local function playTrack()
	local list = stations()
	local st = list[station]
	if st == nil then
		sound.SoundId = ""
		return
	end
	local tracks = st.Tracks or {}
	local id = tracks[1]
	if hasAudio(id) then
		sound.SoundId = "rbxassetid://" .. id
		sound.TimePosition = 0
		if on then
			sound:Play()
		end
	else
		sound:Stop()
		sound.SoundId = ""
	end
end

local function announce()
	local list = stations()
	local st = list[station]
	if st == nil then
		return
	end
	if hasAudio(R.DJIntro) then
		sound.Volume = 0.25 -- duck, do not stop: a dead-air cut reads as a bug
		intro.SoundId = "rbxassetid://" .. R.DJIntro
		intro:Play()
		intro.Ended:Once(function()
			sound.Volume = 1
		end)
	end
end

local function cycle()
	local list = stations()
	if #list == 0 then
		return
	end
	station = station % #list + 1
	playTrack()
	announce()
end

local function toggle()
	on = not on
	if on then
		playTrack()
		sound:Play()
		announce()
	else
		sound:Stop()
	end
end

UserInputService.InputBegan:Connect(function(input, processed)
	if processed then
		return
	end
	if input.KeyCode == R.ToggleKey then
		toggle()
	elseif input.KeyCode == R.StationKey then
		cycle()
	end
end)

-- a station card, so the radio is legible even while the audio is still the
-- placeholder asset ids (i.e. before you upload your own mp3s)
local player = Players.LocalPlayer
local gui = Instance.new("ScreenGui")
gui.Name = "RadioCard"
gui.ResetOnSpawn = false
gui.Parent = player:WaitForChild("PlayerGui")

local card = Instance.new("Frame")
card.Name = "Card"
card.BackgroundColor3 = Color3.fromRGB(8, 10, 16)
card.BackgroundTransparency = 0.25
card.BorderSizePixel = 0
card.Size = UDim2.fromOffset(210, 44)
card.Position = UDim2.new(0, 24, 1, -92)
card.Visible = false
card.Parent = gui
local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0, 8)
corner.Parent = card

local nameL = Instance.new("TextLabel")
nameL.BackgroundTransparency = 1
nameL.Size = UDim2.new(1, -16, 0, 20)
nameL.Position = UDim2.new(0, 8, 0, 6)
nameL.Font = Enum.Font.GothamBold
nameL.TextXAlignment = Enum.TextXAlignment.Left
nameL.TextSize = 15
nameL.Text = ""
nameL.Parent = card

local genreL = Instance.new("TextLabel")
genreL.BackgroundTransparency = 1
genreL.Size = UDim2.new(1, -16, 0, 14)
genreL.Position = UDim2.new(0, 8, 0, 25)
genreL.Font = Enum.Font.Gotham
genreL.TextXAlignment = Enum.TextXAlignment.Left
genreL.TextColor3 = Color3.fromRGB(150, 160, 175)
genreL.TextSize = 12
genreL.Text = ""
genreL.Parent = card

local function showCard(seconds)
	local list = stations()
	local st = list[station]
	if st == nil then
		return
	end
	nameL.Text = on and st.Name or (st.Name .. "  (off)")
	nameL.TextColor3 = st.Color or Config.HUD.Accent
	genreL.Text = (st.Genre or "") .. (hasAudio(R.DJIntro) and "" or "   |   audio: placeholder ids")
	card.Visible = true
	task.delay(seconds or 2.4, function()
		card.Visible = false
	end)
end

UserInputService.InputBegan:Connect(function(input, processed)
	if not processed and (input.KeyCode == R.ToggleKey or input.KeyCode == R.StationKey) then
		showCard()
	end
end)

-- ad bumps: the GTA radio joke only works if it interrupts at an awkward moment,
-- so this is a randomised gap and not a fixed jingle timer
task.spawn(function()
	while true do
		task.wait(1)
		if on and hasAudio(R.AdBump) then
			adTimer = adTimer + 1
			if adTimer > 180 and math.random() < 0.02 then
				adTimer = 0
				sound.Volume = 0.2
				intro.SoundId = "rbxassetid://" .. R.AdBump
				intro:Play()
				intro.Ended:Once(function()
					sound.Volume = 1
				end)
			end
		end
	end
end)

showCard(3)
