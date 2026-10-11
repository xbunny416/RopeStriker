--!strict
--[[
	WorldService
	------------
	Boots the world: builds the procedural greybox when the place has no authored map
	(no Workspace.ChronoWorld), applies the stylised lighting rig, and exposes
	tag-based lookups for the interactables other services drive.

	Level designers can bake the greybox into the place from the Studio command bar:
	    require(game.ServerScriptService.Source.World.WorldBuilder).Build(workspace)
	then save; the runtime build is skipped from then on.
]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Tags = require(ReplicatedStorage.Source.Shared.Tags)
local WorldBuilder = require(script.Parent.Parent.World.WorldBuilder)

local WorldService = {}

function WorldService.Init()
	if workspace:FindFirstChild("ChronoWorld") == nil then
		local started = os.clock()
		WorldBuilder.Build(workspace)
		print(`[WorldService] Built procedural world in {math.floor((os.clock() - started) * 1000)}ms`)
	end
	WorldBuilder.ApplyLighting()
end

function WorldService.Start() end

-- Every obelisk model (one per era sector).
function WorldService.GetObelisks(): { Model }
	local result: { Model } = {}
	for _, instance in CollectionService:GetTagged(Tags.EpochObelisk) do
		if instance:IsA("Model") then
			table.insert(result, instance)
		end
	end
	return result
end

-- Banking pads around the obelisks.
function WorldService.GetPedestals(): { BasePart }
	local result: { BasePart } = {}
	for _, instance in CollectionService:GetTagged(Tags.ObeliskPedestal) do
		if instance:IsA("BasePart") then
			table.insert(result, instance)
		end
	end
	return result
end

-- Spawner markers keyed by SpawnerId.
function WorldService.GetSpawnerMarkers(): { [string]: BasePart }
	local result: { [string]: BasePart } = {}
	for _, instance in CollectionService:GetTagged(Tags.MobSpawner) do
		local spawnerId = instance:GetAttribute("SpawnerId")
		if instance:IsA("BasePart") and type(spawnerId) == "string" then
			result[spawnerId] = instance
		end
	end
	return result
end

-- Egg models keyed by EggId.
function WorldService.GetEggs(): { [string]: Model }
	local result: { [string]: Model } = {}
	for _, instance in CollectionService:GetTagged(Tags.ChronoEgg) do
		local eggId = instance:GetAttribute("EggId")
		if instance:IsA("Model") and type(eggId) == "string" then
			result[eggId] = instance
		end
	end
	return result
end

-- Distance from a position to the closest obelisk (math.huge when none exist).
function WorldService.DistanceToNearestObelisk(position: Vector3): number
	local best = math.huge
	for _, obelisk in WorldService.GetObelisks() do
		local distance = (obelisk:GetPivot().Position - position).Magnitude
		if distance < best then
			best = distance
		end
	end
	return best
end

return WorldService
