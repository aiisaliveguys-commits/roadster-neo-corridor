--[[
	Keeps test/Config.lua honest.

	The harness loads a MIRROR of Config.Car, because the real Config module is
	written for Roblox (it touches Enum.KeyCode and Color3). A mirror silently
	drifts - and a drifted mirror means the harness is testing numbers the game
	will never use, which is worse than not testing at all. This compares the two
	key sets and fails CI on any key that exists in one and not the other.

	Usage: lua5.1 test/config_drift.lua
]]
local function load(path)
	local chunk = assert(loadfile(path))
	local env = {
		Enum = setmetatable({}, {
			__index = function(t, k)
				local g = setmetatable({}, {
					__index = function(u, n)
						u[n] = "Enum." .. k .. "." .. n
						return u[n]
					end,
				})
				t[k] = g
				return g
			end,
		}),
		-- Color3 is only used as a value in Config, never operated on here.
		Color3 = {
			fromRGB = function(r, g, b)
				return string.format("rgb(%d,%d,%d)", r, g, b)
			end,
		},
	}
	setfenv(chunk, setmetatable(env, { __index = _G }))
	return chunk()
end

local real = load("src/shared/Config.lua")
local mirror = load("test/Config.lua")

local function keys(t)
	local set = {}
	for k in pairs(t) do
		set[k] = true
	end
	return set
end
local function diff(a, b, label)
	local missing = {}
	for k in pairs(a) do
		if not b[k] then
			missing[#missing + 1] = k
		end
	end
	table.sort(missing)
	if #missing > 0 then
		print(string.format("  MISMATCH  %s: in %s but not in the mirror: %s", table.concat(missing, ", "), label, ""))
	end
	return missing
end

local ok = true
for _, sect in ipairs({ "Car", "Wanted", "Mission" }) do
	local a, b = keys(real[sect] or {}), keys(mirror[sect] or {})
	local onlyReal, onlyMirror = {}, {}
	for k in pairs(a) do
		if not b[k] then
			onlyReal[#onlyReal + 1] = k
		end
	end
	for k in pairs(b) do
		if not a[k] then
			onlyMirror[#onlyMirror + 1] = k
		end
	end
	table.sort(onlyReal)
	table.sort(onlyMirror)
	if #onlyReal > 0 or #onlyMirror > 0 then
		ok = false
		print(string.format("== %s ==", sect))
		if #onlyReal > 0 then
			print("   in src/shared/Config.lua but MISSING from test/Config.lua: " .. table.concat(onlyReal, ", "))
		end
		if #onlyMirror > 0 then
			print("   in test/Config.lua but not in the real Config (dead mirror keys): " .. table.concat(onlyMirror, ", "))
		end
	end
	-- value drift for keys present in both
	for k in pairs(a) do
		if b[k] ~= nil and type(a[k]) == "number" and type(b[k]) == "number" and a[k] ~= b[k] then
			ok = false
			print(string.format("   %s.%s value differs: real=%s mirror=%s", sect, k, tostring(a[k]), tostring(b[k])))
		end
	end
end
print(ok and "config mirror in sync" or "CONFIG MIRROR DRIFT")
os.exit(ok and 0 or 1)
