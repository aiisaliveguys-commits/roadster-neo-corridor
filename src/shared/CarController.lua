--[[
	CarController - the feel of the game, in one module.

	ONE module, TWO homes (no duplicated physics, no drift):
	  * Studio "Play Solo": the server Script instantiates it and the server owns
	    the assembly, so it works with zero network setup.
	  * Published game: the client LocalScript instantiates it after the server
	    hands the assembly over with SetNetworkOwnerAsync.

	Deliberately NOT VehicleConstraint: that class is great for cars and useless
	for a car that flies, because the whole trick is swapping the ground solver
	out from under the same assembly.

	GROUND  per-wheel raycast spring+damper VectorForces, a lateral grip budget
	        measured in g (so changing mass/power never breaks the feel),
	        forward LinearVelocity, yaw from an AngularVelocity.
	FLIGHT  gravity off; attitude is a real PD torque on the rotation error, so
	        slamming a wall still reacts like an object instead of teleporting
	        back to a scripted CFrame; velocity chases a world-space target
	        built from wherever the nose is pointing. Point the nose, the
	        velocity follows - that is why it flies like a jet and not like a
	        falling brick.

	Tuning: every constant lives in ReplicatedStorage.Config.Car. The g-based
	forces mean you can retune mass, grip and power independently.
]]

local RunService = game:GetService("RunService")
local Config = require(game:GetService("ReplicatedStorage"):WaitForChild("Config"))
local C = Config.Car

local IS_CLIENT = RunService:IsClient()
local UserInputService = IS_CLIENT and game:GetService("UserInputService") or nil

local MODE = { GROUND = "GROUND", FLIGHT = "FLIGHT", LANDING = "LANDING" }
local RAD = math.rad
local DEG_PER_RAD = 180 / math.pi

local CarController = {}
CarController.MODE = MODE

--------------------------------------------------------------------------------
-- math helpers
--------------------------------------------------------------------------------
local function clamp(v, lo, hi)
	if v < lo then
		return lo
	end
	if v > hi then
		return hi
	end
	return v
end

local function damp(cur, target, response, dt)
	return cur + (target - cur) * (1 - math.exp(-response * dt))
end

-- Rotation error from `target` to `actual`, expressed in WORLD axes, as an
-- axis*angle vector. Uses ToObjectSpace + ToOrientation (CFrame:Inverse() is
-- deprecated and m11-style fields do not exist on CFrame).
local function rotErrorWorld(target, actual)
	local t = CFrame.new(target.Position) * target.Rotation
	local rel = t:ToObjectSpace(actual)
	local x, y, z = rel:ToOrientation()
	return Vector3.new(x, y, z)
end

