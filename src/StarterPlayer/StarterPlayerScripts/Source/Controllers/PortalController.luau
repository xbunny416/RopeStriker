--!strict
--[[
	PortalController
	----------------
	Client-side collision gates for the Chronal Rifts (Bible §3.1).

	Rift barriers are solid for everyone on the server. Once the server has verified
	this player's stored TotalStrength/RebirthCount and persisted the unlock (it arrives
	in UnlockedPortals / PortalUnlocked), this client turns the barrier's CanCollide off
	locally, so only this player can walk through. Labels show each rift's requirement
	and progress. Barriers stream in and out, so everything is tag-driven.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Source = ReplicatedStorage.Source
local GameConfig = require(Source.Configuration.GameConfig)
local NumberFormat = require(Source.Shared.NumberFormat)
local Tags = require(Source.Shared.Tags)
local Remotes = require(Source.Network.Remotes)

local Modules = script.Parent.Parent.Modules
local ClientState = require(Modules.ClientState)
local SoundPlayer = require(Modules.SoundPlayer)

type GateView = {
	Barrier: BasePart,
	PortalId: string,
	Title: TextLabel,
	Detail: TextLabel,
}

local ROMAN = { "I", "II", "III", "IV", "V", "VI" }

local PortalController = {}

local gates: { [BasePart]: GateView } = {}
local labelRoot: Instance

local function isUnlocked(portalId: string): boolean
	local data = ClientState.Get()
	return data ~= nil and data.UnlockedPortals[portalId] == true
end

local function refreshGate(view: GateView)
	local portal = GameConfig.Portals[view.PortalId]
	if portal == nil then
		return
	end
	local unlocked = isUnlocked(view.PortalId)
	view.Barrier.CanCollide = not unlocked
	view.Barrier.Transparency = if unlocked then 0.8 else 0

	local era = GameConfig.Eras[portal.ToEra]
	view.Title.Text = `ERA {ROMAN[portal.ToEra] or tostring(portal.ToEra)} · {string.upper(era.DisplayName)}`
	view.Title.TextColor3 = era.Theme.Accent
	if unlocked then
		view.Detail.Text = "RIFT OPEN"
		view.Detail.TextColor3 = GameConfig.UI.Palette.Good
		return
	end
	local data = ClientState.Get()
	local strength = if data then data.TotalStrength else 0
	local text =
		`Requires {NumberFormat.Abbreviate(portal.RequiredStrength)} Strength ({NumberFormat.Abbreviate(strength)})`
	if portal.RequiredRebirths > 0 then
		text ..= ` + {portal.RequiredRebirths} Rebirths`
	end
	view.Detail.Text = text
	view.Detail.TextColor3 = GameConfig.UI.Palette.Text
end

local function label(parent: Instance, name: string, positionY: number, height: number): TextLabel
	local text = Instance.new("TextLabel")
	text.Name = name
	text.AnchorPoint = Vector2.new(0.5, 0.5)
	text.Position = UDim2.fromScale(0.5, positionY)
	text.Size = UDim2.fromScale(1, height)
	text.BackgroundTransparency = 1
	text.Font = Enum.Font.FredokaOne
	text.TextScaled = true
	text.TextColor3 = Color3.new(1, 1, 1)
	text.TextStrokeTransparency = 0.2
	text.Parent = parent
	return text
end

local function track(instance: Instance)
	if not instance:IsA("BasePart") or gates[instance] then
		return
	end
	local portalId = instance:GetAttribute("PortalId")
	if type(portalId) ~= "string" then
		return
	end
	local anchor = instance:FindFirstChild("LabelAttachment")
	local gui = Instance.new("BillboardGui")
	gui.Name = `RiftLabel_{portalId}`
	gui.Adornee = if anchor then anchor else instance
	gui.Size = UDim2.fromScale(26, 5)
	gui.MaxDistance = 160
	gui.LightInfluence = 0
	gui.ResetOnSpawn = false
	local view: GateView = {
		Barrier = instance,
		PortalId = portalId,
		Title = label(gui, "Title", 0.3, 0.55),
		Detail = label(gui, "Detail", 0.78, 0.38),
	}
	gui.Parent = labelRoot
	gates[instance] = view
	refreshGate(view)

	instance.AncestryChanged:Connect(function()
		if instance.Parent == nil then
			gates[instance] = nil
			gui:Destroy()
		end
	end)
end

local function refreshAll()
	for _, view in gates do
		refreshGate(view)
	end
end

function PortalController.Init()
	labelRoot = Players.LocalPlayer:WaitForChild("PlayerGui")
end

function PortalController.Start()
	for _, instance in CollectionService:GetTagged(Tags.ChronalRiftGate) do
		track(instance)
	end
	CollectionService:GetInstanceAddedSignal(Tags.ChronalRiftGate):Connect(track)

	ClientState.Changed:Connect(function(key: string)
		if key == "*" or key == "UnlockedPortals" or key == "TotalStrength" or key == "RebirthCount" then
			refreshAll()
		end
	end)

	Remotes.PortalUnlocked.OnClientEvent:Connect(function(portalId: string)
		local data = ClientState.Get()
		if data and type(portalId) == "string" then
			data.UnlockedPortals[portalId] = true
		end
		refreshAll()
		local portal = GameConfig.Portals[portalId]
		if portal then
			SoundPlayer.PlayAt("ObeliskBank", portal.Position + Vector3.new(0, 10, 0), 1.25)
		end
	end)
end

return PortalController
