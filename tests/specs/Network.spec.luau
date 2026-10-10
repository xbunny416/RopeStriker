-- The RemoteEvents folder authored for Rojo, the canonical definitions and the typed
-- Remotes module must agree exactly.

return function(t)
	local describe, it, expect = t.describe, t.it, t.expect
	local fs = require("@lune/fs")
	local serde = require("@lune/serde")
	local loader = t.loader()
	local Definitions = loader:require("src/ReplicatedStorage/Source/Network/Definitions.luau")

	local folder = "src/ReplicatedStorage/Source/Network/RemoteEvents"

	describe("Network", function()
		it("has one model file per definition with the same class", function()
			local files = {}
			for _, entry in fs.readDir(folder) do
				local name = string.match(entry, "^(.+)%.model%.json$")
				if name then
					local model = serde.decode("json", fs.readFile(`{folder}/{entry}`))
					files[name] = model.className
				end
			end
			local declared = {}
			for _, definition in Definitions do
				declared[definition.Name] = definition.Class
				expect(files[definition.Name]).toBe(definition.Class)
			end
			for name in files do
				expect(declared[name] ~= nil).toBe(true)
			end
		end)

		it("exposes every declared remote in Remotes.luau", function()
			local source = fs.readFile("src/ReplicatedStorage/Source/Network/Remotes.luau")
			local exposed = {}
			for name in string.gmatch(source, 'get%("([%w_]+)"%)') do
				exposed[name] = true
			end
			for _, definition in Definitions do
				expect(exposed[definition.Name]).toBe(true)
			end
		end)

		it("has unique names", function()
			local seen = {}
			for _, definition in Definitions do
				expect(seen[definition.Name]).toBeNil()
				seen[definition.Name] = true
			end
		end)
	end)
end
