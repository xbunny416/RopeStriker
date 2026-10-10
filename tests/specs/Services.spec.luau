-- Integration tests: the real DataService, TrainingService and CombatService running
-- against the mocked engine (tests/harness/RobloxMock.luau).

return function(t)
	local describe, it, expect = t.describe, t.it, t.expect
	local roblox = require("@lune/roblox")
	local Mock = require("../harness/RobloxMock")

	local Vector3 = roblox.Vector3
	local CFrame = roblox.CFrame

	local SERVICES = "src/ServerScriptService/Source/Services/"

	-- Builds an isolated server world. `extraOverrides` replaces modules by path.
	local function world(extraOverrides: { [string]: any }?)
		local players = Mock.players()
		local workspaceMock = Mock.workspace()
		local runService = Mock.runService()
		local fakeOs, clock = Mock.os()
		local profileService = Mock.profileService()

		local definitionsLoader = t.loader()
		local definitions = definitionsLoader:require("src/ReplicatedStorage/Source/Network/Definitions.luau")
		local remotes = Mock.remotes(definitions)

		local overrides = {
			["src/ReplicatedStorage/Source/Network/Remotes.luau"] = remotes,
			["src/ReplicatedStorage/Source/Packages/ProfileService.luau"] = profileService,
		}
		for path, module in extraOverrides or {} do
			overrides[path] = module
		end

		local loader = t.loader({
			services = {
				Players = players,
				Workspace = workspaceMock,
				RunService = runService,
				CollectionService = Mock.collectionService(),
				__Instance = { new = Mock.instance },
			},
			overrides = overrides,
			globals = { os = fakeOs, RaycastParams = Mock.raycastParams() },
		})

		local env = {
			Players = players,
			Workspace = workspaceMock,
			RunService = runService,
			Clock = clock,
			Remotes = remotes,
			ProfileService = profileService,
			Loader = loader,
		}

		-- Advance both clocks and run Heartbeat-driven loops.
		function env.advance(seconds: number)
			local remaining = seconds
			while remaining > 1e-9 do
				local step = math.min(0.05, remaining)
				clock.Now += step
				workspaceMock.ServerTime += step
				runService.Heartbeat:Fire(step)
				remaining -= step
			end
		end

		return env
	end

	local function loadData(env)
		local DataService = env.Loader:require(SERVICES .. "DataService.luau")
		DataService.Init()
		DataService.Start()
		return DataService
	end

	describe("DataService", function()
		it("loads, replicates and releases profiles", function()
			local env = world()
			local DataService = loadData(env)
			local player = env.Players:__join(101, "Alpha")

			local data = DataService.GetData(player)
			expect(data ~= nil).toBe(true)
			expect(player:GetAttribute("DataLoaded")).toBe(true)
			expect(player:GetAttribute("StaminaCapacity")).toBe(100)
			expect(player:FindFirstChild("leaderstats") ~= nil).toBe(true)
			local snapshot = env.Remotes.StateSnapshot:Last()
			expect(snapshot.Player).toBe(player)
			expect(snapshot.Args[1] ~= data).toBe(true) -- a copy, never the live table

			local added, capped = DataService.AddKP(player, 40)
			expect(added).toBe(40)
			expect(capped).toBe(false)
			expect(player:GetAttribute("UnbankedKP")).toBe(40)
			expect(DataService.BankPower(player)).toBe(40)
			expect(player:GetAttribute("TotalStrength")).toBe(40)
			expect(player:FindFirstChild("leaderstats"):FindFirstChild("Strength").Value).toBe(40)

			env.Players:__leave(player)
			expect(DataService.GetData(player)).toBeNil()
			expect(DataService.Mutate(player, {}, function() end)).toBe(false)
			expect(env.ProfileService.Saved["Player_101"].TotalStrength).toBe(40)
		end)

		it("refuses mutators that yield (atomicity)", function()
			local env = world()
			local DataService = loadData(env)
			local player = env.Players:__join(102, "Beta")
			expect(function()
				DataService.Mutate(player, { "Shards" }, function(data)
					data.Shards += 1
					coroutine.yield()
				end)
			end).toThrow("synchronous")
		end)

		it("kicks players whose profile cannot be loaded", function()
			local env = world()
			loadData(env)
			env.ProfileService.FailNextLoad = true
			local player = env.Players:__join(103, "Gamma")
			expect(player.Kicked ~= nil).toBe(true)
		end)

		it("kicks when another server steals the session", function()
			local env = world()
			loadData(env)
			local player = env.Players:__join(104, "Delta")
			env.ProfileService.Loaded["Player_104"]:Release()
			expect(player.Kicked).toContain("another server")
		end)

		it("serves snapshots through GetSnapshot", function()
			local env = world()
			local DataService = loadData(env)
			local player = env.Players:__join(105, "Echo")
			local snapshot = env.Remotes.GetSnapshot.OnServerInvoke(player)
			expect(type(snapshot)).toBe("table")
			expect(snapshot ~= DataService.GetData(player)).toBe(true)
			expect(snapshot.EquippedRope).toBe("HempCord")
		end)
	end)

	describe("TrainingService", function()
		local GameConfig = t.loader():require("src/ReplicatedStorage/Source/Configuration/GameConfig.luau")
		local interval = GameConfig.Rhythm.BeatInterval

		local fakeWorld = {
			Init = function() end,
			Start = function() end,
			GetObelisks = function()
				return {}
			end,
			GetPedestals = function()
				return {}
			end,
			DistanceToNearestObelisk = function(position: Vector3): number
				return (position - Vector3.new(0, 0, 0)).Magnitude
			end,
		}

		local function setup()
			local env = world({ [SERVICES .. "WorldService.luau"] = fakeWorld })
			local DataService = loadData(env)
			local Training = env.Loader:require(SERVICES .. "TrainingService.luau")
			Training.Init()
			Training.Start()
			local player = env.Players:__join(201, "Jumper")
			local _, _, root = Mock.spawnCharacter(player, Vector3.new(0, 3, -44))
			env.advance(0.2)
			-- Align the synchronised clock to just before a beat.
			local now = env.Workspace.ServerTime
			env.Workspace.ServerTime = math.ceil(now / interval) * interval + interval - 0.01
			return env, DataService, Training, player, root
		end

		-- Physically jumps (so GroundTracker witnesses a takeoff) and reports it.
		local function bounce(env, player, root, pressOffset: number, report: boolean?)
			local beat = math.floor(env.Workspace.ServerTime / interval + 1) * interval
			env.advance(beat - env.Workspace.ServerTime + pressOffset)
			local pressTime = env.Workspace.ServerTime
			root.Position = root.Position + Vector3.new(0, 3, 0)
			env.advance(0.2)
			root.Position = root.Position - Vector3.new(0, 3, 0)
			env.advance(0.35)
			local landTime = env.Workspace.ServerTime
			if report ~= false then
				env.Remotes.ReportBounce.OnServerEvent:Fire(player, pressTime, landTime)
			end
			return env.Remotes.BounceResult:Last()
		end

		it("awards KP and raises the combo for an on-beat bounce", function()
			local env, DataService, _, player, root = setup()
			local result = bounce(env, player, root, 0.02).Args[1]
			expect(result.Accepted).toBe(true)
			expect(result.OnBeat).toBe(true)
			expect(result.Combo).toBe(1.1)
			expect(result.Gained).toBeNear(1.1)
			expect(DataService.GetData(player).UnbankedKP).toBeNear(1.1)
			expect(player:GetAttribute("RhythmCombo")).toBe(1.1)
			expect(player.Character:GetAttribute("RopeState")).toBe("Training")
		end)

		it("resets the combo on an off-beat bounce", function()
			local env, _, _, player, root = setup()
			bounce(env, player, root, 0.02)
			bounce(env, player, root, 0.0)
			-- Press 0.30s before the next beat, landing 0.25s after it: both outside 0.15s.
			local result = bounce(env, player, root, 0.45).Args[1]
			expect(result.Accepted).toBe(true)
			expect(result.OnBeat).toBe(false)
			expect(result.Combo).toBe(1)
		end)

		it("rejects bounces the server never saw happen", function()
			local env, DataService, _, player, _ = setup()
			env.advance(1)
			local now = env.Workspace.ServerTime
			env.Remotes.ReportBounce.OnServerEvent:Fire(player, now - 0.6, now - 0.05)
			local result = env.Remotes.BounceResult:Last().Args[1]
			expect(result.Accepted).toBe(false)
			expect(result.Reason).toBe("Unverified")
			expect(DataService.GetData(player).UnbankedKP).toBe(0)
		end)

		it("rejects stale, future and physically impossible timestamps", function()
			local env, _, _, player, _ = setup()
			local now = env.Workspace.ServerTime
			env.Remotes.ReportBounce.OnServerEvent:Fire(player, now - 10.5, now - 10)
			expect(env.Remotes.BounceResult:Last().Args[1].Reason).toBe("Stale")
			env.Remotes.ReportBounce.OnServerEvent:Fire(player, now + 4, now + 4.5)
			expect(env.Remotes.BounceResult:Last().Args[1].Reason).toBe("Stale")
			env.advance(1)
			env.Remotes.ReportBounce.OnServerEvent:Fire(player, now, now + 0.01)
			expect(env.Remotes.BounceResult:Last().Args[1].Reason).toBe("Timing")
		end)

		it("does not train inside the Colosseum", function()
			local env, _, _, player, root = setup()
			root.Position = GameConfig.World.ColosseumCenter + Vector3.new(0, 3, 0)
			env.advance(0.2)
			local result = bounce(env, player, root, 0.02).Args[1]
			expect(result.Accepted).toBe(false)
			expect(result.Reason).toBe("Zone")
		end)

		it("ignores malformed payloads", function()
			local env, DataService, _, player, _ = setup()
			local before = #env.Remotes.BounceResult.Fired
			env.Remotes.ReportBounce.OnServerEvent:Fire(player, "now", {})
			env.Remotes.ReportBounce.OnServerEvent:Fire(player, 0 / 0, math.huge)
			expect(#env.Remotes.BounceResult.Fired).toBe(before)
			expect(DataService.GetData(player).UnbankedKP).toBe(0)
		end)

		it("stops at Stamina Capacity and drops the stance after a pause", function()
			local env, DataService, _, player, root = setup()
			DataService.Mutate(player, { "UnbankedKP" }, function(data)
				data.UnbankedKP = 99.5
			end)
			local result = bounce(env, player, root, 0.02).Args[1]
			expect(result.Gained).toBeNear(0.5)
			expect(result.Capped).toBe(true)
			expect(DataService.GetData(player).UnbankedKP).toBe(100)

			env.advance(GameConfig.Rhythm.EngagedTimeout + 0.5)
			expect(player:GetAttribute("RhythmCombo")).toBe(1)
			expect(player.Character:GetAttribute("RopeState")).toBe("Idle")
		end)
	end)

	describe("CombatService", function()
		local GameConfig = t.loader():require("src/ReplicatedStorage/Source/Configuration/GameConfig.luau")
		local center = GameConfig.World.ColosseumCenter

		local function setup()
			local mobs = {}
			local damageLog = {}
			local fakeMobs = {
				Init = function() end,
				Start = function() end,
				GetMob = function(mobId: number)
					return mobs[mobId]
				end,
				GetPosition = function(record)
					return record.Position
				end,
				ApplyDamage = function(mobId: number, player, amount: number)
					table.insert(damageLog, { MobId = mobId, Player = player, Amount = amount })
					return amount, false
				end,
			}
			local env = world({ [SERVICES .. "MobService.luau"] = fakeMobs })
			local DataService = loadData(env)
			local Combat = env.Loader:require(SERVICES .. "CombatService.luau")
			local Formulas = env.Loader:require("src/ReplicatedStorage/Source/Shared/Formulas.luau")
			Combat.Init()
			Combat.Start()
			local player = env.Players:__join(301, "Striker")
			local _, _, root = Mock.spawnCharacter(player, center + Vector3.new(0, 3, -40))
			-- Face +Z. (Lune 0.10's CFrame.lookAt mirrors Z, so build the rotation explicitly.)
			root.CFrame = CFrame.new(root.Position) * CFrame.Angles(0, math.pi, 0)
			env.advance(0.2)
			mobs[1] = { Data = GameConfig.Mobs.RomanLegionary, Position = root.Position + Vector3.new(0, 0, 10) }
			mobs[2] = { Data = GameConfig.Mobs.RomanLegionary, Position = root.Position + Vector3.new(0, 0, 30) }
			mobs[3] = { Data = GameConfig.Mobs.RomanLegionary, Position = root.Position + Vector3.new(0, 0, -8) }
			return env, DataService, player, root, damageLog, Formulas
		end

		local function attack(env, player, kind: string, direction: any, targets: any)
			env.Remotes.RequestAttack.OnServerEvent:Fire(player, kind, direction, targets)
		end

		it("applies the Bible damage formula to validated targets", function()
			local env, DataService, player, _, damageLog, Formulas = setup()
			DataService.Mutate(player, { "TotalStrength" }, function(data)
				data.TotalStrength = 1000
			end)
			attack(env, player, "GroundLash", Vector3.new(0, 0, 1), { 1 })
			expect(#damageLog).toBe(1)
			local expected = Formulas.AttackDamage(DataService.GetData(player), "GroundLash")
			expect(damageLog[1].Amount).toBeNear(expected)
			expect(damageLog[1].Amount).toBeNear((1000 ^ 0.65 + 10) * 1, 1e-9)
			expect(env.Remotes.CombatFeedback:Last().Player).toBe(player)
			expect(env.Remotes.AttackFx:Last().Player).toBe("*")
		end)

		it("enforces the attack cooldown", function()
			local env, _, player, _, damageLog = setup()
			attack(env, player, "GroundLash", Vector3.new(0, 0, 1), { 1 })
			attack(env, player, "GroundLash", Vector3.new(0, 0, 1), { 1 })
			expect(#damageLog).toBe(1)
			env.advance(GameConfig.Combat.Attacks.GroundLash.Cooldown)
			attack(env, player, "GroundLash", Vector3.new(0, 0, 1), { 1 })
			expect(#damageLog).toBe(2)
		end)

		it("rejects targets beyond 16 studs and behind the player", function()
			local env, _, player, _, damageLog = setup()
			attack(env, player, "GroundLash", Vector3.new(0, 0, 1), { 2, 3 })
			expect(#damageLog).toBe(0)
		end)

		it("requires being airborne for Aerial Sweep", function()
			local env, _, player, root, damageLog = setup()
			attack(env, player, "AerialSweep", Vector3.new(0, 0, 1), { 1, 3 })
			expect(#damageLog).toBe(0)
			root.Position = root.Position + Vector3.new(0, 4, 0)
			env.advance(0.6)
			attack(env, player, "AerialSweep", Vector3.new(0, 0, 1), { 1, 3 })
			expect(#damageLog).toBe(2) -- radial: hits in front and behind
		end)

		it("rejects aim that does not match the character's facing", function()
			local env, _, player, _, damageLog = setup()
			attack(env, player, "GroundLash", Vector3.new(0, 0, -1), { 1 })
			expect(#damageLog).toBe(0)
		end)

		it("ignores malformed payloads", function()
			local env, _, player, _, damageLog = setup()
			attack(env, player, "Nuke", Vector3.new(0, 0, 1), { 1 })
			attack(env, player, "GroundLash", Vector3.new(0 / 0, 0, 1), { 1 })
			attack(env, player, "GroundLash", Vector3.new(0, 0, 1), { "1" })
			attack(env, player, "GroundLash", Vector3.new(0, 0, 1), { 1, 2, 3, 4, 5, 6, 7, 8, 9 })
			expect(#damageLog).toBe(0)
		end)
	end)
end