--------------------------------------------------------------------------------
-- construction
--------------------------------------------------------------------------------
function CarController.new(model)
	local self = setmetatable({}, { __index = CarController })
	self.Model = model

	local rootName = model:GetAttribute("VehicleRoot")
	local root = (rootName and model:FindFirstChild(rootName)) or model.PrimaryPart
	assert(root and root:IsA("BasePart"), "CarController: no VehicleRoot on " .. model:GetFullName())
	self.Root = root

	self.Seat = model:FindFirstChild("Seat", true)
	self.Wheels = {}

	local parts = model:FindFirstChild("CarParts")
	if parts then
		for _, wheel in ipairs(parts:GetChildren()) do
			if wheel:IsA("BasePart") and wheel:GetAttribute("Role") == "Wheel" then
				local offset = root.CFrame:PointToObjectSpace(wheel.Position)
				local a = Instance.new("Attachment")
				a.Name = "Susp_" .. wheel.Name
				a.Position = offset
				a.Parent = root

				local spring = Instance.new("VectorForce")
				spring.Name = "Spring_" .. wheel.Name
				spring.Attachment0 = a
				spring.RelativeTo = Enum.ActuatorRelativeTo.World
				spring.Parent = a

				table.insert(self.Wheels, {
					Part = wheel,
					Attachment = a,
					Spring = spring,
					Offset = offset,
					Radius = math.max(wheel.Size.Y, wheel.Size.Z) * 0.5,
					Steerable = (offset.Z < 0),
					Compress = 0,
					Spin = 0,
				})
			end
		end
	end
	assert(#self.Wheels >= 2, "CarController: needs 2+ tagged wheels on " .. model:GetFullName())

	-- An attachment with identity world orientation lets VectorForce /
	-- AngularVelocity work directly in WORLD axes, which is what a PD controller
	-- needs. Without it, AngularVelocity would be in the car's spinning frame.
	-- An attachment with identity WORLD orientation lets VectorForce and
	-- AngularVelocity work directly in world axes, which is what a PD
	-- controller needs. (Attachment0-relative would spin with the car.)
	local a = Instance.new("Attachment")
	a.Name = "WorldRef"
	a.CFrame = CFrame.new(root.Position)
	a.Parent = root
	self.WorldAttachment = a

	self.Grip = Instance.new("VectorForce")
	self.Grip.Attachment0 = self.WorldAttachment
	self.Grip.RelativeTo = Enum.ActuatorRelativeTo.World
	self.Grip.Parent = root

	self.Drive = Instance.new("LinearVelocity")
	self.Drive.Attachment0 = self.WorldAttachment
	self.Drive.RelativeTo = Enum.ActuatorRelativeTo.World
	self.Drive.MaxForce = 0
	self.Drive.Parent = root

	self.BoostForce = Instance.new("VectorForce")
	self.BoostForce.Attachment0 = self.WorldAttachment
	self.BoostForce.RelativeTo = Enum.ActuatorRelativeTo.World
	self.BoostForce.Enabled = false
	self.BoostForce.Parent = root

	self.Yaw = Instance.new("AngularVelocity")
	self.Yaw.Attachment0 = self.WorldAttachment
	self.Yaw.RelativeTo = Enum.ActuatorRelativeTo.World
	self.Yaw.MaxTorque = 0
	self.Yaw.Parent = root

	self.Attitude = Instance.new("AngularVelocity")
	self.Attitude.Attachment0 = self.WorldAttachment
	self.Attitude.RelativeTo = Enum.ActuatorRelativeTo.World
	self.Attitude.MaxTorque = 0
	self.Attitude.Parent = root

	-- wheels are cosmetic: the raycast springs own ground contact, and Massless
	-- keeps their weight out of the suspension maths
	for _, w in ipairs(self.Wheels) do
		local wp = w.Part
		wp.CanCollide = false
		wp.CanQuery = false
		wp.CanTouch = false
		wp.Massless = true
		wp.CastShadow = false
	end

	self.RayParams = RaycastParams.new()
	self.RayParams.FilterType = Enum.RaycastFilterType.Exclude
	self.RayParams.RespectCanCollide = true
	self.RayParams.FilterDescendantsInstances = { model }

	self.Mode = MODE.GROUND
	self.Pitch = 0
	self.Roll = 0
	self.Heading = math.atan2(root.CFrame.LookVector.X, root.CFrame.LookVector.Z)
	self.Boost = C.BoostCapacity
	self.Boosting = false
	self.Speed = 0
	self.Vertical = 0
	self.Altitude = 0
	self.GroundY = nil
	self.Grounded = true
	self.AirTime = 0
	self.HoverAlt = root.Position.Y
	self.ToggleQueued = false
	self.LandArmed = false
	self.OnCrash = nil
	self.LastCrashSpeed = 0

	self._mass = root.AssemblyMass
	self._massAge = 0
	self._ownAge = 0
	self._stateAge = 0
	self._lastHit = 0
	self._age = 0

	self:_setState()

	self.TouchedConn = root.Touched:Connect(function(hit)
		self:_onTouched(hit)
	end)

	if IS_CLIENT then
		self:bindFlightKey()
	end

	return self
end

function CarController:bindFlightKey()
	local ok, CAS = pcall(function()
		return game:GetService("ContextActionService")
	end)
	if not ok or CAS == nil then
		return
	end
	self._cas = CAS
	CAS:BindAction("RoadsterAero", function(_, state)
		if state == Enum.UserInputState.Begin then
			self.ToggleQueued = true
		end
	end, false, C.ToggleKeyCode)
end

--------------------------------------------------------------------------------
-- ownership (client-driven mode only)
--------------------------------------------------------------------------------
function CarController:_refreshOwner(dt)
	if not IS_CLIENT then
		return
	end
	self._ownAge = self._ownAge + dt
	if self._ownAge < 0.5 then
		return
	end
	self._ownAge = 0
	local ok, owner = pcall(function()
		return self.Root:GetRootPart().AssemblyOwner
	end)
	if not ok then
		return
	end
	local me = game:GetService("Players").LocalPlayer
	if owner == nil then
		pcall(function()
			self.Root:SetNetworkOwnerAsync(me)
		end)
	end
end

--------------------------------------------------------------------------------
-- input
--------------------------------------------------------------------------------
function CarController:_key(code)
	if code == nil or UserInputService == nil then
		return false
	end
	return UserInputService:IsKeyDown(code)
end

function CarController:ReadInput()
	local throttle, steer = 0, 0
	local seatDriven = false
	local seat = self.Seat
	if seat ~= nil and seat.Occupant ~= nil and seat.Occupant.Parent ~= nil then
		seatDriven = true
		throttle = seat.Throttle
		steer = seat.Steer
	end

	local up = self:_key(Enum.KeyCode.Space)
	local brake = self:_key(Enum.KeyCode.LeftControl)
	local fwd = self:_key(Enum.KeyCode.W) or self:_key(Enum.KeyCode.Up)
	local back = self:_key(Enum.KeyCode.S) or self:_key(Enum.KeyCode.Down)
	local left = self:_key(Enum.KeyCode.A)
	local right = self:_key(Enum.KeyCode.D)
	local yawL = self:_key(Enum.KeyCode.Q)
	local yawR = self:_key(Enum.KeyCode.E)
	local rollL = self:_key(Enum.KeyCode.Z)
	local rollR = self:_key(Enum.KeyCode.X)
	local boost = self:_key(C.BoostKey)

	if not seatDriven then
		if fwd then
			throttle = throttle + 1
		end
		if back then
			throttle = throttle - 1
		end
		if left then
			steer = steer - 1
		end
		if right then
			steer = steer + 1
		end
	end

	return {
		Throttle = clamp(throttle, -1, 1),
		Steer = clamp(steer, -1, 1),
		Up = up,
		Brake = brake,
		Boost = boost,
		Pitch = (back and 1 or 0) - (fwd and 1 or 0),
		Yaw = (yawR and 1 or 0) - (yawL and 1 or 0),
		Roll = (rollR and 1 or 0) - (rollL and 1 or 0),
		SeatDriven = seatDriven,
	}
end

--------------------------------------------------------------------------------
-- ground step
--------------------------------------------------------------------------------
function CarController:_stepGround(dt, mass, input, g)
	-- Acceleration-based spring. w.Compress is studs/s of compression RATE, so
	-- k * rate is an acceleration in 1/s^2:
	--   a = k*x - c*v      (integrate once -> velocity, twice -> position)
	-- so at rest k*sag must equal exactly 1 g. Deriving k from the target sag
	-- keeps ride height correct for ANY chassis mass, and dividing the force by
	-- the wheel count keeps it correct for any wheel count too (a 6-wheeler and
	-- a 4-wheeler sit at the same height). No magic units to chase.
	-- k in g per stud of deflection, so static sag = 1/k studs; c from the
	-- damping ratio (1.0 = critically damped). Both dimensionless-friendly:
	-- retune mass or power and the ride height survives.
	local k = 1 / math.max(C.RideSag, 0.05)
	local c = 2 * C.SuspensionDampingRatio * math.sqrt(k)
	local root = self.Root
	local cf = root.CFrame
	local up = cf.UpVector
	local look = cf.LookVector
	local vel = root.AssemblyLinearVelocity
	local omega = root.AssemblyAngularVelocity
	local forwardSpeed = look:Dot(vel)
	local contacts = 0

	for _, w in ipairs(self.Wheels) do
		local hub = root.CFrame:PointToWorldSpace(w.Offset)
		local reach = w.Radius + C.SuspensionTravel * 2.6
		local hit = workspace:Raycast(hub, -up * reach, self.RayParams)

		if hit then
			contacts = contacts + 1
			-- GEOMETRY FIRST. A wheel touching down has hubHeight == radius + travel,
			-- so `deflect` is exactly 0 at touchdown and grows as the spring
			-- compresses. Deriving the rest position from geometry (instead of a
			-- hand-tuned offset) is what keeps the ride height correct for a car of
			-- any size - and an earlier sign flip here pinned every spring at full
			-- force on frame 1, which launched the car instead of settling it.
			local deflect = clamp((w.Radius + C.SuspensionTravel) - hit.Distance, 0, C.SuspensionTravel * 2.4)
			-- F = mass * (k*deflect - c*compressionRate), divided per wheel so a
			-- 6-wheeler sits at the same height as a 4-wheeler
			local force = mass * g * clamp(k * deflect - c * up:Dot(w.Rate or Vector3.zero), 0, C.MaxSpringG or 8) / #self.Wheels
			w.Spring.Force = up * force
			w.Deflect = deflect
		else
			-- no ground, no force. A damper acting while airborne is the classic
			-- "car launches itself off nothing" bug.
			w.Deflect = 0
			w.Spring.Force = Vector3.zero
		end
	end

	-- visual wheels: rotation + front steer kick
	for _, w in ipairs(self.Wheels) do
		w.Spin = w.Spin - (forwardSpeed * dt) / math.max(w.Radius, 0.2)
		local steerA = w.Steerable and RAD(C.MaxSteerAngle) * input.Steer or 0
		w.Part.CFrame = (cf * CFrame.new(w.Offset)) * CFrame.Angles(0, steerA, 0) * CFrame.Angles(0, 0, w.Spin)
	end

	-- lateral grip: a budget in g, spent to kill slip
	local slip = vel - look * forwardSpeed
	slip = slip - up * slip:Dot(up)
	local gripG = (input.Brake and C.HandbrakeGripG) or C.LateralGripG
	if contacts == 0 then
		gripG = gripG * 0.18
	end
	if slip.Magnitude > 0.01 then
		self.Grip.Force = -slip.Unit * math.min(slip.Magnitude * mass * 14, gripG * mass * g)
	else
		self.Grip.Force = Vector3.zero
	end

	-- drive / brake / coast
	local desired, accelG = 0, C.RollDragG
	if input.Throttle > 0 then
		desired = C.DriveSpeed * input.Throttle
		accelG = C.DriveAccelG
	elseif input.Throttle < 0 then
		desired = C.ReverseSpeed * input.Throttle
		accelG = C.DriveAccelG * 0.7
	end
	if input.Brake then
		desired = 0
		accelG = C.BrakeG
	end
	-- LinearVelocity in Roblox is NOT a rate: VelocityFactor is a 0-1 BLEND
	-- applied per step, and MaxForce is an impulse budget (force x dt) for that
	-- step. So the shape of the response comes from MaxForce, and VelocityFactor
	-- should be 1 ("apply as much as you are allowed"). Requesting a factor above
	-- 1 just saturates to 1, and an under-set MaxForce silently becomes the real
	-- speed limiter - which is exactly how this car ended up pinning 0.28 g of
	-- acceleration while the config claimed 1.15.
	local dv = desired - forwardSpeed
	self.Drive.VelocityFactor = 1
	self.Drive.MaxForce = mass * clamp(math.abs(dv) / C.DriveTimeConstant, accelG * g, C.DriveMaxG * g)
	self.Drive.LineVelocity = look * desired

	-- boost: extra shove along the nose, energy budgeted
	local boosting = input.Boost and self.Boost > 1
	self.BoostForce.Enabled = boosting
	if boosting then
		self.BoostForce.Force = look * (mass * (C.BoostAccelG - C.DriveAccelG) * g)
	end

	-- steering: yaw rate authority that fades with speed (GTA-ish weighting)
	local speedCap = clamp(1 - math.abs(forwardSpeed) * C.SteerSpeedFalloff, 0.34, 1)
	local targetYaw = input.Steer * C.SteerAuthority * speedCap
	if input.Throttle < 0 then
		targetYaw = -targetYaw
	end
	self.Yaw.MaxTorque = mass * g * 14
	self.Yaw.AngularVelocity = Vector3.new(0, targetYaw, 0)

	-- "grounded" for landing purposes means the springs are actually carrying
	-- load, not merely that a ray hit something: after a drop the chassis sits
	-- at maximum deflection, so an altitude/deflection-threshold test can never
	-- pass and the car would be stuck in LANDING forever.
	local loaded = 0
	for _, w in ipairs(self.Wheels) do
		if w.Spring.Force.Magnitude > mass * g * 0.08 / #self.Wheels then
			loaded = loaded + 1
		end
	end
	self.Grounded = contacts > 0
	self.LoadedWheels = loaded
	return contacts > 0
end

--------------------------------------------------------------------------------
-- flight step
--------------------------------------------------------------------------------
function CarController:_stepFlight(dt, mass, input, g)
	local root = self.Root
	local look = root.CFrame.LookVector
	local right = root.CFrame.RightVector
	local vel = root.AssemblyLinearVelocity

	-- pitch target: W/S (or seat throttle when seated), Space adds lift
	local pitchIn
	if input.SeatDriven then
		pitchIn = -input.Throttle
	else
		pitchIn = -input.Pitch
	end
	if input.Up then
		pitchIn = pitchIn - 0.6
	end
	pitchIn = clamp(pitchIn, -1, 1)

	self.Pitch = clamp(self.Pitch + pitchIn * C.PitchRate * dt, -48, 48)
	if pitchIn == 0 then
		self.Pitch = damp(self.Pitch, 0, 1.3, dt)
	end

	-- Anti-windup: if a wall knocks the car over, the target angle follows the
	-- REAL attitude back up, so we never accumulate a huge error and then
	-- catapult the car trying to correct it.
	local fwdFlat = Vector3.new(look.X, 0, look.Z)
	if fwdFlat.Magnitude > 0.05 then
		local realPitch = math.asin(clamp(look.Y, -1, 1))
		local flatFwd = fwdFlat.Unit
		local realRoll =
			math.atan2(root.CFrame.RightVector:Dot(flatFwd:Cross(Vector3.yAxis)), root.CFrame.UpVector:Dot(Vector3.yAxis))
		if pitchIn == 0 then
			self.Pitch = self.Pitch + (realPitch * DEG_PER_RAD - self.Pitch) * clamp(dt * 2.5, 0, 1)
		end
		self.Roll = self.Roll + (realRoll * DEG_PER_RAD - self.Roll) * clamp(dt * 2.5, 0, 1)
	end

	local rollIn
	if input.SeatDriven then
		rollIn = input.Steer * 0.55
	else
		rollIn = (input.Roll ~= 0) and input.Roll or 0
	end
	self.Roll = clamp(damp(self.Roll, rollIn * 36, 4.5, dt), -45, 45)

	local yawIn
	if input.SeatDriven then
		yawIn = input.Steer
	else
		yawIn = input.Yaw
	end
	self.Heading = self.Heading + yawIn * RAD(C.YawRate) * dt

	-- attitude PD in world axes (hence the identity-orientation attachment)
	local target = CFrame.new(root.Position) * CFrame.Angles(RAD(self.Pitch), self.Heading, RAD(self.Roll))
	local err = rotErrorWorld(target.Rotation, root.CFrame.Rotation)
	self.Attitude.MaxTorque = mass * g * 220
	local px = clamp(-err.X * 9, -6, 6)
	local py = clamp(-err.Y * 3.2, -4, 4)
	local pz = clamp(-err.Z * 9, -6, 6)
	self.Attitude.AngularVelocity = Vector3.new(px, py, pz)

	-- velocity targeting in world space, aimed where the nose points
	local throttle = input.SeatDriven and 1 or input.Throttle
	local dir = throttle < 0 and -0.4 or 1
	local top = C.FlightSpeed * (1 + (self.Boosting and 0.4 or 0))
	local planar = look * (top * clamp(math.abs(throttle), 0, 1) * dir)
	if not input.SeatDriven and throttle == 0 then
		planar = root.CFrame.LookVector * (top * 0.3)
	end
	planar = planar + right * (rollIn * 26)

	-- ---- vertical: lift while held, then ONE-MOMENT altitude capture
	-- The mistake to avoid (it cost me a debugging cycle here): re-anchoring the
	-- hover setpoint to the car's current height every frame while it climbs.
	-- The velocity loop always lags a little, so that lag accumulates and the
	-- car ratchets upward forever - it "holds" a drift of ~30 studs/s and never
	-- comes down for the auto-land check. Anchor ONCE, on release, with the
	-- momentum of the car folded into the target, and the error decays to zero.
	if input.Up then
		self.HoverAlt = nil
		wantY = C.LiftSpeed or 62
	elseif self.Mode == MODE.FLIGHT and self.HoverAlt ~= nil then
		local err = self.HoverAlt - root.Position.Y
		wantY = clamp(err * C.HoverKp - vel.Y * C.HoverDamp, -C.HoverMaxRate, C.HoverMaxRate)
	else
		-- coasting level: hold attitude, bleed vertical speed
		wantY = clamp(-vel.Y * C.HoverDamp, -C.HoverMaxRate, C.HoverMaxRate)
	end
	if self.HoverAlt == nil and not input.Up and pitchIn == 0 then
		self.HoverAlt = root.Position.Y + clamp(vel.Y * 0.35, -25, 25)
	end
	-- Ceiling goes LAST, on the composed target. Checked earlier (my first pass)
	-- the hover capture immediately overrode it and the car sailed past the cap.
	if self.Altitude > C.MaxAltitude and wantY > 0 then
		wantY = 0
		self.HoverAlt = nil
	end

	local targetVel = Vector3.new(planar.X, wantY, planar.Z)
	-- MaxForce is already an impulse budget for the step, so it must NOT be
	-- multiplied by dt again here - that double-count silently divided the whole
	-- actuator authority by the frame time and made the car crawl.
	local curVel = root.AssemblyLinearVelocity
	local dvx, dvy, dvz = targetVel.X - curVel.X, targetVel.Y - curVel.Y, targetVel.Z - curVel.Z
	self.Drive.VelocityFactor = 1
	self.Drive.MaxForce = mass
		* math.min(math.sqrt(dvx * dvx + dvy * dvy + dvz * dvz) / C.FlightTimeConstant, C.FlightMaxG * g)
	self.Drive.LineVelocity = targetVel

	self.BoostForce.Enabled = self.Boosting
	if self.Boosting then
		self.BoostForce.Force = look * (mass * C.BoostAccelG * g * 0.3)
	end

	for _, w in ipairs(self.Wheels) do
		w.Spring.Force = Vector3.zero
		w.Compress = damp(w.Compress, 0, 10, dt)
		w.Part.CFrame = (root.CFrame * CFrame.new(w.Offset))
	end

	self.Speed = vel.Magnitude
	self.Vertical = vel.Y
end

--------------------------------------------------------------------------------
-- landing step
--------------------------------------------------------------------------------
function CarController:_stepLanding(dt, mass, input, g)
	local root = self.Root
	local vel = root.AssemblyLinearVelocity
	if math.abs(vel.Y) > 55 then
		root.AssemblyLinearVelocity = Vector3.new(vel.X, vel.Y * 0.45, vel.Z)
	end
	self.Pitch = damp(self.Pitch, 0, 7, dt)
	self.Roll = damp(self.Roll, 0, 7, dt)
	local target = CFrame.new(root.Position)
		* CFrame.Angles(0, math.atan2(root.CFrame.LookVector.X, root.CFrame.LookVector.Z), 0)
	local err = rotErrorWorld(target.Rotation, root.CFrame.Rotation)
	self.Attitude.MaxTorque = mass * g * 120
	self.Attitude.AngularVelocity = -err * 7
	self.Drive.MaxForce = 0
	self.Grip.Force = Vector3.zero
	-- keep the published numbers live: _stepLanding used to leave Speed/Vertical
	-- frozen at their last flight values, and the touchdown test below then read
	-- a stale "still falling" velocity and never handed control back
	self.Speed = vel.Magnitude
	self.Vertical = vel.Y
	-- Touchdown = near the deck AND not still falling AND roughly upright.
	-- (A "springs are loaded" count also works but is fragile, because a hard
	-- landing parks the deflection at its clamp; these three tests are stable.)
	local upright = math.abs(root.CFrame.RightVector.Y) < 0.45
	if __LANDPROBE then
		__LANDPROBE(self.Altitude, self.Vertical, upright, C.AutoLandAltitude)
	end
	if self.Altitude < C.AutoLandAltitude and self.Vertical < 25 and upright then
		self.Mode = MODE.GROUND
		self:_restoreGroundAuthority()
		self:_setState()
	end
end

--------------------------------------------------------------------------------
-- mode control
--------------------------------------------------------------------------------
function CarController:ToggleFlight()
	if self.Mode == MODE.FLIGHT then
		self:ExitFlight()
	else
		self:EnterFlight()
	end
end

function CarController:EnterFlight()
	if self.Mode == MODE.FLIGHT then
		return
	end
	self.Mode = MODE.FLIGHT
	self.Grip.Force = Vector3.zero
	self.Yaw.MaxTorque = 0
	self.BoostForce.Enabled = false
	self.HoverAlt = self.Root.Position.Y
	self.LandArmed = false
	self.Heading = math.atan2(self.Root.CFrame.LookVector.X, self.Root.CFrame.LookVector.Z)
	self.Root.AssemblyGravityEnabled = false
	self:_setState()
end

function CarController:ExitFlight()
	if self.Mode == MODE.GROUND then
		return
	end
	self.Mode = MODE.LANDING
	self.Root.AssemblyGravityEnabled = true
	self.Attitude.MaxTorque = 0
	self.Drive.MaxForce = 0
	self.BoostForce.Enabled = false
	self.HoverAlt = nil
	self.AirTime = 0
	self:_setState()
end

-- Both ExitFlight and the flight step deliberately park the drive actuator at
-- zero authority (you should not be able to launch off the throttle mid-dive).
-- That means SOMETHING has to hand it back on touchdown, or the car rolls to a
-- stop after landing and never drives again. It bites here for real.
function CarController:_restoreGroundAuthority()
	self.Drive.MaxForce = self._mass * workspace.Gravity * math.max(C.DriveAccelG, 0.5)
	self.Drive.VelocityFactor = 1
	self.Attitude.MaxTorque = 0
	self.Grip.Force = Vector3.zero
	self.BoostForce.Enabled = false
end

function CarController:_setState()
	self.Model:SetAttribute("Mode", self.Mode)
end

function CarController:_onTouched(hit)
	local speed = self.Root.AssemblyLinearVelocity.Magnitude
	if speed > C.CrashForce and os.clock() - self._lastHit > 1 then
		self._lastHit = os.clock()
		self.LastCrashSpeed = speed
		if self.OnCrash ~= nil then
			self.OnCrash(speed, hit)
		end
	end
end

--------------------------------------------------------------------------------
-- main loop: fixed 60Hz substeps so tuning is frame-rate independent
--------------------------------------------------------------------------------
function CarController:Start()
	if self.Conn ~= nil then
		return
	end
	local acc = 0
	self.Conn = RunService.Heartbeat:Connect(function(rawDt)
		local root = self.Root
		if root == nil or root.Parent == nil then
			self:Destroy()
			return
		end
		acc = acc + clamp(rawDt, 1 / 240, 1 / 15)
		local guard = 0
		while acc >= 1 / 60 and guard < 4 do
			acc = acc - 1 / 60
			guard = guard + 1
			self:_step(1 / 60)
		end
		if guard >= 4 then
			acc = 0
		end
	end)
	self:_setState()
end

function CarController:_step(dt)
	self:_refreshOwner(dt)
	self._massAge = self._massAge + dt
	if self._massAge > 0.5 then
		self._massAge = 0
		self._mass = self.Root.AssemblyMass
	end

	local mass = self._mass
	local g = workspace.Gravity
	self._age = self._age + dt
	local settling = self._age < (C.SettleTime or 0.5)
	local input = self:ReadInput()
	if settling then
		input = {
			Throttle = 0,
			Steer = 0,
			Up = false,
			Brake = false,
			Boost = false,
			Pitch = 0,
			Yaw = 0,
			Roll = 0,
			SeatDriven = false,
		}
	end

	if input.Boost and (self.Speed > 5 or self.Mode == MODE.FLIGHT) and self.Boost > 0 then
		self.Boost = clamp(self.Boost - C.BoostDrain * dt, 0, C.BoostCapacity)
		self.Boosting = self.Boost > 1
	else
		self.Boost = clamp(self.Boost + C.BoostRegen * dt, 0, C.BoostCapacity)
		self.Boosting = false
	end

	-- ---- altitude, measured before stepping so flight logic acts on it.
	-- The ray has a finite reach, and above a city the ground genuinely goes out
	-- of range. Freezing GroundY there (my first pass) froze Altitude too, which
	-- silently disabled BOTH the ceiling and auto-land, because both read it.
	-- So: when the ray misses, keep estimating from vertical motion instead.
	local root = self.Root
	local center = root.Position
	local downReach = (self.Altitude or 0) + 600
	local hit = workspace:Raycast(center + Vector3.yAxis * 2, -Vector3.yAxis * downReach, self.RayParams)
	local vy = root.AssemblyLinearVelocity.Y
	if hit ~= nil then
		self.GroundY = hit.Position.Y
		self.GroundResolved = true
	elseif self.GroundY == nil then
		self.GroundY = center.Y
		self.GroundResolved = false
	else
		self.GroundY = self.GroundY - vy * dt
		self.GroundResolved = false
	end
	self.Altitude = math.max(center.Y - self.GroundY, 0)

	if self.ToggleQueued then
		self.ToggleQueued = false
		self:ToggleFlight()
	end

	if self.Mode == MODE.GROUND then
		self:_stepGround(dt, mass, input, g)
		if input.Up and self.Speed > 70 then
			self:EnterFlight()
		end
	elseif self.Mode == MODE.FLIGHT then
		self:_stepFlight(dt, mass, input, g)
		self.AirTime = self.AirTime + dt
		-- Arm auto-land only once the car has actually CLIMBED. Without the arm
		-- step this fires on frame 1 (a car at rest sits below AutoLandAltitude
		-- with vertical velocity 0), so aero cancelled itself the instant you
		-- pressed the key. Classic hysteresis bug: threshold checks need to know
		-- which direction you came from.
		if self.Altitude > (C.LandArmAltitude or 30) then
			self.LandArmed = true
		end
		if self.LandArmed and self.Altitude < C.AutoLandAltitude and self.Vertical <= 0 then
			self.LandArmed = false
			self:ExitFlight()
		end
	else
		self:_stepLanding(dt, mass, input, g)
	end

	-- Numerical hygiene. A CFrame that ever goes NaN (a bad weld, a constraint
	-- fighting a MeshPart with a broken root) never recovers on its own - the
	-- car just becomes an invisible ghost that still holds the server slot. Every
	-- shipped vehicle game guards this; it costs three comparisons.
	local root = self.Root
	local p, v = root.Position, root.AssemblyLinearVelocity
	if p ~= p or p.X ~= p.X or v ~= v or v.X ~= v.X or math.abs(p.Y) > 1e6 or math.abs(v.Magnitude) > 5000 then
		self:_recover()
		return
	end

	self._stateAge = self._stateAge + dt
	if self._stateAge > 0.1 then
		self._stateAge = 0
		self.Model:SetAttribute("Speed", math.floor(self.Speed * 10) / 10)
		self.Model:SetAttribute("Altitude", math.floor(self.Altitude))
		self.Model:SetAttribute("Boost", math.floor(self.Boost))
		self.Model:SetAttribute("AirTime", math.floor(self.AirTime))
		self.Model:SetAttribute("Grounded", self.Grounded)
	end
end

function CarController:_recover()
	local root = self.Root
	local pos = Vector3.new(0, root.Position.Y > 0 and 20 or 20, 0)
	-- rebuild a clean CFrame from the last known-good heading
	local look = root.CFrame.LookVector
	local dirXZ = Vector3.new(look.X, 0, look.Z)
	if dirXZ.Magnitude < 0.01 then
		dirXZ = Vector3.new(0, 0, 1)
	end
	local yaw = math.atan2(dirXZ.X, dirXZ.Z)
	root.CFrame = CFrame.new(root.Position.X, math.max(root.Position.Y, 4), root.Position.Z) * CFrame.Angles(0, yaw, 0)
	root.AssemblyLinearVelocity = Vector3.zero
	root.AssemblyAngularVelocity = Vector3.zero
	self.Pitch, self.Roll, self.Heading = 0, 0, yaw
	self.Speed, self.Vertical, self.Altitude = 0, 0, 0
	self.GroundY = nil
	self.Mode = MODE.GROUND
	self.HoverAlt = root.Position.Y
	self.Root.AssemblyGravityEnabled = true
	self:_restoreGroundAuthority()
	for _, w in ipairs(self.Wheels) do
		w.Compress, w.Deflect = 0, 0
	end
	self.Model:SetAttribute("Recovered", os.clock())
end

function CarController:Destroy()
	if self.Conn ~= nil then
		self.Conn:Disconnect()
		self.Conn = nil
	end
	if self.TouchedConn ~= nil then
		self.TouchedConn:Disconnect()
	end
	pcall(function()
		self.Root.AssemblyGravityEnabled = true
	end)
	if self._cas ~= nil then
		pcall(function()
			self._cas:UnbindAction("RoadsterAero")
		end)
	end
end

return CarController
