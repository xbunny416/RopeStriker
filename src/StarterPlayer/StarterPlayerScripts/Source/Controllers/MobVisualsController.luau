--!strict
--[[
	MobVisualsController
	--------------------
	Client presentation of the server's world mobs (streaming-aware via tags):

	  * Overhead health bars driven by the Health/MaxHealth attributes.
	  * Mob_Telegraph_Slash (Bible §4.2/§4.3): when a mob starts a wind-up the red ground
	    decal (cone or circle, Modules/Telegraph) fills over 0.8s and flashes on impact;
	    the procedural rig raises its weapon arm and slams it down at the strike.
	  * Confirmed hits from CombatFeedback: floating damage numbers + spatial Whip_Crack.
	  * Death: the rig fades out with a shard burst.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Source = ReplicatedStorage.Source
local GameConfig = require(Source.Configuration.GameConfig)
local NumberFormat = require(Source.Shared.NumberFormat)
local Tags = require(Source.Shared.Tags)
local Trove = require(Source.Shared.Trove)
local Remotes = require(Source.Network.Remotes)

local Modules = script.Parent.Parent.Modules
local SoundPlayer = require(Modules.SoundPlayer)
local Telegraph = require(Modules.Telegraph)

type HitReport = Remotes.HitReport

type MobView = {
	Model: Model,
	Trove: Trove.Trove,
	Fill: Frame?,
	Billboard: BillboardGui?,
	Decal: Telegraph.Decal?,
	TelegraphStart: number,
	TelegraphEnd: number,
	Flashed: boolean,
	LastStrikeAt: number,
	Shoulder: Motor6D?,
	Dying: boolean,
}

local STRIKE_POSE_SECONDS = 0.25
local DECAL_LINGER = 0.2

local MobVisualsController = {}

local views: { [Model]: MobView } = {}
local effectsFolder: Folder -- local world-space parts (telegraph decals)
local billboardRoot: Instance -- BillboardGuis live in PlayerGui with an Adornee

local function numberAttribute(instance: Instance, name: string, default: number): number
	local value = instance:GetAttribute(name)
	return if type(value) == "number" then value else default
end

local function updateHealth(view: MobView)
	local fill = view.Fill
	if fill == nil then
		return
	end
	local health = numberAttribute(view.Model, "Health", 1)
	local maxHealth = math.max(1, numberAttribute(view.Model, "MaxHealth", 1))
	local fraction = math.clamp(health / maxHealth, 0, 1)
	fill.Size = UDim2.fromScale(fraction, 1)
	fill.BackgroundColor3 = if fraction > 0.5
		then Color3.fromRGB(96, 220, 120)
		elseif fraction > 0.25 then Color3.fromRGB(255, 196, 46)
		else Color3.fromRGB(255, 72, 72)
end

local function buildHealthBar(view: MobView)
	local model = view.Model
	local root = model.PrimaryPart
	local anchor: Instance? = if root then root:FindFirstChild("Overhead") else nil
	local adornee = anchor or root
	if adornee == nil then
		return
	end
	local isBoss = model:GetAttribute("IsBoss") == true
	local gui = Instance.new("BillboardGui")
	gui.Name = "MobHealth"
	gui.Adornee = adornee
	gui.Size = UDim2.fromScale(if isBoss then 9 else 5, if isBoss then 1.6 else 1.1)
	gui.StudsOffset = Vector3.new(0, 0.6, 0)
	gui.MaxDistance = GameConfig.UI.MobBarRange
	gui.LightInfluence = 0
	gui.ResetOnSpawn = false

	local name = Instance.new("TextLabel")
	name.AnchorPoint = Vector2.new(0.5, 0.5)
	name.Position = UDim2.fromScale(0.5, 0.25)
	name.Size = UDim2.fromScale(1, 0.5)
	name.BackgroundTransparency = 1
	name.Font = Enum.Font.FredokaOne
	name.TextScaled = true
	name.TextColor3 = if isBoss then Color3.fromRGB(255, 90, 90) else Color3.new(1, 1, 1)
	name.TextStrokeTransparency = 0.3
	local displayName = model:GetAttribute("DisplayName")
	name.Text = if type(displayName) == "string" then displayName else model.Name
	name.Parent = gui

	local back = Instance.new("Frame")
	back.AnchorPoint = Vector2.new(0.5, 0.5)
	back.Position = UDim2.fromScale(0.5, 0.75)
	back.Size = UDim2.fromScale(0.9, 0.32)
	back.BackgroundColor3 = Color3.fromRGB(20, 20, 26)
	back.BorderSizePixel = 0
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = back
	back.Parent = gui

	local fill = Instance.new("Frame")
	fill.Size = UDim2.fromScale(1, 1)
	fill.BorderSizePixel = 0
	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = UDim.new(0.5, 0)
	fillCorner.Parent = fill
	fill.Parent = back

	gui.Parent = billboardRoot
	view.Trove:Add(gui)
	view.Billboard = gui
	view.Fill = fill
	updateHealth(view)
end

local function startTelegraph(view: MobView)
	local model = view.Model
	local start = model:GetAttribute("TelegraphStart")
	local finish = model:GetAttribute("TelegraphEnd")
	local origin = model:GetAttribute("TelegraphOrigin")
	local direction = model:GetAttribute("TelegraphDirection")
	local shape = model:GetAttribute("TelegraphShape")
	local range = model:GetAttribute("TelegraphRange")
	local angle = model:GetAttribute("TelegraphAngle")
	if
		type(start) ~= "number"
		or type(finish) ~= "number"
		or typeof(origin) ~= "Vector3"
		or typeof(direction) ~= "Vector3"
		or type(shape) ~= "string"
		or type(range) ~= "number"
	then
		return
	end
	local previous = view.Decal
	if previous then
		previous:Destroy()
	end
	view.Decal = Telegraph.Create(
		effectsFolder,
		shape,
		origin :: Vector3,
		direction :: Vector3,
		range,
		if type(angle) == "number" then angle else 90
	)
	view.TelegraphStart = start
	view.TelegraphEnd = finish
	view.Flashed = false
end

local function playDeath(view: MobView)
	if view.Dying then
		return
	end
	view.Dying = true
	local decal = view.Decal
	if decal then
		decal:Destroy()
		view.Decal = nil
	end
	local info = TweenInfo.new(1.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	for _, descendant in view.Model:GetDescendants() do
		if descendant:IsA("BasePart") then
			TweenService:Create(descendant, info, { LocalTransparencyModifier = 1 }):Play()
		end
	end
	local root = view.Model.PrimaryPart
	if root then
		local burst = Instance.new("ParticleEmitter")
		burst.Color = ColorSequence.new(GameConfig.UI.Palette.Shard)
		burst.LightEmission = 1
		burst.Speed = NumberRange.new(6, 14)
		burst.Lifetime = NumberRange.new(0.4, 0.9)
		burst.SpreadAngle = Vector2.new(180, 180)
		burst.Rate = 0
		burst.Parent = root
		burst:Emit(28)
		view.Trove:Add(burst)
	end
end

local function track(instance: Instance)
	if not instance:IsA("Model") or views[instance] then
		return
	end
	local model = instance
	local shoulder: Motor6D? = nil
	local found = model:FindFirstChild("WeaponShoulder", true)
	if found and found:IsA("Motor6D") then
		shoulder = found
	end
	local view: MobView = {
		Model = model,
		Trove = Trove.new(),
		Fill = nil,
		Billboard = nil,
		Decal = nil,
		TelegraphStart = 0,
		TelegraphEnd = 0,
		Flashed = true,
		LastStrikeAt = numberAttribute(model, "LastStrikeAt", 0),
		Shoulder = shoulder,
		Dying = false,
	}
	views[model] = view
	buildHealthBar(view)

	view.Trove:Connect(model:GetAttributeChangedSignal("Health"), function()
		updateHealth(view)
	end)
	view.Trove:Connect(model:GetAttributeChangedSignal("TelegraphStart"), function()
		startTelegraph(view)
	end)
	view.Trove:Connect(model:GetAttributeChangedSignal("LastStrikeAt"), function()
		view.LastStrikeAt = numberAttribute(model, "LastStrikeAt", 0)
	end)
	view.Trove:Connect(model:GetAttributeChangedSignal("State"), function()
		if model:GetAttribute("State") == "Dead" then
			playDeath(view)
		end
	end)
	if model:GetAttribute("State") == "Dead" then
		playDeath(view)
	elseif model:GetAttribute("State") == "Telegraph" then
		startTelegraph(view)
	end
end

local function untrack(instance: Instance)
	local model = instance :: Model
	local view = views[model]
	if view == nil then
		return
	end
	views[model] = nil
	local decal = view.Decal
	if decal then
		decal:Destroy()
	end
	view.Trove:Clean()
end

local function showDamage(hit: HitReport)
	local anchor = Instance.new("Attachment")
	anchor.Position = hit.Position + Vector3.new((math.random() - 0.5) * 2, 4, (math.random() - 0.5) * 2)
	anchor.Parent = workspace.Terrain

	local gui = Instance.new("BillboardGui")
	gui.Adornee = anchor
	gui.Size = UDim2.fromScale(if hit.Killed then 6 else 4, if hit.Killed then 2 else 1.4)
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.Text = (if hit.Killed then "KO! " else "") .. NumberFormat.Abbreviate(hit.Damage)
	label.TextColor3 = if hit.Killed then GameConfig.UI.Palette.Accent else Color3.new(1, 1, 1)
	label.TextStrokeTransparency = 0.2
	label.Parent = gui
	gui.Parent = billboardRoot

	local info = TweenInfo.new(0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(gui, info, { StudsOffset = Vector3.new(0, 3, 0) }):Play()
	TweenService:Create(label, info, { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
	task.delay(0.85, function()
		gui:Destroy()
		anchor:Destroy()
	end)
end

function MobVisualsController.Init()
	local folder = Instance.new("Folder")
	folder.Name = "ChronoLocalEffects"
	folder.Parent = workspace
	effectsFolder = folder
	billboardRoot = Players.LocalPlayer:WaitForChild("PlayerGui")

	Remotes.CombatFeedback.OnClientEvent:Connect(function(hits: { HitReport })
		if type(hits) ~= "table" then
			return
		end
		for index, hit in hits do
			if typeof(hit.Position) == "Vector3" and type(hit.Damage) == "number" then
				showDamage(hit)
				if index == 1 then
					SoundPlayer.PlayAt("WhipCrack", hit.Position)
				end
			end
		end
	end)
end

function MobVisualsController.Start()
	for _, instance in CollectionService:GetTagged(Tags.ChronoMob) do
		track(instance)
	end
	CollectionService:GetInstanceAddedSignal(Tags.ChronoMob):Connect(track)
	CollectionService:GetInstanceRemovedSignal(Tags.ChronoMob):Connect(untrack)

	-- Telegraph decals fill up over the wind-up and flash on impact.
	RunService.RenderStepped:Connect(function()
		local serverNow = workspace:GetServerTimeNow()
		for _, view in views do
			local decal = view.Decal
			if decal == nil then
				continue
			end
			local duration = math.max(0.05, view.TelegraphEnd - view.TelegraphStart)
			local progress = (serverNow - view.TelegraphStart) / duration
			if progress < 1 then
				decal:SetProgress(progress)
			elseif not view.Flashed then
				view.Flashed = true
				decal:SetProgress(1)
				decal:Flash()
			elseif serverNow > view.TelegraphEnd + DECAL_LINGER then
				decal:Destroy()
				view.Decal = nil
			end
		end
	end)

	-- Procedural weapon wind-up / strike for rigs without an authored animation.
	if GameConfig.Animations.MobTelegraphSlash == "" then
		RunService.PreSimulation:Connect(function()
			local serverNow = workspace:GetServerTimeNow()
			for _, view in views do
				local shoulder = view.Shoulder
				if shoulder == nil or shoulder.Parent == nil or view.Dying then
					continue
				end
				local sinceStrike = serverNow - view.LastStrikeAt
				if view.Decal and serverNow < view.TelegraphEnd then
					local duration = math.max(0.05, view.TelegraphEnd - view.TelegraphStart)
					local raise = math.clamp((serverNow - view.TelegraphStart) / duration, 0, 1)
					shoulder.Transform = CFrame.Angles(2.6 * raise, 0, 0.25 * raise)
				elseif sinceStrike >= 0 and sinceStrike < STRIKE_POSE_SECONDS then
					local follow = sinceStrike / STRIKE_POSE_SECONDS
					shoulder.Transform = CFrame.Angles(-0.9 * (1 - follow), 0, 0)
				end
			end
		end)
	end
end

return MobVisualsController
