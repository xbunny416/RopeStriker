--!strict
--[[
	UIController
	============
	Cross-platform HUD (Bible §5). Every element is placed with AnchorPoint (0.5, 0.5)
	and Scale-only UDim2 values, keeps its shape with UIAspectRatioConstraint, and sits
	inside the device safe area (ScreenInsets) so notches and the Roblox top bar never
	cover it.

	  Bottom-right   oversized circular Action Button: "JUMP" in Training, "SWING" in
	                 Combat (swaps automatically by zone; bigger on touch devices).
	  Bottom-centre  segmented Kinetic Power gauge: CurrentKP / Stamina Capacity.
	  Top-centre     boss health bar, only within 60 studs of a boss.
	  Left edge      collapsible drawer: Rebirth, Shop, Pets.
	  Top-left       Strength / Shards / Rebirth pills.  Top-right: era + mode chip.

	Gamepad: R2 = Action, Y = toggle drawer, B = close panel; panels set the selection
	so they are fully navigable with the D-pad.
]]

local CollectionService = game:GetService("CollectionService")
local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Source = ReplicatedStorage.Source
local GameConfig = require(Source.Configuration.GameConfig)
local NumberFormat = require(Source.Shared.NumberFormat)
local Tags = require(Source.Shared.Tags)
local Remotes = require(Source.Network.Remotes)

local Controllers = script.Parent
local RopeController = require(Controllers.RopeController)

local Modules = script.Parent.Parent.Modules
local ClientState = require(Modules.ClientState)
local SoundPlayer = require(Modules.SoundPlayer)

local UI = script.Parent.Parent.UI
local PanelFrame = require(UI.PanelFrame)
local PetsPanel = require(UI.PetsPanel)
local RebirthPanel = require(UI.RebirthPanel)
local ShopPanel = require(UI.ShopPanel)
local Toasts = require(UI.Toasts)
local UIKit = require(UI.UIKit)

type PlayerMode = GameConfig.PlayerMode
type BounceResult = Remotes.BounceResult
type RewardReport = Remotes.RewardReport
type PetRecord = GameConfig.PetRecord

local GAUGE_SEGMENTS = 10
local BOSS_SCAN_INTERVAL = 0.1
local ROMAN = { "I", "II", "III", "IV", "V", "VI" }
local ACTION_DRAWER = "ChronoDrawer"
local ACTION_CLOSE = "ChronoClosePanel"

local Palette = UIKit.Palette

local UIController = {}

local player = Players.LocalPlayer
local screen: ScreenGui
local toasts: Toasts.Toasts
local panels: { [string]: PanelFrame.Panel } = {}
local openPanel: PanelFrame.Panel? = nil

-- HUD references
local strengthLabel: TextLabel
local shardsLabel: TextLabel
local rebirthLabel: TextLabel
local eraLabel: TextLabel
local modeLabel: TextLabel
local gaugeSegments: { Frame } = {}
local gaugeLabel: TextLabel
local gaugeHint: TextLabel
local gaugeFrame: Frame
local actionButton: TextButton
local actionHint: TextLabel
local drawer: Frame
local drawerToggle: TextButton
local drawerOpen = true
local bossFrame: Frame
local bossName: TextLabel
local bossFill: Frame
local bossHealthText: TextLabel
local hatchPopup: Frame
local hatchTitle: TextLabel
local hatchDetail: TextLabel
local celebration: TextLabel

---------------------------------------------------------------------------------------
-- Platform
---------------------------------------------------------------------------------------

local function isTouch(): boolean
	return UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
end

local function isGamepad(): boolean
	local last = UserInputService:GetLastInputType()
	return last.Name:sub(1, 7) == "Gamepad"
end

---------------------------------------------------------------------------------------
-- HUD construction
---------------------------------------------------------------------------------------

