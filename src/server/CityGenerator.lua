--[[
	CityGenerator - the neighbourhood, from a seed.

	Design notes that matter for a flying car:
	* The city is a grid of blocks separated by roads, so there is always a
	  straight line to land on. Buildings occupy their own lots and never overlap
	  a road, which is what makes "land on the street" a thing you can actually do.
	* Everything static is anchored. Unanchored scenery plus a 1000-part city is
	  how the physics solver dies.
	* The elevated corridor is a real deck at Config.Corridor.Height with columns,
	  because the flight model wants a second altitude layer to play in - and the
	  wanted system uses "under the deck" as a real gameplay condition.
	* Parts are created in batches with a Heartbeat yield every so often, or the
	  whole generation would blow the script timeout and half-build the map.
	* Deterministic PRNG: same seed, same city, so a bug report about "the gap on
	  5th and Main" means the same gap for everyone.
]]

local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Config = require(game:GetService("ReplicatedStorage"):WaitForChild("Config"))
local City = Config.City
local Corridor = Config.Corridor

local BATCH = 400

local function newRandom(seed)
	local x = seed
	return function()
		-- numerically recipes rng, 32-bit. Cheap and good enough for a city.
		x = (x * 1103515245 + 12345) % 2147483648
		return x / 2147483648
	end
end

local function part(props)
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for k, v in pairs(props) do
		p[k] = v
	end
	return p
end

local CityGen = {}

