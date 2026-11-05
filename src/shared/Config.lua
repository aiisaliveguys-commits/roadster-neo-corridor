--[[
	CONFIG - single source of truth for the whole vertical slice.
	Touch nothing else to tune the game. Everything the physics, city,
	police, HUD and radio use lives here.

	Placement: ReplicatedStorage.Config (ModuleScript)
]]

local Config = {}

Config.GameName = "ROADSTER: Neo Corridor"

--------------------------------------------------------------------------------
-- WORLD / CITY
--------------------------------------------------------------------------------
Config.City = {
	GridSize = 11, -- blocks per side (odd looks better, centre block = downtown)
	Block = 128, -- stud size of a city block
	Road = 28, -- stud width of the road gutter between blocks
	BuildingChance = 0.78, -- fraction of a block's lots that get a tower
	MaxHeight = 420, -- tallest tower near the centre
	ParkChance = 0.14,
	LiteBuildings = true, -- emissive window bands at night (cheap, big payoff)
	RooftopProps = true,
	MergeStatic = false, -- true = merge roads/sidewalks into GeneratedMeshParts (fast, test it)
}

-- Flight is only interesting if there is a place to fly TO.
Config.Corridor = {
	Height = 260, -- deck elevation of the elevated expressway
	Lanes = 2,
	Enabled = true,
}

--------------------------------------------------------------------------------
-- VEHICLE PHYSICS
--------------------------------------------------------------------------------
-- Ground model: raycast springs + lateral grip + velocity-targeting.
-- Flight model: attitude slerp + velocity targeting in the car's frame, so the
-- velocity vector follows where you point the nose. That is what makes it feel
-- like a game and not a physics demo.
Config.Car = {
	-- suspension (physical, not magic numbers)
	SuspensionTravel = 2.2, -- studs the wheel can drop below the chassis
	RideSag = 0.45, -- studs the chassis settles at rest. Stiffness is
	-- derived from this: k = g / sag, so the ride height
	-- stays correct no matter how you retune the chassis mass
	SuspensionDampingRatio = 0.7,
	MaxSpringG = 8,
	SettleTime = 0.5, -- seconds the chassis soaks into its springs before input responds -- 1 = critically damped, 0.7 = settles fast, no bounce
	MaxSpringG = 8,
	SettleTime = 0.5, -- seconds the chassis soaks into its springs before input responds             -- safety cap on one wheel's share of the load, in g

	-- grip
	LateralGripG = 2.2, -- g available sideways (tyre model)
	HandbrakeGripG = 0.55,
	RollDragG = 0.09, -- coasting deceleration

	-- power
	DriveSpeed = 175, -- studs/sec at full throttle (175 studs/s ~= 195 mph in Roblox units)
	ReverseSpeed = 55,
	DriveAccelG = 1.15,
	DriveTimeConstant = 0.30, -- seconds to reach the target speed; MaxForce is derived from this
	DriveMaxG = 6, -- hard ceiling on drive authority
	FlightMaxG = 8,
	HoverMaxRate = 85,
	BrakeG = 2.0,
	SmallSpeedLimit = 8,

	-- steering
	MaxSteerAngle = 30, -- degrees of visual front-wheel kick
	SteerAuthority = 2.55, -- rad/s of yaw at low speed
	SteerSpeedFalloff = 0.0115,
	BodyRoll = 7, -- degrees of lean into a corner
	BodyPitch = 4.5,

	-- flight
	ToggleKeyCode = Enum.KeyCode.F,
	PitchRate = 62, -- deg/s
	RollRate = 78,
	YawRate = 58,
	AttitudeResponse = 6.0, -- how hard attitude chases the target
	FlightSpeed = 235,
	FlightTimeConstant = 0.22, -- seconds to close the gap to the requested velocity         -- velocityFactor on the LinearVelocity
	FlightLiftG = 1.06, -- >1 so it lifts off under thrust
	HoverKp = 6.0,
	LiftSpeed = 62,
	HoverDamp = 2.2,
	MaxAltitude = 900,

	-- boost
	BoostSpeed = 340,
	BoostAccelG = 1.9,
	BoostCapacity = 100,
	BoostDrain = 34,
	BoostRegen = 13,
	BoostKey = Enum.KeyCode.LeftShift,

	-- landing assist
	AutoLandAltitude = 14,
	LandArmAltitude = 34, -- auto-land only arms after you clear this: stops it cancelling aero the instant you engage
	CrashForce = 120, -- studs/s impact speed that costs you money

	KickUp = Enum.KeyCode.Space, -- hold to pull up while driving fast (hop)
	HornKey = Enum.KeyCode.LeftAlt,
}

