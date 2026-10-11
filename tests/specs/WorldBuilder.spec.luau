-- Smoke test: build the procedural world, mob rigs and pet models against Lune's
-- Roblox instance model, which rejects unknown properties and invalid enum values.

return function(t)
	local describe, it, expect = t.describe, t.it, t.expect
	local roblox = require("@lune/roblox")

	local function countTagged(root, tag: string): number
		local count = 0
		for _, descendant in root:GetDescendants() do
			if descendant:HasTag(tag) then
				count += 1
			end
		end
		return count
	end

	describe("WorldBuilder", function()
		local game = roblox.Instance.new("DataModel")
		local workspaceInstance = game:GetService("Workspace")
		local loader = t.loader({
			services = {
				Lighting = game:GetService("Lighting"),
				Workspace = workspaceInstance,
			},
		})
		local GameConfig = loader:require("src/ReplicatedStorage/Source/Configuration/GameConfig.luau")
		local Tags = loader:require("src/ReplicatedStorage/Source/Shared/Tags.luau")
		local WorldBuilder = loader:require("src/ServerScriptService/Source/World/WorldBuilder.luau")

		local world = WorldBuilder.Build(workspaceInstance)

		it("parents a single ChronoWorld model", function()
			expect(world.Name).toBe("ChronoWorld")
			expect(world.Parent).toBe(workspaceInstance)
		end)

		it("tags every interactable the services rely on", function()
			expect(countTagged(world, Tags.EpochObelisk)).toBe(#GameConfig.Eras)
			expect(countTagged(world, Tags.ObeliskPedestal)).toBe(#GameConfig.Eras)
			local eggCount = 0
			for _ in GameConfig.Eggs do
				eggCount += 1
			end
			expect(countTagged(world, Tags.ChronoEgg)).toBe(eggCount)
			expect(countTagged(world, Tags.MobSpawner)).toBe(#GameConfig.Spawners)
			local portalCount = 0
			for _ in GameConfig.Portals do
				portalCount += 1
			end
			expect(countTagged(world, Tags.ChronalRiftGate)).toBe(portalCount)
			expect(countTagged(world, Tags.PanelPrompt)).toBe(2)
		end)

		it("gives each spawner and rift the attributes gameplay reads", function()
			for _, descendant in world:GetDescendants() do
				if descendant:HasTag(Tags.MobSpawner) then
					expect(GameConfig.Mobs[descendant:GetAttribute("MobId")] ~= nil).toBe(true)
				elseif descendant:HasTag(Tags.ChronalRiftGate) then
					local portal = GameConfig.Portals[descendant:GetAttribute("PortalId")]
					expect(portal ~= nil).toBe(true)
					expect(descendant.CanCollide).toBe(true)
				end
			end
		end)

		it("stays within a mobile-friendly part budget and material palette", function()
			local parts = 0
			-- Bible §3.2 palette (ForceField only on rift barriers).
			local allowed = { SmoothPlastic = true, Neon = true, Pebble = true, ForceField = true }
			for _, descendant in world:GetDescendants() do
				if descendant:IsA("BasePart") then
					parts += 1
					expect(allowed[descendant.Material.Name]).toBe(true)
					expect(descendant.Anchored).toBe(true)
				end
			end
			expect(parts).toBeLessThan(1500)
			print(`    procedural world: {parts} parts`)
		end)

		it("applies lighting without errors", function()
			WorldBuilder.ApplyLighting()
			expect(game:GetService("Lighting"):FindFirstChild("ChronoBloom") ~= nil).toBe(true)
		end)
	end)

	describe("Procedural rigs", function()
		local game = roblox.Instance.new("DataModel")
		local loader = t.loader({
			services = {
				ServerStorage = game:GetService("ServerStorage"),
				Workspace = game:GetService("Workspace"),
			},
		})
		local GameConfig = loader:require("src/ReplicatedStorage/Source/Configuration/GameConfig.luau")
		local PetModels = loader:require("src/StarterPlayer/StarterPlayerScripts/Source/Modules/PetModels.luau")

		it("builds every pet under the 500-triangle budget", function()
			for petId in GameConfig.Pets do
				local model = PetModels.Build(petId)
				expect(model ~= nil).toBe(true)
				expect(model.PrimaryPart ~= nil).toBe(true)
				local parts = 0
				for _, descendant in model:GetDescendants() do
					if descendant:IsA("BasePart") then
						parts += 1
					end
				end
				-- Blocks are 12 triangles, wedges 8: stay well under the budget.
				expect(parts * 12).toBeLessThan(500)
			end
		end)
	end)
end
