--!strict
--[[
	ChronoRope: Epoch Striker - server bootstrap.

	Services are initialised in dependency order (Init wires remotes and state, no
	yielding), then started (Start connects players, loops and world interactions).
]]

local Services = script.Parent.Services

type Service = {
	Init: () -> (),
	Start: () -> (),
}

local ordered: { { Name: string, Module: Service } } = {
	{ Name = "WorldService", Module = require(Services.WorldService) },
	{ Name = "DataService", Module = require(Services.DataService) },
	{ Name = "EquipmentService", Module = require(Services.EquipmentService) },
	{ Name = "PetService", Module = require(Services.PetService) },
	{ Name = "TrainingService", Module = require(Services.TrainingService) },
	{ Name = "MobService", Module = require(Services.MobService) },
	{ Name = "CombatService", Module = require(Services.CombatService) },
	{ Name = "PortalService", Module = require(Services.PortalService) },
	{ Name = "RebirthService", Module = require(Services.RebirthService) },
}

local started = os.clock()

for _, entry in ordered do
	local ok, err = pcall(entry.Module.Init :: any)
	if not ok then
		error(`[ChronoRope] {entry.Name}.Init failed: {err}`)
	end
end

for _, entry in ordered do
	local ok, err = pcall(entry.Module.Start :: any)
	if not ok then
		error(`[ChronoRope] {entry.Name}.Start failed: {err}`)
	end
end

print(`[ChronoRope] Server ready in {math.floor((os.clock() - started) * 1000)}ms`)
