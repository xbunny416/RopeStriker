--!strict
--[[
	ChronoRope: Epoch Striker - client bootstrap.

	Waits for the initial replication snapshot, starts the profile mirror, then
	initialises (no yielding) and starts every controller in dependency order.
]]

if not game:IsLoaded() then
	game.Loaded:Wait()
end

local Controllers = script.Parent.Controllers
local ClientState = require(script.Parent.Modules.ClientState)
local SoundPlayer = require(script.Parent.Modules.SoundPlayer)

type Controller = {
	Init: () -> (),
	Start: () -> (),
}

local ordered: { { Name: string, Module: Controller } } = {
	{ Name = "RopeController", Module = require(Controllers.RopeController) },
	{ Name = "UIController", Module = require(Controllers.UIController) },
	{ Name = "MobVisualsController", Module = require(Controllers.MobVisualsController) },
	{ Name = "PetController", Module = require(Controllers.PetController) },
	{ Name = "PortalController", Module = require(Controllers.PortalController) },
	{ Name = "WorldController", Module = require(Controllers.WorldController) },
}

ClientState.Start()
task.spawn(SoundPlayer.Verify)

for _, entry in ordered do
	local ok, err = pcall(entry.Module.Init :: any)
	if not ok then
		warn(`[ChronoRope] {entry.Name}.Init failed: {err}`)
	end
end

for _, entry in ordered do
	local ok, err = pcall(entry.Module.Start :: any)
	if not ok then
		warn(`[ChronoRope] {entry.Name}.Start failed: {err}`)
	end
end