local function statPill(name: string, position: UDim2, color: Color3, icon: string): TextLabel
	local pill: Frame = UIKit.new("Frame", {
		Name = name,
		Position = position,
		Size = UDim2.fromScale(0.2, 0.06),
		BackgroundColor3 = Palette.Background,
		BackgroundTransparency = 0.2,
		Parent = screen,
	}, { UIKit.Corner(0.5), UIKit.Stroke(color, 2, 0.2), UIKit.Aspect(4.4) })
	UIKit.new("TextLabel", {
		Name = "Icon",
		Text = icon,
		Position = UDim2.fromScale(0.11, 0.5),
		Size = UDim2.fromScale(0.16, 0.8),
		Parent = pill,
	}, { UIKit.Aspect(1) })
	local value: TextLabel = UIKit.new("TextLabel", {
		Name = "Value",
		Text = "0",
		Position = UDim2.fromScale(0.58, 0.5),
		Size = UDim2.fromScale(0.76, 0.7),
		TextColor3 = color,
		Font = UIKit.HeadingFont,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = pill,
	}, { UIKit.TextLimit(30), UIKit.TextStroke(Color3.new(0, 0, 0), 1.5) })
	return value
end

local function buildStats()
	strengthLabel = statPill("Strength", UDim2.fromScale(0.12, 0.07), Palette.Kinetic, "💪")
	shardsLabel = statPill("Shards", UDim2.fromScale(0.12, 0.14), Palette.Shard, "💎")
	rebirthLabel = statPill("Rebirths", UDim2.fromScale(0.12, 0.21), Color3.fromRGB(178, 120, 255), "⏳")

	local chip: Frame = UIKit.new("Frame", {
		Name = "EraChip",
		Position = UDim2.fromScale(0.87, 0.08),
		Size = UDim2.fromScale(0.24, 0.09),
		BackgroundColor3 = Palette.Background,
		BackgroundTransparency = 0.2,
		Parent = screen,
	}, { UIKit.Corner(0.3), UIKit.Stroke(Palette.Accent, 2, 0.2), UIKit.Aspect(3.6) })
	eraLabel = UIKit.new("TextLabel", {
		Name = "Era",
		Text = "ERA I · ANCIENT ROME",
		Position = UDim2.fromScale(0.5, 0.33),
		Size = UDim2.fromScale(0.92, 0.45),
		Font = UIKit.HeadingFont,
		TextColor3 = Palette.Accent,
		Parent = chip,
	}, { UIKit.TextLimit(22) })
	modeLabel = UIKit.new("TextLabel", {
		Name = "Mode",
		Text = "TRAINING",
		Position = UDim2.fromScale(0.5, 0.74),
		Size = UDim2.fromScale(0.9, 0.34),
		TextColor3 = Palette.TextDim,
		Parent = chip,
	}, { UIKit.TextLimit(16) })
end

local function buildGauge()
	gaugeFrame = UIKit.new("Frame", {
		Name = "KineticGauge",
		Position = UDim2.fromScale(0.5, 0.93),
		Size = UDim2.fromScale(0.44, 0.055),
		BackgroundColor3 = Palette.Background,
		BackgroundTransparency = 0.15,
		Parent = screen,
	}, { UIKit.Corner(0.5), UIKit.Stroke(Palette.Kinetic, 2, 0.1), UIKit.Aspect(10) })

	local track: Frame = UIKit.new("Frame", {
		Name = "Segments",
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.95, 0.62),
		BackgroundTransparency = 1,
		Parent = gaugeFrame,
	})
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.Padding = UDim.new(0.008, 0)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = track

	for index = 1, GAUGE_SEGMENTS do
		local segment: Frame = UIKit.new("Frame", {
			Name = `Segment{index}`,
			Size = UDim2.fromScale(0.092, 1),
			BackgroundColor3 = Palette.PanelLight,
			LayoutOrder = index,
			Parent = track,
		}, { UIKit.Corner(0.35) })
		local fill: Frame = UIKit.new("Frame", {
			Name = "Fill",
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.fromScale(0, 0.5),
			Size = UDim2.fromScale(0, 1),
			BackgroundColor3 = Palette.Kinetic,
			Parent = segment,
		}, { UIKit.Corner(0.35) })
		gaugeSegments[index] = fill
	end

	gaugeLabel = UIKit.new("TextLabel", {
		Name = "KPLabel",
		Text = "KINETIC POWER 0 / 100",
		Position = UDim2.fromScale(0.5, 0.875),
		Size = UDim2.fromScale(0.4, 0.035),
		Font = UIKit.HeadingFont,
		TextColor3 = Palette.Kinetic,
		Parent = screen,
	}, { UIKit.TextLimit(24), UIKit.TextStroke(Color3.new(0, 0, 0), 1.5) })
	gaugeHint = UIKit.new("TextLabel", {
		Name = "BankHint",
		Text = "STAMINA FULL - BANK AT THE EPOCH OBELISK",
		Position = UDim2.fromScale(0.5, 0.835),
		Size = UDim2.fromScale(0.46, 0.035),
		Font = UIKit.HeadingFont,
		TextColor3 = Palette.Accent,
		Visible = false,
		Parent = screen,
	}, { UIKit.TextLimit(22), UIKit.TextStroke(Color3.new(0, 0, 0), 1.5) })
