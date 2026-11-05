-- Mirror of ReplicatedStorage/Config.Car for the headless harness only.
-- Kept as a separate file so the harness loads the real Config module code path
-- (require -> ModuleScript) instead of an inlined fake.
local Config = {
	Car = {
		SuspensionTravel = 2.2,
		RideSag = 0.45,
		SuspensionDampingRatio = 0.7,
		MaxSpringG = 8,
		SettleTime = 0.5, -- seconds the chassis soaks into its springs before input responds
		LateralGripG = 2.2,
		HandbrakeGripG = 0.55,
		RollDragG = 0.09,
		DriveSpeed = 175,
		ReverseSpeed = 55,
		DriveAccelG = 1.15,
		DriveTimeConstant = 0.30, -- seconds to reach the target speed; MaxForce is derived from this
		DriveMaxG = 6, -- hard ceiling on drive authority
		FlightMaxG = 8,
		HoverMaxRate = 85,
		BrakeG = 2.0,
		SmallSpeedLimit = 8,
		DriveTimeConstant = 0.30,
		DriveMaxG = 6,
		FlightMaxG = 8,
		HoverMaxRate = 85,
		MaxSteerAngle = 30,
		SteerAuthority = 2.55,
		SteerSpeedFalloff = 0.0115,
		BodyRoll = 7,
		BodyPitch = 4.5,
		ToggleKeyCode = Enum.KeyCode.F,
		PitchRate = 62,
		RollRate = 78,
		YawRate = 58,
		AttitudeResponse = 6.0,
		FlightSpeed = 235,
		FlightTimeConstant = 0.22, -- seconds to close the gap to the requested velocity
		FlightLiftG = 1.06,
		HoverKp = 6.0,
		LiftSpeed = 62,
		HoverDamp = 2.2,
		MaxAltitude = 900,
		BoostSpeed = 340,
		BoostAccelG = 1.9,
		BoostCapacity = 100,
		BoostDrain = 34,
		BoostRegen = 13,
		BoostKey = Enum.KeyCode.LeftShift,
		AutoLandAltitude = 14,
		LandArmAltitude = 34, -- auto-land only arms after you clear this: stops it cancelling aero the instant you engage
		CrashForce = 120,
		KickUp = Enum.KeyCode.Space,
		HornKey = Enum.KeyCode.LeftAlt,
	},
	Wanted = { MaxStars = 5, FlyInCity = 1 },
	Mission = { Rings = 8 },
	HUD = { Accent = 0 },
	Radio = { Stations = {} },
	Voice = {},
	City = { GridSize = 11 },
}
return Config