-- Anti-cheat/ownership. In a published game the client owns the car and
-- Roblox replicates it. Set true if you want server-owned physics in a live
-- game (heavier, but you cannot be exploited).
Config.ServerAuthoritative = false

--------------------------------------------------------------------------------
-- WANTED SYSTEM (GTA-flavoured, no shooting required)
--------------------------------------------------------------------------------
Config.Wanted = {
	MaxStars = 5,
	FlyInCity = 1, -- stars for screaming through the streets under the deck
	FlyAltitude = 90, -- below this, flying is "in the city"
	AirborneGrace = 1.5, -- seconds airborne before it counts
	StreetSpeed = 165, -- street racing threshold
	DecayNoWitness = 17, -- seconds out of sight before a star drops
	CopSpeed = 195,
	CopPerStar = 1,
	ArrestRange = 16,
	ArrestSpeed = 22, -- you get busted below this while a cop is touching you
	ArrestFine = 500,
	PatrolZones = 6,
}

--------------------------------------------------------------------------------
-- MISSIONS
--------------------------------------------------------------------------------
Config.Mission = {
	Rings = 8,
	RingRadius = 20,
	RewardPerRing = 250,
	FinishReward = 5000,
	TimeLimit = 240,
	GroundOnlyAfter = 1, -- ring #1 is free, the rest must be taken on wheels
}

--------------------------------------------------------------------------------
-- HUD
--------------------------------------------------------------------------------
Config.HUD = {
	Accent = Color3.fromRGB(0, 229, 255),
	Danger = Color3.fromRGB(255, 71, 87),
	Cash = Color3.fromRGB(120, 255, 170),
	MinimapSize = 210,
	SpeedoSize = 232,
	ShowAltitude = true,
}

--------------------------------------------------------------------------------
-- RADIO
-- R cycles stations. DJ intro plays, then the track list loops.
-- These are placeholder-legal Roblox audio asset IDs from the licensed
-- "Roblox Audio" catalog; swap in your own uploads freely.
-- YOUR RECORDED DJ SET IS IN THE PROJECT at audio/radio/*.mp3 - upload those
-- (Create > Asset ID, audio must be < 7 min and you need audio upload rights)
-- and paste the ids into DJIntro / AdBump below.
--------------------------------------------------------------------------------
Config.Radio = {
	ToggleKey = Enum.KeyCode.H,
	StationKey = Enum.KeyCode.R,
	Volume = 0.55,
	DJIntro = 0, -- rbxassetid for dj-01-open.mp3 once uploaded
	AdBump = 0, -- rbxassetid for dj-03-ad.mp3 once uploaded
	Stations = {
		{
			Name = "ELECTRO BAY",
			Genre = "Synth / Night Drive",
			Color = Color3.fromRGB(0, 229, 255),
			Tracks = { 1837879082, 1848354536, 1846458016 },
		},
		{
			Name = "NEON FM",
			Genre = "Downtempo",
			Color = Color3.fromRGB(255, 92, 200),
			Tracks = { 1841906742, 1842778001 },
		},
		{
			Name = "COLD STEEL RADIO",
			Genre = "Industrial",
			Color = Color3.fromRGB(200, 210, 225),
			Tracks = { 1848354536, 1837879082 },
		},
	},
}

--------------------------------------------------------------------------------
-- DISPATCH VO (your uploaded mp3s go here; 0 = use on-screen text only)
--------------------------------------------------------------------------------
Config.Voice = {
	Welcome = 0, -- audio/dispatch/01-welcome.mp3
	Freeway = 0, -- audio/dispatch/02-freeway.mp3
	MissionStart = 0, -- audio/dispatch/03-mission-start.mp3
}

Config.EngineSound = 0 -- optional looping engine rbxassetid

return Config
