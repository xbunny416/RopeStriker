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

	SoundPlayer.Verify() (run once at startup) preloads every configured id. An id that
	fails to load is replaced by its first working fallback, or muted, with one warning,
	instead of erroring on every playback.
]]

local ContentProvider = game:GetService("ContentProvider")
local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

local GameConfig = require(ReplicatedStorage.Source.Configuration.GameConfig)

local MAX_LIFETIME = 6

local SoundPlayer = {}

local resolved: { [string]: string } = {} -- key -> id in use ("" = muted)
local loadResults: { [string]: boolean } = {}

-- The id `key` plays with: the configured one until Verify picks otherwise.
function SoundPlayer.GetSoundId(key: string): string
	local id = resolved[key]
	if id then
		return id
	end
	local config = GameConfig.Sounds[key]
	return if config then config.SoundId else ""
end

local function loads(soundId: string): boolean
	local cached = loadResults[soundId]
	if cached ~= nil then
		return cached
	end
	local failed = false
	local probe = Instance.new("Sound")
	probe.SoundId = soundId
	local ok = pcall(function()
		ContentProvider:PreloadAsync({ probe }, function(_contentId: string, status: Enum.AssetFetchStatus)
			-- Only an explicit failure counts; anything else keeps the sound.
			if status == Enum.AssetFetchStatus.Failure then
				failed = true
			end
		end)
	end)
	probe:Destroy()
	local result = ok and not failed
	loadResults[soundId] = result
	return result
end

-- Yields while preloading; call it from its own thread.
function SoundPlayer.Verify()
	for key, config in GameConfig.Sounds do
		if config.SoundId == "" then
			continue
		end
		local candidates: { string } = { config.SoundId }
		local fallbacks = config.Fallbacks
		if fallbacks then
			for _, fallback in fallbacks do
				table.insert(candidates, fallback)
			end
		end
		local chosen = ""
		for _, candidate in candidates do
			if loads(candidate) then
				chosen = candidate
				break
			end
		end
		resolved[key] = chosen
		if chosen == "" then
			warn(`[SoundPlayer] {key}: {config.SoundId} failed to load and has no working fallback; muted`)
		elseif chosen ~= config.SoundId then
			warn(`[SoundPlayer] {key}: {config.SoundId} failed to load; using {chosen}`)
		end
	end
end

local function create(key: string, playbackSpeed: number?, volume: number?): Sound?
	local config = GameConfig.Sounds[key]
	local soundId = SoundPlayer.GetSoundId(key)
	if config == nil or soundId == "" then
		return nil
	end
	local sound = Instance.new("Sound")
	sound.Name = key
	sound.SoundId = soundId
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
