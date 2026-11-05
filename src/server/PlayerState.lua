--[[
	PlayerState - one owner for "how much money" and "how many stars".

	WantedService needs to raise and decay stars, MissionService needs to pay
	rewards, and a third service that also wrote these values is how you get the
	bug where a mission reward wipes a fine. Both live in leaderstats because
	Roblox renders that folder automatically: the HUD gets the default leaderboard
	for free and only has to draw the stars.

	Accessors are read by name from anywhere: the client reaches them through
	player.leaderstats, which is replicated, so the HUD never needs a remote for
	state that a Value object already carries.
]]

local Players = game:GetService("Players")

local Config = require(game:GetService("ReplicatedStorage"):WaitForChild("Config"))

local PlayerState = {}

local MAX = Config.Wanted.MaxStars

function PlayerState.attach(player)
	local stats = player:FindFirstChild("leaderstats")
	if stats == nil then
		stats = Instance.new("Folder")
		stats.Name = "leaderstats"
		stats.Parent = player
	end

	local function ensure(name, className, start)
		local v = stats:FindFirstChild(name)
		if v == nil then
			v = Instance.new(className)
			v.Name = name
			v.Value = start
			v.Parent = stats
		end
		return v
	end

	ensure("Cash", "IntValue", 0)
	local stars = ensure("Wanted", "IntValue", 0)
	stars.Capacity = MAX
	return stats
end

function PlayerState.get(player, name)
	local stats = player:FindFirstChild("leaderstats") or PlayerState.attach(player)
	return stats:FindFirstChild(name)
end

function PlayerState.cash(player)
	return PlayerState.get(player, "Cash")
end

function PlayerState.stars(player)
	return PlayerState.get(player, "Wanted")
end

function PlayerState.addCash(player, amount)
	local v = PlayerState.cash(player)
	if v == nil then
		return 0
	end
	v.Value = math.max(0, v.Value + math.floor(amount))
	return v.Value
end

-- returns the new star count, clamped; bump=true resets the decay clock, which is
-- what makes "lose them in the tunnel" work instead of "lose them in 17 seconds,
-- always"
function PlayerState.addStars(player, amount, bump)
	local v = PlayerState.stars(player)
	if v == nil then
		return 0
	end
	local before = v.Value
	v.Value = math.max(0, math.min(MAX, v.Value + amount))
	if v.Value ~= before and bump then
		local t = PlayerState.get(player, "LastHeat")
		if t ~= nil then
			t.Value = os.clock()
		end
	end
	return v.Value
end

function PlayerState.clearStars(player)
	local v = PlayerState.stars(player)
	if v ~= nil then
		v.Value = 0
	end
end

return PlayerState
