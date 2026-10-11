--!strict
--[[
	SoundPlayer
	-----------
	Fire-and-forget SFX from GameConfig.Sounds (Bible §4.4).

	    SoundPlayer.Play("RopeWhoosh", rootPart, pitch)    -- attached to a part
	    SoundPlayer.PlayAt("WhipCrack", hitPosition)       -- spatial, with falloff
	    SoundPlayer.Play("ObeliskBank")                    -- 2D

	Positional sounds use InverseTapered roll-off up to the configured
	RollOffMaxDistance so far-away whip cracks fade out naturally.
]]

local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

local GameConfig = require(ReplicatedStorage.Source.Configuration.GameConfig)

local MAX_LIFETIME = 6

local SoundPlayer = {}

local function create(key: string, playbackSpeed: number?, volume: number?): Sound?
	local config = GameConfig.Sounds[key]
	if config == nil or config.SoundId == "" then
		return nil
	end
	local sound = Instance.new("Sound")
	sound.Name = key
	sound.SoundId = config.SoundId
	sound.Volume = config.Volume * (volume or 1)
	sound.PlaybackSpeed = playbackSpeed or 1
	sound.RollOffMode = Enum.RollOffMode.InverseTapered
	sound.RollOffMinDistance = 8
	sound.RollOffMaxDistance = config.RollOffMaxDistance
	return sound
end

local function play(sound: Sound, holder: Instance): Sound
	sound.Parent = holder
	sound.Ended:Once(function()
		sound:Destroy()
	end)
	Debris:AddItem(sound, MAX_LIFETIME)
	sound:Play()
	return sound
end

-- Plays on `parent` (spatial when it is a part/attachment) or in 2D when parent is nil.
function SoundPlayer.Play(key: string, parent: Instance?, playbackSpeed: number?, volume: number?): Sound?
	local sound = create(key, playbackSpeed, volume)
	if sound == nil then
		return nil
	end
	return play(sound, parent or SoundService)
end

-- Plays at a world position with distance falloff.
function SoundPlayer.PlayAt(key: string, position: Vector3, playbackSpeed: number?, volume: number?): Sound?
	local sound = create(key, playbackSpeed, volume)
	if sound == nil then
		return nil
	end
	local point = Instance.new("Attachment")
	point.Name = `{key}Emitter`
	point.Position = position -- Terrain sits at the origin, so local == world
	point.Parent = workspace.Terrain
	Debris:AddItem(point, MAX_LIFETIME)
	return play(sound, point)
end

return SoundPlayer
