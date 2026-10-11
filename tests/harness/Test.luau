--[[
	Test
	----
	A tiny describe/it/expect runner for Lune.
]]

local Test = {}

type Case = { Name: string, Fn: () -> () }
type Suite = { Name: string, Cases: { Case } }

local function format(value: any): string
	if type(value) == "string" then
		return string.format("%q", value)
	elseif type(value) == "table" then
		local parts = {}
		for key, child in value do
			table.insert(parts, `{tostring(key)}={format(child)}`)
			if #parts > 8 then
				table.insert(parts, "...")
				break
			end
		end
		return "{" .. table.concat(parts, ", ") .. "}"
	end
	return tostring(value)
end

local function deepEqual(a: any, b: any): boolean
	if a == b then
		return true
	end
	if type(a) ~= "table" or type(b) ~= "table" then
		return false
	end
	for key, value in a do
		if not deepEqual(value, b[key]) then
			return false
		end
	end
	for key in b do
		if a[key] == nil then
			return false
		end
	end
	return true
end

function Test.expect(actual: any)
	local matchers = {}
	function matchers.toBe(expected: any)
		if actual ~= expected then
			error(`expected {format(expected)}, got {format(actual)}`, 2)
		end
	end
	function matchers.toEqual(expected: any)
		if not deepEqual(actual, expected) then
			error(`expected {format(expected)}, got {format(actual)}`, 2)
		end
	end
	function matchers.toBeNear(expected: number, epsilon: number?)
		if type(actual) ~= "number" or math.abs(actual - expected) > (epsilon or 1e-6) then
			error(`expected ~{expected}, got {format(actual)}`, 2)
		end
	end
	function matchers.toBeTruthy()
		if not actual then
			error(`expected truthy, got {format(actual)}`, 2)
		end
	end
	function matchers.toBeFalsy()
		if actual then
			error(`expected falsy, got {format(actual)}`, 2)
		end
	end
	function matchers.toBeNil()
		if actual ~= nil then
			error(`expected nil, got {format(actual)}`, 2)
		end
	end
	function matchers.toBeGreaterThan(expected: number)
		if not (actual > expected) then
			error(`expected > {expected}, got {format(actual)}`, 2)
		end
	end
	function matchers.toBeLessThan(expected: number)
		if not (actual < expected) then
			error(`expected < {expected}, got {format(actual)}`, 2)
		end
	end
	function matchers.toContain(expected: any)
		if type(actual) == "string" then
			if string.find(actual, expected, 1, true) == nil then
				error(`expected {format(actual)} to contain {format(expected)}`, 2)
			end
		elseif table.find(actual, expected) == nil then
			error(`expected list to contain {format(expected)}`, 2)
		end
	end
	function matchers.toThrow(fragment: string?)
		local ok, err = pcall(actual)
		if ok then
			error("expected function to throw", 2)
		end
		if fragment and string.find(tostring(err), fragment, 1, true) == nil then
			error(`expected error containing {format(fragment)}, got {format(tostring(err))}`, 2)
		end
	end
	return matchers
end

function Test.newSession()
	local suites: { Suite } = {}
	local current: Suite? = nil
	local session = {}

	function session.describe(name: string, body: () -> ())
		local suite: Suite = { Name = name, Cases = {} }
		table.insert(suites, suite)
		local previous = current
		current = suite
		body()
		current = previous
	end

	function session.it(name: string, fn: () -> ())
		local suite = current
		if suite == nil then
			error("it() must be called inside describe()")
		end
		table.insert(suite.Cases, { Name = name, Fn = fn })
	end

	function session.run(fileLabel: string): (number, number, { string })
		local passed, failed = 0, 0
		local failures: { string } = {}
		for _, suite in suites do
			for _, case in suite.Cases do
				local ok, err = pcall(case.Fn)
				if ok then
					passed += 1
				else
					failed += 1
					table.insert(failures, `[{fileLabel}] {suite.Name} > {case.Name}\n      {tostring(err)}`)
				end
			end
		end
		return passed, failed, failures
	end

	return session
end

return Test
