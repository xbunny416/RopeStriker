-- SoundPlayer.Verify: ids that fail to load fall back (or mute) instead of erroring on
-- every playback. ContentProvider is mocked to fail chosen ids.

return function(t)
	local describe, it, expect = t.describe, t.it, t.expect
	local roblox = require("@lune/roblox")
	local Mock = require("../harness/RobloxMock")

	local Enum = roblox.Enum
	local PATH = "src/StarterPlayer/StarterPlayerScripts/Source/Modules/SoundPlayer.luau"
	local GameConfig = t.loader():require("src/ReplicatedStorage/Source/Configuration/GameConfig.luau")
	local whoosh = GameConfig.Sounds.RopeWhoosh

	local function load(failing: { [string]: boolean })
		local preloaded = {}
		local contentProvider = Mock.instance("ContentProvider")
		function contentProvider:PreloadAsync(list: { any }, callback: (string, any) -> ())
			for _, item in list do
				local id = item.SoundId
				table.insert(preloaded, id)
				callback(id, if failing[id] then Enum.AssetFetchStatus.Failure else Enum.AssetFetchStatus.Success)
			end
		end
		local loader = t.loader({
			services = {
				ContentProvider = contentProvider,
				Debris = Mock.instance("Debris"),
				SoundService = Mock.instance("SoundService"),
				__Instance = { new = Mock.instance },
			},
		})
		return loader:require(PATH), preloaded
	end

	describe("SoundPlayer", function()
		it("keeps ids that load and preloads each id once", function()
			local SoundPlayer, preloaded = load({})
			SoundPlayer.Verify()
			for key, config in GameConfig.Sounds do
				expect(SoundPlayer.GetSoundId(key)).toBe(config.SoundId)
			end
			local seen = {}
			for _, id in preloaded do
				expect(seen[id]).toBeNil()
				seen[id] = true
			end
		end)

		it("falls back past ids that fail to load", function()
			local SoundPlayer = load({ [whoosh.SoundId] = true })
			expect(SoundPlayer.GetSoundId("RopeWhoosh")).toBe(whoosh.SoundId) -- until verified
			SoundPlayer.Verify()
			expect(SoundPlayer.GetSoundId("RopeWhoosh")).toBe((whoosh.Fallbacks :: { string })[1])
			expect(SoundPlayer.GetSoundId("WhipCrack")).toBe(GameConfig.Sounds.WhipCrack.SoundId)
		end)

		it("mutes a sound when every candidate fails", function()
			local failing = { [whoosh.SoundId] = true }
			for _, fallback in whoosh.Fallbacks :: { string } do
				failing[fallback] = true
			end
			local SoundPlayer = load(failing)
			SoundPlayer.Verify()
			expect(SoundPlayer.GetSoundId("RopeWhoosh")).toBe("")
			expect(SoundPlayer.Play("RopeWhoosh")).toBeNil()
		end)
	end)
end