end

local function buildActionButton()
	actionButton = UIKit.new("TextButton", {
		Name = "ActionButton",
		Text = "JUMP",
		Position = UDim2.fromScale(0.86, 0.72),
		Size = UDim2.fromScale(0.2, 0.2),
		SizeConstraint = Enum.SizeConstraint.RelativeYY,
		BackgroundTransparency = 0,
		BackgroundColor3 = Palette.Accent,
		AutoButtonColor = false,
		Font = UIKit.HeadingFont,
		Selectable = false,
		Parent = screen,
	}, {
		UIKit.Corner(0.5),
		UIKit.Aspect(1),
		UIKit.Stroke(Color3.new(1, 1, 1), 4, 0.1),
		UIKit.TextLimit(44),
		UIKit.Padding(0.2),
		UIKit.TextStroke(Color3.new(0, 0, 0), 2),
	})
	actionButton.Activated:Connect(function()
		UIKit.Pop(actionButton, 0.85)
		RopeController.PerformAction()
	end)

	actionHint = UIKit.new("TextLabel", {
		Name = "ActionHint",
		Text = "",
		Position = UDim2.fromScale(0.86, 0.85),
		Size = UDim2.fromScale(0.14, 0.03),
		TextColor3 = Palette.TextDim,
		Parent = screen,
	}, { UIKit.TextLimit(16), UIKit.TextStroke(Color3.new(0, 0, 0), 1) })
end

local function buildBossBar()
	bossFrame = UIKit.new("Frame", {
		Name = "BossBar",
		Position = UDim2.fromScale(0.5, 0.085),
		Size = UDim2.fromScale(0.46, 0.05),
		BackgroundColor3 = Palette.Background,
		BackgroundTransparency = 0.1,
		Visible = false,
		Parent = screen,
	}, { UIKit.Corner(0.4), UIKit.Stroke(Palette.Bad, 3, 0), UIKit.Aspect(12) })
	bossFill = UIKit.new("Frame", {
		Name = "Fill",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.fromScale(0.01, 0.5),
		Size = UDim2.fromScale(0.98, 0.7),
		BackgroundColor3 = Palette.Bad,
		Parent = bossFrame,
	}, { UIKit.Corner(0.4), UIKit.Gradient(Color3.fromRGB(255, 120, 100), Color3.fromRGB(180, 20, 20)) })
	bossHealthText = UIKit.new("TextLabel", {
		Name = "Health",
		Text = "",
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.5, 0.7),
		Font = UIKit.HeadingFont,
		ZIndex = 3,
		Parent = bossFrame,
	}, { UIKit.TextLimit(20), UIKit.TextStroke(Color3.new(0, 0, 0), 1.5) })
	bossName = UIKit.new("TextLabel", {
		Name = "BossName",
		Text = "",
		Position = UDim2.fromScale(0.5, -0.55),
		Size = UDim2.fromScale(0.7, 0.8),
		Font = UIKit.HeadingFont,
		TextColor3 = Palette.Bad,
		Parent = bossFrame,
	}, { UIKit.TextLimit(26), UIKit.TextStroke(Color3.new(0, 0, 0), 2) })
end

