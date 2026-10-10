--!strict
--[[
	WorldController
	---------------
	World-anchored client UI and interactions:

	  * Overhead nameplates: equipped title (cosmetic, retained through rebirth) and
	    rebirth count above every player.
	  * Panel prompts: ProximityPrompts tagged PanelPrompt (Blacksmith anvil, Rebirth
	    Portal arch) open the matching UI panel. Gameplay prompts (Epoch Obelisk, eggs)
	    are handled on the server.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Source = ReplicatedStorage.Source
local GameConfig = require(Source.Configuration.GameConfig)
local Tags = require(Source.Shared.Tags)

local UIController = require(script.Parent.UIController)

local WorldController = {}

local localPlayer = Players.LocalPlayer
local plateRoot: Instance
local plates: { [Player]: BillboardGui? } = {}

local function refreshPlate(player: Player)
	local gui = plates[player]
	if gui == nil then
		return
	end
	local title = gui:FindFirstChild("Title")
	local rebirths = gui:FindFirstChild("Rebirths")
	local titleId = player:GetAttribute("EquippedTitle")
	local titleData = if type(titleId) == "string" then GameConfig.Titles[titleId] else nil
	if title and title:IsA("TextLabel") then
		title.Text = if titleData then titleData.DisplayName else ""
		title.TextColor3 = if titleData then titleData.Color else Color3.new(1, 1, 1)
	end
	if rebirths and rebirths:IsA("TextLabel") then
		local count = player:GetAttribute("RebirthCount")
		rebirths.Text = if type(count) == "number" and count > 0 then `⏳ {count}` else ""
	end
end

local function attachPlate(player: Player, character: Model)
	local existing = plates[player]
	if existing then
		existing:Destroy()
	end
	local head = character:WaitForChild("Head", 10)
	if head == nil or not head:IsA("BasePart") or player.Character ~= character then
		return
	end
	local gui = Instance.new("BillboardGui")
	gui.Name = `Nameplate_{player.UserId}`
	gui.Adornee = head
	gui.Size = UDim2.fromScale(6, 1.3)
	gui.StudsOffset = Vector3.new(0, 2.6, 0)
	gui.MaxDistance = 90
	gui.LightInfluence = 0
	gui.ResetOnSpawn = false

	for _, spec in { { Name = "Title", Y = 0.3, H = 0.55 }, { Name = "Rebirths", Y = 0.8, H = 0.38 } } do
		local text = Instance.new("TextLabel")
		text.Name = spec.Name
		text.AnchorPoint = Vector2.new(0.5, 0.5)
		text.Position = UDim2.fromScale(0.5, spec.Y)
		text.Size = UDim2.fromScale(1, spec.H)
		text.BackgroundTransparency = 1
		text.Font = Enum.Font.FredokaOne
		text.TextScaled = true
		text.TextColor3 = Color3.fromRGB(205, 160, 255)
		text.TextStrokeTransparency = 0.3
		text.Parent = gui
	end
	gui.Parent = plateRoot
	plates[player] = gui
	refreshPlate(player)
end

local function watchPlayer(player: Player)
	player.CharacterAdded:Connect(function(character: Model)
		attachPlate(player, character)
	end)
	if player.Character then
		task.spawn(attachPlate, player, player.Character)
	end
	player:GetAttributeChangedSignal("EquippedTitle"):Connect(function()
		refreshPlate(player)
	end)
	player:GetAttributeChangedSignal("RebirthCount"):Connect(function()
		refreshPlate(player)
	end)
end

function WorldController.Init()
	plateRoot = localPlayer:WaitForChild("PlayerGui")
end

function WorldController.Start()
	for _, player in Players:GetPlayers() do
		watchPlayer(player)
	end
	Players.PlayerAdded:Connect(watchPlayer)
	Players.PlayerRemoving:Connect(function(player: Player)
		local gui = plates[player]
		if gui then
			gui:Destroy()
			plates[player] = nil
		end
	end)

	ProximityPromptService.PromptTriggered:Connect(function(prompt: ProximityPrompt, player: Player)
		if player ~= localPlayer or not CollectionService:HasTag(prompt, Tags.PanelPrompt) then
			return
		end
		local panel = prompt:GetAttribute("OpensPanel")
		if type(panel) == "string" then
			UIController.OpenPanel(panel)
		end
	end)
end

return WorldController
