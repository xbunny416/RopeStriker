--!strict
--[[
	Zones
	-----
	Pure spatial queries over the world layout in GameConfig. The server uses them as
	the authority (rewards, portal enforcement, training eligibility); the client uses
	the same functions to swap the Action Button between JUMP and SWING instantly.
]]

local GameConfig = require(script.Parent.Parent.Configuration.GameConfig)
local Spatial = require(script.Parent.Spatial)

local World = GameConfig.World

local Zones = {}

-- Era sector containing the position (sectors are slabs along the X axis).
function Zones.EraAt(position: Vector3): number
	for _, era in GameConfig.Eras do
		if position.X >= era.SectorMinX and position.X < era.SectorMaxX then
			return era.Index
		end
	end
	if position.X < GameConfig.Eras[1].SectorMinX then
		return 1
	end
	return GameConfig.Eras[#GameConfig.Eras].Index
end

-- Inside the Grand Colosseum arena floor (walls included).
function Zones.IsInColosseum(position: Vector3, padding: number?): boolean
	return Spatial.HorizontalDistance(position, World.ColosseumCenter) <= World.ColosseumRadius + (padding or 0)
end

-- Combat zones swap the Action Button to SWING and enable mob aggro on the player.
function Zones.ModeAt(position: Vector3): GameConfig.PlayerMode
	if Zones.IsInColosseum(position) then
		return "Combat"
	end
	return "Training"
end

function Zones.IsNearObelisk(position: Vector3, distance: number): boolean
	return (position - World.ObeliskPosition).Magnitude <= distance
end

-- Portal guarding entry into the given era, if any.
function Zones.PortalIntoEra(eraIndex: number): GameConfig.PortalData?
	for _, portal in GameConfig.Portals do
		if portal.ToEra == eraIndex then
			return portal
		end
	end
	return nil
end

function Zones.EraData(eraIndex: number): GameConfig.EraData
	return GameConfig.Eras[math.clamp(eraIndex, 1, #GameConfig.Eras)]
end

return Zones