local function buildPopups()
	hatchPopup = UIKit.new("Frame", {
		Name = "HatchPopup",
		Position = UDim2.fromScale(0.5, 0.42),
		Size = UDim2.fromScale(0.36, 0.2),
		BackgroundColor3 = Palette.Background,
		BackgroundTransparency = 0.1,
		Visible = false,
		ZIndex = 20,
		Parent = screen,
	}, { UIKit.Corner(0.15), UIKit.Stroke(Palette.Accent, 4, 0), UIKit.Aspect(3) })
	hatchTitle = UIKit.new("TextLabel", {
		Name = "Title",
		Text = "",
		Position = UDim2.fromScale(0.5, 0.36),
		Size = UDim2.fromScale(0.9, 0.42),
		Font = UIKit.HeadingFont,
		ZIndex = 21,
		Parent = hatchPopup,
	}, { UIKit.TextLimit(40), UIKit.TextStroke(Color3.new(0, 0, 0), 2) })
	hatchDetail = UIKit.new("TextLabel", {
		Name = "Detail",
		Text = "",
		Position = UDim2.fromScale(0.5, 0.75),
		Size = UDim2.fromScale(0.9, 0.28),
		TextColor3 = Palette.TextDim,
		ZIndex = 21,
		Parent = hatchPopup,
	}, { UIKit.TextLimit(24) })

	celebration = UIKit.new("TextLabel", {
		Name = "Celebration",
		Text = "",
		Position = UDim2.fromScale(0.5, 0.4),
		Size = UDim2.fromScale(0.8, 0.14),
		Font = UIKit.HeadingFont,
		TextColor3 = Color3.fromRGB(205, 160, 255),
		TextTransparency = 1,
		ZIndex = 30,
		Parent = screen,
	}, { UIKit.TextLimit(72), UIKit.TextStroke(Color3.fromRGB(40, 0, 70), 3) })
end

---------------------------------------------------------------------------------------
-- Panels & drawer
---------------------------------------------------------------------------------------

function UIController.ClosePanel()
	local current = openPanel
	if current == nil then
		return
	end
	openPanel = nil
	current.Frame.Visible = false
	ContextActionService:UnbindAction(ACTION_CLOSE)
	if GuiService.SelectedObject and GuiService.SelectedObject:IsDescendantOf(current.Frame) then
		GuiService.SelectedObject = nil
	end
end

function UIController.OpenPanel(name: string)
	local panel = panels[name]
	if panel == nil then
		return
	end
	if openPanel == panel then
		UIController.ClosePanel()
		return
	end
	UIController.ClosePanel()
	openPanel = panel
	panel.Refresh()
	panel.Frame.Visible = true
	UIKit.Pop(panel.Frame, 0.92)
	ContextActionService:BindAction(
		ACTION_CLOSE,
		function(_: string, state: Enum.UserInputState): Enum.ContextActionResult
			if state == Enum.UserInputState.Begin then
				UIController.ClosePanel()
			end
			return Enum.ContextActionResult.Sink
		end,
		false,
		Enum.KeyCode.ButtonB
	)
	if isGamepad() then
		GuiService.SelectedObject = panel.DefaultSelection()
	end
end

local function setDrawerOpen(value: boolean)
	drawerOpen = value
	UIKit.Tween(drawer, 0.25, { Position = UDim2.fromScale(if value then 0.055 else -0.05, 0.5) })
	drawerToggle.Text = if value then "<" else ">"
end