function CityGen.Generate(parent, seed)
	local rng = newRandom(seed or 20261105)
	local n = City.GridSize
	local block = City.Block
	local road = City.Road
	local pitch = block + road
	local span = n * pitch
	local half = span / 2

	local folder = Instance.new("Folder")
	folder.Name = "GeneratedCity"
	folder.Parent = parent

	local groundY = 0
	local created = 0
	local function add(inst)
		inst.Parent = folder
		created = created + 1
		if created % BATCH == 0 then
			RunService.Heartbeat:Wait()
		end
	end

	-- ground: one plate under the whole grid. Cheaper than 121 tiles and it
	-- removes every seam a wheel could catch on.
	add(part({
		Name = "Ground",
		Size = Vector3.new(span + road * 2, 2, span + road * 2),
		Position = CFrame.new(0, groundY - 1, 0),
		Material = Enum.Material.Asphalt,
		Color = Color3.fromRGB(38, 40, 46),
	}))

	-- sidewalks + lots, block by block
	local centre = (n - 1) / 2
	local downtownPeak = City.MaxHeight
	local pads = {}

	for bx = 0, n - 1 do
		for bz = 0, n - 1 do
			local cx = (bx - centre) * pitch
			local cz = (bz - centre) * pitch
			local distFromCentre = math.max(math.abs(bx - centre), math.abs(bz - centre)) / centre

			-- block plate (sidewalk level)
			add(part({
				Name = string.format("Block_%d_%d", bx, bz),
				Size = Vector3.new(block, 1, block),
				Position = CFrame.new(cx, groundY + 0.5, cz),
				Material = Enum.Material.Concrete,
				Color = Color3.fromRGB(84, 86, 92),
			}))

			local isPark = rng() < City.ParkChance
			if isPark then
				add(part({
					Name = "Park",
					Size = Vector3.new(block - 14, 0.6, block - 14),
					Position = CFrame.new(cx, groundY + 1.3, cz),
					Material = Enum.Material.Grass,
					Color = Color3.fromRGB(52, 96, 54),
					Parent = folder,
				}))
			else
				-- a block is a ring of lots around a courtyard; towers on the ring
				local lots = { { -1, -1 }, { 1, -1 }, { -1, 1 }, { 1, 1 } }
				for li = 1, 4 do
					if rng() < City.BuildingChance then
						local ox, oz = lots[li][1], lots[li][2]
						local w = 34 + math.floor(rng() * 16)
						local d = 34 + math.floor(rng() * 16)
						-- downtown gets the height, edges get the low-rise sprawl
						local falloff = 1 - distFromCentre
						local h = math.max(18, math.floor((8 + rng() * 46) * (0.25 + falloff * falloff) * downtownPeak / 40))
						local px = cx + ox * (block / 4)
						local pz = cz + oz * (block / 4)
						local shell = part({
							Name = string.format("Tower_%d_%d_%d", bx, bz, li),
							Size = Vector3.new(w, h, d),
							Position = CFrame.new(px, groundY + 1 + h / 2, pz),
							Material = Enum.Material.Concrete,
							Color = Color3.fromRGB(64, 66, 74):Lerp(Color3.fromRGB(30, 32, 40), rng() * 0.5),
						})
						add(shell)

						if City.LiteBuildings then
							-- emissive window bands: one thin part per floor, so the
							-- skyline reads at night for a fraction of the cost of
							-- real windows
							local bandCount = math.floor(h / 12)
							for bi = 1, bandCount do
								if rng() < 0.72 then
									add(part({
										Name = "Windows",
										Size = Vector3.new(w + 0.4, 1.8, d + 0.4),
										Position = CFrame.new(px, groundY + 1 + bi * 12 - 4, pz),
										Material = Enum.Material.Neon,
										Color = Color3.fromRGB(180, 210, 255),
										Transparency = 0.25,
										CanCollide = false,
									}))
								end
							end
						end

						if City.RooftopProps and h > 60 then
							add(part({
								Name = "RooftopPad",
								Size = Vector3.new(math.min(w, d) - 8, 0.4, math.min(w, d) - 8),
								Position = CFrame.new(px, groundY + 2 + h, pz),
								Material = Enum.Material.DiamondPlate,
								Color = Color3.fromRGB(120, 124, 130),
							}))
							pads[#pads + 1] = Vector3.new(px, groundY + 3 + h, pz)
							-- a stair box so the pad is not a bare slab
							add(part({
								Name = "StairBox",
								Size = Vector3.new(10, 8, 10),
								Position = CFrame.new(px + w / 4, groundY + 5 + h, pz + d / 4),
								Material = Enum.Material.CorrodedMetal,
								Color = Color3.fromRGB(90, 88, 84),
							}))
						end
					end
				end
			end
		end
		-- one yield per row keeps a 2500-row build from ever touching the timeout
		RunService.Heartbeat:Wait()
	end

	-- road markings down the centre of each gutter. CanCollide false: a decal-like
	-- strip that a wheel could clip on is worse than no strip at all.
	for i = 0, n do
		local c = (i - centre) * pitch - pitch / 2
		add(part({
			Name = "RoadX",
			Size = Vector3.new(road, 0.2, span + road),
			Position = CFrame.new(c, groundY + 0.11, 0),
			Material = Enum.Material.Asphalt,
			Color = Color3.fromRGB(30, 31, 36),
			CanCollide = false,
		}))
		add(part({
			Name = "RoadZ",
			Size = Vector3.new(span + road, 0.2, road),
			Position = CFrame.new(0, groundY + 0.11, c),
			Material = Enum.Material.Asphalt,
			Color = Color3.fromRGB(30, 31, 36),
			CanCollide = false,
		}))
	end

	local deckY = Corridor.Height
	local lanes = math.max(1, Corridor.Lanes)
	local deckW = 26 * lanes

	if Corridor.Enabled then
		-- two straight elevated arms through downtown. Two (not a ring) on purpose:
		-- a ring invites you to loop it forever and never touch the streets.
		local dirs = { Vector3.new(1, 0, 0), Vector3.new(0, 0, 1) }
		for di = 1, 2 do
			local dir = dirs[di]
			local len = span + 240
			local mid = Vector3.new(0, deckY, 0)
			local size
			if dir.X > 0 then
				size = Vector3.new(len, 3, deckW)
			else
				size = Vector3.new(deckW, 3, len)
			end
			-- deck in chunks: one 2000-stud part is a collision monster, 10 parts
			-- of 200 studs each are not, and a car crossing a seam at 200 studs/s
			-- will never notice it
			local chunks = 10
			local chunkLen = len / chunks
			for ci = 0, chunks - 1 do
				local offset = (ci - (chunks - 1) / 2) * chunkLen
				local pos = mid + dir * offset
				local cs = size
				if dir.X > 0 then
					cs = Vector3.new(chunkLen - 1, size.Y, size.Z)
				else
					cs = Vector3.new(size.X, size.Y, chunkLen - 1)
				end
				add(part({
					Name = string.format("Deck_%d_%d", di, ci),
					Size = cs,
					Position = CFrame.new(pos),
					Material = Enum.Material.Concrete,
					Color = Color3.fromRGB(96, 98, 104),
				}))
			end
			-- barriers so the deck has edges you can feel
			for side = -1, 1, 2 do
				local bs
				if dir.X > 0 then
					bs = Vector3.new(len, 4, 1.5)
				else
					bs = Vector3.new(1.5, 4, len)
				end
				local perp = dir.Cross(Vector3.new(0, 1, 0)).Unit
				add(part({
					Name = "Barrier",
					Size = bs,
					Position = CFrame.new(mid + perp * (deckW / 2) * side + Vector3.new(0, 3, 0)),
					Material = Enum.Material.Concrete,
					Color = Color3.fromRGB(150, 152, 150),
				}))
			end
			-- columns every ~90 studs
			local colCount = math.floor(len / 90)
			for col = 0, colCount do
				local offset = (col - colCount / 2) * (len / math.max(1, colCount))
				local pos = mid + dir * offset
				add(part({
					Name = "Column",
					Size = Vector3.new(6, deckY, 6),
					Position = CFrame.new(pos.X, deckY / 2, pos.Z),
					Material = Enum.Material.Concrete,
					Color = Color3.fromRGB(78, 80, 86),
				}))
			end
		end
	end

	-- a landing apron on the ground under the deck: the tutorial beat is
	-- "start here, climb to the corridor" and it needs a flat, pad-free stretch
	add(part({
		Name = "LaunchApron",
		Size = Vector3.new(deckW + 30, 0.5, 300),
		Position = CFrame.new(0, groundY + 0.3, 0),
		Material = Enum.Material.Neon,
		Color = Color3.fromRGB(0, 229, 255),
		Transparency = 0.75,
		CanCollide = false,
	}))

	local origin = Vector3.new(0, groundY + 6, 0)
	return {
		Folder = folder,
		PartCount = created,
		SpawnPoint = origin,
		RooftopPads = pads,
		Extent = half,
		DeckY = deckY,
	}
end

return CityGen
