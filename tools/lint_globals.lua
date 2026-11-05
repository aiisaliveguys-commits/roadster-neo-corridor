--[[
	Finds calls to names that are never defined in the file.

	Why this exists: two patches of mine collided in VehicleSpawner and deleted the
	definition of `prepare()` while leaving its call sites. `luac -p` was happy (the
	file was syntactically perfect), the physics suite was happy (it does not load the
	spawner), and the place file would have thrown "attempt to call a nil value" the
	first time a player joined - on the user's machine, not in CI. It also caught a
	debug call left behind by a removed hook, which would have crashed every landing.

	Approach: ONE left-to-right scanner that both blanks comments/strings and collects
	definitions. Pattern-only attempts fail here, and each failure mode was hit for
	real: a "--" lives inside strings, a long bracket opens both a string and a
	comment, and English prose like "TWO homes (no duplicated physics)" reads as a call
	to an undefined function. A linter that cries wolf is a linter that gets deleted.

	Usage: lua5.1 tools/lint_globals.lua FILE...
]]

local GLOBALS = {}
for w in ("game workspace script task wait spawn delay warn print require tick \
Instance Enum Vector3 Vector2 CFrame Color3 UDim UDim2 Rect NumberRange \
PhysicalProperties RaycastParams OverlapParams TouchParams Random TweenInfo \
DateTime Buffer os math table string utf8 bit32 coroutine io debug \
assert error type tostring tonumber setmetatable getmetatable rawget rawset \
select next ipairs pairs unpack pack newproxy typeof load loadstring loadfile \
setfenv getfenv module package arg pcall xpcall"):gmatch("%S+") do
	GLOBALS[w] = true
end

local KEYWORDS = {}
for w in ("and or not then do end if elseif else return function in repeat until \
break goto nil true false"):gmatch("%S+") do
	KEYWORDS[w] = true
end

local B = string.byte
local S = string.sub

-- If src[i] opens a long bracket, return the index just past its match. Character
-- codes, because writing the literal bracket form in this file breaks this file.
local function longBracket(src, i, n)
	if B(src, i) ~= B("[") then
		return nil
	end
	local j = i + 1
	local level = 0
	while j <= n and B(src, j) == B("=") do
		level = level + 1
		j = j + 1
	end
	if B(src, j) ~= B("[") then
		return nil
	end
	-- scan for the matching close at the same level
	local k = j + 1
	while k <= n do
		if B(src, k) == B("]") then
			local p = k + 1
			local cnt = 0
			while p <= n and B(src, p) == B("=") do
				cnt = cnt + 1
				p = p + 1
			end
			if cnt == level and B(src, p) == B("]") then
				return p + 1
			end
		end
		k = k + 1
	end
	return n + 1
end

local function isWordChar(c)
	return c >= B("a") and c <= B("z") or c >= B("A") and c <= B("Z") or c == B("_") or c >= B("0") and c <= B("9")
end

local function isWordStart(c)
	return c >= B("a") and c <= B("z") or c >= B("A") and c <= B("Z") or c == B("_")
end

local function scan(src)
	local n = #src
	local out, defs = {}, {}
	local pending = nil -- the previous word, for "local X" / "function X"

	local i = 1
	while i <= n do
		local c = B(src, i)
		if c == B("-") and B(src, i + 1) == B("-") then
			local after = longBracket(src, i + 2, n)
			if after then
				i = after
			else
				local e = string.find(src, "\n", i + 2, true)
				i = e and (e + 1) or (n + 1)
			end
			out[#out + 1] = " "
		elseif c == B("[") then
			local after = longBracket(src, i, n)
			if after then
				i = after
				out[#out + 1] = " "
			else
				out[#out + 1] = "["
				i = i + 1
			end
		elseif c == B('"') or c == B("'") then
			local j = i + 1
			while j <= n do
				local d = B(src, j)
				if d == B("\\") then
					j = j + 2
				elseif d == c or d == B("\n") then
					break
				else
					j = j + 1
				end
			end
			out[#out + 1] = '""'
			i = j + 1
		elseif isWordStart(c) then
			local j = i
			while j <= n and isWordChar(B(src, j)) do
				j = j + 1
			end
			local word = S(src, i, j - 1)
			if pending == "local" or pending == "function" then
				defs[word] = true
			end
			out[#out + 1] = word
			i = j
			pending = word
		else
			out[#out + 1] = S(src, i, i)
			-- carry "local"/"function" across whitespace and commas so a name on the
			-- next line still counts; clear it at a paren or any other punctuation
			if c == B("(") or c == B(")") then
				pending = nil
			elseif c ~= B(" ") and c ~= B("\t") and c ~= B("\n") and c ~= B("\r") and c ~= B(",") then
				pending = nil
			end
			i = i + 1
		end
	end
	return table.concat(out), defs
end

local function checkFile(path)
	local f = io.open(path, "r")
	if not f then
		return { "cannot open " .. path }
	end
	local src = f:read("*a")
	f:close()
	local code, defs = scan(src)

	-- Multi-name and parameter forms the single-token pass above cannot see:
	--   local a, b = ...    for k, v in ...    function(a, b)
	-- These run on the RAW source on purpose: the scanner blanks string contents,
	-- and "local" / "function" inside a string are harmless here, but running these
	-- on the stripped code found nothing at all - the keywords had already been
	-- replaced by spaces, so every named parameter looked undefined.
	for list in src:gmatch("local%s+([%a_][%w_,%s]-)=") do
		for name in list:gmatch("[%a_][%w_]+") do
			defs[name] = true
		end
	end
	for list in src:gmatch("for%s+([%a_][%w_,%s]+)%s+in") do
		for name in list:gmatch("[%a_][%w_]+") do
			defs[name] = true
		end
	end
	for params in src:gmatch("function%s+[%a_%w]*%s*%(([^)]*)%)") do
		for name in params:gmatch("[%a_][%w_]+") do
			defs[name] = true
		end
	end

	local errs, seen = {}, {}
	for line in code:gmatch("[^\n]+") do
		-- bare call: NAME( where NAME is not a method (obj:NAME) or a field (t.NAME)
		for pre, name in line:gmatch("([%W])([%a_][%w_]*)%s*%(") do
			if pre ~= ":" and pre ~= "." and not defs[name] and not GLOBALS[name] and not KEYWORDS[name] then
				if not seen[name] then
					seen[name] = true
					errs[#errs + 1] = string.format("  undefined call: %s  |  %s", name, line:match("^%s*(.-)$"):sub(1, 72))
				end
			end
		end
		local first = line:match("^([%a_][%w_]*)%s*%(")
		if first and not defs[first] and not GLOBALS[first] and not KEYWORDS[first] and not seen[first] then
			seen[first] = true
			errs[#errs + 1] = string.format("  undefined call: %s  |  %s", first, line:match("^%s*(.-)$"):sub(1, 72))
		end
	end
	return errs
end

local total = 0
for i = 1, #arg do
	local errs = checkFile(arg[i])
	if #errs > 0 then
		print(arg[i])
		for _, e in ipairs(errs) do
			print(e)
		end
		total = total + #errs
	end
end
if total > 0 then
	print("")
	print(string.format("%d undefined call(s). If one is a real Roblox global, add it to GLOBALS.", total))
	os.exit(1)
end
print(string.format("no undefined calls in %d file(s)", #arg))