local function buildDrawer()
	drawer = UIKit.new("Frame", {
		Name = "Drawer",
		Position = UDim2.fromScale(0.055, 0.5),
		Size = UDim2.fromScale(0.11, 0.4),
		SizeConstraint = Enum.SizeConstraint.RelativeYY,
		BackgroundColor3 = Palette.Background,
		BackgroundTransparency = 0.25,
		Parent = screen,
	}, { UIKit.Corner(0.25), UIKit.Stroke(Palette.Accent, 2, 0.3), UIKit.Aspect(0.32) })

	local entries = {
		{ Name = "Rebirth", Icon = "⏳", Color = Color3.fromRGB(178, 120, 255) },
		{ Name = "Shop", Icon = "⚒️", Color = Palette.Accent },
		{ Name = "Pets", Icon = "🐾", Color = Palette.Shard },
	}
	for index, entry in entries do
		local button: TextButton = UIKit.new("TextButton", {
			Name = entry.Name,
			Text = entry.Icon,
			Position = UDim2.fromScale(0.5, 0.18 + (index - 1) * 0.32),
			Size = UDim2.fromScale(0.78, 0.25),
			BackgroundTransparency = 0,
			BackgroundColor3 = Palette.PanelLight,
			AutoButtonColor = false,
			Selectable = true,
			Parent = drawer,
		}, { UIKit.Corner(0.3), UIKit.Stroke(entry.Color, 2), UIKit.Aspect(1), UIKit.Padding(0.18) })
		UIKit.new("TextLabel", {
			Name = "Caption",
			Text = string.upper(entry.Name),
			Position = UDim2.fromScale(0.5, 1.12),
			Size = UDim2.fromScale(1.3, 0.3),
			Font = UIKit.HeadingFont,
			TextColor3 = entry.Color,
			Parent = button,
		}, { UIKit.TextLimit(14), UIKit.TextStroke(Color3.new(0, 0, 0), 1) })
		button.Activated:Connect(function()
			UIKit.Pop(button)
			UIController.OpenPanel(entry.Name)
		end)
	end

	drawerToggle = UIKit.new("TextButton", {
		Name = "Toggle",
		Text = "<",
		Position = UDim2.fromScale(1.18, 0.5),
		Size = UDim2.fromScale(0.36, 0.14),
		BackgroundTransparency = 0,
		BackgroundColor3 = Palette.Background,
		AutoButtonColor = false,
		Font = UIKit.HeadingFont,
		TextColor3 = Palette.Accent,
		Parent = drawer,
	}, { UIKit.Corner(0.4), UIKit.Stroke(Palette.Accent, 2, 0.3) })
	drawerToggle.Activated:Connect(function()
		setDrawerOpen(not drawerOpen)
	end)
end

---------------------------------------------------------------------------------------
-- Live updates
---------------------------------------------------------------------------------------

local function updateStats()
	local data = ClientState.Get()
	strengthLabel.Text =
		NumberFormat.Abbreviate(ClientState.Number("TotalStrength", if data then data.TotalStrength else 0))
	shardsLabel.Text = NumberFormat.Abbreviate(ClientState.Number("Shards", if data then data.Shards else 0))
	local rebirths = ClientState.Number("RebirthCount", if data then data.RebirthCount else 0)
	local tokens = ClientState.Number("RebirthTokens", if data then data.RebirthTokens else 0)
	rebirthLabel.Text = if tokens > 0 then `{rebirths}  (+{tokens} tk)` else tostring(rebirths)
end

local function updateGauge()
	local current = ClientState.Number("UnbankedKP", 0)
	local capacity = math.max(1, ClientState.Capacity())
	local fraction = math.clamp(current / capacity, 0, 1)
	for index, fill in gaugeSegments do
		local segmentFill = math.clamp(fraction * GAUGE_SEGMENTS - (index - 1), 0, 1)
		fill.Size = UDim2.fromScale(segmentFill, 1)
		fill.BackgroundColor3 = if fraction >= 1 then Palette.Accent else Palette.Kinetic
	end
	gaugeLabel.Text = `KINETIC POWER  {NumberFormat.Abbreviate(current)} / {NumberFormat.Abbreviate(capacity)}`
	gaugeHint.Visible = fraction >= 1
end

