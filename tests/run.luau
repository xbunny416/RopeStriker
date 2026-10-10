--[[
	Test runner:  lune run tests/run.luau   (from the repository root)

	Discovers tests/specs/*.spec.luau. Each spec returns `function(t)` where `t` has
	describe / it / expect plus `t.loader(options?)` to build a Loader over the source
	tree. Exits with code 1 when any case fails.
]]

local fs = require("@lune/fs")
local process = require("@lune/process")

local Loader = require("./harness/Loader")
local Test = require("./harness/Test")

local ROOT = process.cwd

local specFiles = {}
for _, entry in fs.readDir("tests/specs") do
	if string.match(entry, "%.spec%.luau$") then
		table.insert(specFiles, entry)
	end
end
table.sort(specFiles)

local totalPassed, totalFailed = 0, 0
local allFailures = {}

for _, file in specFiles do
	local session = Test.newSession()
	local api = {
		describe = session.describe,
		it = session.it,
		expect = Test.expect,
		root = ROOT,
		loader = function(options: any?)
			local resolved = options or {}
			resolved.root = ROOT
			return Loader.new(resolved)
		end,
	}
	local ok, specOrError = pcall(require, `./specs/{string.gsub(file, "%.luau$", "")}`)
	if not ok then
		totalFailed += 1
		table.insert(allFailures, `[{file}] failed to load: {specOrError}`)
		continue
	end
	local defineOk, defineError = pcall(specOrError, api)
	if not defineOk then
		totalFailed += 1
		table.insert(allFailures, `[{file}] failed while defining tests: {defineError}`)
		continue
	end
	local passed, failed, failures = session.run(file)
	totalPassed += passed
	totalFailed += failed
	for _, failure in failures do
		table.insert(allFailures, failure)
	end
	print(string.format("%-34s %3d passed  %d failed", file, passed, failed))
end

print(string.rep("-", 60))
for _, failure in allFailures do
	print("FAIL " .. failure)
end
print(`{totalPassed} passed, {totalFailed} failed`)
process.exit(if totalFailed > 0 then 1 else 0)