local function updateEra()
	local eraIndex = math.clamp(ClientState.Number("Era", 1), 1, #GameConfig.Eras)
	local era = GameConfig.Eras[eraIndex]
	eraLabel.Text = `ERA {ROMAN[eraIndex] or tostring(eraIndex)} · {string.upper(era.DisplayName)}`
end

local function updateActionButton(mode: PlayerMode)
	local combat = mode == "Combat"
	actionButton.Text = if combat then "SWING" else "JUMP"
	actionButton.BackgroundColor3 = if combat then Palette.Bad else Palette.Accent
	modeLabel.Text = if combat then "COMBAT - SWING YOUR ROPE" else "TRAINING - JUMP ON THE BEAT"
	modeLabel.TextColor3 = if combat then Palette.Bad else Palette.TextDim

	-- Oversized on touch screens; compact with a key hint elsewhere.
	local touch = isTouch()
	local size = if touch then 0.24 else 0.15
	actionButton.Size = UDim2.fromScale(size, size)
	actionButton.Position = if touch then UDim2.fromScale(0.8, 0.7) else UDim2.fromScale(0.88, 0.76)
	actionHint.Position = UDim2.fromScale(actionButton.Position.X.Scale, actionButton.Position.Y.Scale + size * 0.62)
	if touch then
		actionHint.Text = ""
	elseif isGamepad() then
		actionHint.Text = if combat then "R2" else "A / R2"
	else
		actionHint.Text = if combat then "CLICK" else "SPACE"
	end
end

local function popKP(text: string, color: Color3)
	local label: TextLabel = UIKit.new("TextLabel", {
		Name = "KPPop",
		Text = text,
		Position = UDim2.fromScale(0.5 + (math.random() - 0.5) * 0.12, 0.88),
		Size = UDim2.fromScale(0.16, 0.045),
		Font = UIKit.HeadingFont,
		TextColor3 = color,
		Parent = screen,
	}, { UIKit.TextLimit(30), UIKit.TextStroke(Color3.new(0, 0, 0), 2) })
	UIKit.Tween(label, 0.7, { Position = label.Position - UDim2.fromScale(0, 0.09), TextTransparency = 1 })
	task.delay(0.75, function()
		label:Destroy()
	end)
end

local function nearestBoss(): Model?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root == nil or not root:IsA("BasePart") then
		return nil
	end
	local best: Model? = nil
	local bestDistance = GameConfig.UI.BossBarRange
	for _, instance in CollectionService:GetTagged(Tags.ChronoMob) do
		if
			instance:IsA("Model")
			and instance:GetAttribute("IsBoss") == true
			and instance:GetAttribute("State") ~= "Dead"
		then
			local distance = (instance:GetPivot().Position - root.Position).Magnitude
			if distance <= bestDistance then
				bestDistance = distance
				best = instance
			end
		end
	end
	return best
end

local function updateBossBar()
	local boss = nearestBoss()
	if boss == nil then
		bossFrame.Visible = false
		return
	end
	local health = boss:GetAttribute("Health")
	local maxHealth = boss:GetAttribute("MaxHealth")
	local name = boss:GetAttribute("DisplayName")
	if type(health) ~= "number" or type(maxHealth) ~= "number" or maxHealth <= 0 then
		bossFrame.Visible = false
		return
	end
	bossFrame.Visible = true
	bossName.Text = if type(name) == "string" then string.upper(name) else "BOSS"
	bossFill.Size = UDim2.fromScale(0.98 * math.clamp(health / maxHealth, 0, 1), 0.7)
	bossHealthText.Text = `{NumberFormat.Abbreviate(health)} / {NumberFormat.Abbreviate(maxHealth)}`
end

local function showHatch(eggId: string, record: PetRecord)
	local pet = GameConfig.Pets[record.Id]
	local egg = GameConfig.Eggs[eggId]
	if pet == nil then
		return
	end
	local color = GameConfig.Pet.RarityColors[pet.Rarity]
	hatchTitle.Text = `{pet.DisplayName}!`
	hatchTitle.TextColor3 = color
	hatchDetail.Text = `{string.upper(pet.Rarity)}  ·  {NumberFormat.Multiplier(pet.Multiplier)}  ·  from {if egg
		then egg.DisplayName
		else "an egg"}`
	local stroke = hatchPopup:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Color = color
	end
	hatchPopup.Visible = true
	UIKit.Pop(hatchPopup, 0.6)
	SoundPlayer.Play("Hatch")
	task.delay(2.6, function()
		hatchPopup.Visible = false
	end)
end

local function celebrateRebirth(count: number)
	celebration.Text = `TEMPORAL PARADOX #{count}`
	celebration.TextTransparency = 0
	UIKit.Pop(celebration, 0.4)
	SoundPlayer.Play("ObeliskBank", nil, 0.6)
	task.delay(1.8, function()
		UIKit.Tween(celebration, 0.6, { TextTransparency = 1 })
	end)
	toasts:Push(
		`Base stats now {NumberFormat.Multiplier(GameConfig.Rebirth.MultiplierBase ^ count)}!`,
		Color3.fromRGB(205, 160, 255)
	)
end

local NOTIFY_COLORS: { [string]: Color3 } = {
	Error = Palette.Bad,
	Info = Palette.Text,
	Title = Palette.Accent,
	Portal = Palette.Kinetic,
}

---------------------------------------------------------------------------------------
-- Lifecycle
---------------------------------------------------------------------------------------

function UIController.Toast(text: string, color: Color3?)
	toasts:Push(text, color)
end

function UIController.Init()
	local playerGui = player:WaitForChild("PlayerGui") :: PlayerGui
	screen = Instance.new("ScreenGui")
	screen.Name = "ChronoHUD"
	screen.ResetOnSpawn = false
	screen.IgnoreGuiInset = false
	screen.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
	screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screen.Parent = playerGui

	buildStats()
	buildGauge()
	buildActionButton()
	buildBossBar()
	buildDrawer()
	buildPopups()
	toasts = Toasts.new(screen)

	local context: PanelFrame.Context = {
		Toast = function(text: string, color: Color3?)
			toasts:Push(text, color)
		end,
		Close = function()
			UIController.ClosePanel()
		end,
	}
	panels.Shop = ShopPanel.Create(screen, context)
	panels.Pets = PetsPanel.Create(screen, context)
	panels.Rebirth = RebirthPanel.Create(screen, context)
end

function UIController.Start()
	updateStats()
	updateGauge()
	updateEra()
	updateActionButton(RopeController.GetMode())

	ClientState.Changed:Connect(function(key: string)
		if
			key == "*"
			or key == "TotalStrength"
			or key == "Shards"
			or key == "RebirthCount"
			or key == "RebirthTokens"
		then
			updateStats()
		end
		if key == "*" or key == "UnbankedKP" or key == "StaminaCapacity" then
			updateGauge()
		end
		if key == "*" or key == "Era" then
			updateEra()
		end
	end)

	RopeController.ModeChanged:Connect(updateActionButton)
	UserInputService.LastInputTypeChanged:Connect(function()
		updateActionButton(RopeController.GetMode())
	end)

	RopeController.BounceConfirmed:Connect(function(result: BounceResult)
		if not result.Accepted then
			return
		end
		if result.Gained > 0 then
			popKP(`+{NumberFormat.Abbreviate(result.Gained)} KP`, Palette.Kinetic)
		end
		if result.Capped then
			UIKit.Pop(gaugeFrame, 1.12)
		end
	end)

	Remotes.Banked.OnClientEvent:Connect(function(amount: number, _totalStrength: number)
		SoundPlayer.Play("ObeliskBank")
		toasts:Push(`+{NumberFormat.Abbreviate(amount)} Strength banked!`, Palette.Accent)
		UIKit.Pop(gaugeFrame, 1.15)
	end)

	Remotes.MobReward.OnClientEvent:Connect(function(report: RewardReport)
		if type(report) ~= "table" then
			return
		end
		toasts:Push(
			`+{NumberFormat.Abbreviate(report.Shards)} Shards · {report.MobName} ({NumberFormat.Percent(
				report.Contribution
			)})`,
			Palette.Shard
		)
		for _, drop in report.Drops do
			local name = if drop.Kind == "Pet"
				then (GameConfig.Pets[drop.Id] and GameConfig.Pets[drop.Id].DisplayName or drop.Id)
				else (GameConfig.Titles[drop.Id] and GameConfig.Titles[drop.Id].DisplayName or drop.Id)
			toasts:Push(`RARE DROP: {name}!`, Palette.Accent, 4)
		end
	end)

	Remotes.HatchResult.OnClientEvent:Connect(showHatch)
	Remotes.RebirthComplete.OnClientEvent:Connect(celebrateRebirth)
	Remotes.Notify.OnClientEvent:Connect(function(kind: string, message: string)
		toasts:Push(tostring(message), NOTIFY_COLORS[kind] or Palette.Text)
	end)

	ContextActionService:BindAction(
		ACTION_DRAWER,
		function(_: string, state: Enum.UserInputState): Enum.ContextActionResult
			if state == Enum.UserInputState.Begin then
				setDrawerOpen(not drawerOpen)
			end
			return Enum.ContextActionResult.Sink
		end,
		false,
		Enum.KeyCode.ButtonY
	)

	local elapsed = 0
	RunService.Heartbeat:Connect(function(deltaTime: number)
		elapsed += deltaTime
		if elapsed >= BOSS_SCAN_INTERVAL then
			elapsed = 0
			updateBossBar()
		end
	end)
end

return UIController
