--!strict
--[[
	ShopPanel
	---------
	The Blacksmith: buy and equip ropes and boots with Shards, equip earned titles.
	Every action is a RemoteFunction request validated by the server
	(EquipmentService + PlayerDataOps); the panel only reflects replicated state.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Source = ReplicatedStorage.Source
local GameConfig = require(Source.Configuration.GameConfig)
local NumberFormat = require(Source.Shared.NumberFormat)
local Remotes = require(Source.Network.Remotes)

local ClientState = require(script.Parent.Parent.Modules.ClientState)
local PanelFrame = require(script.Parent.PanelFrame)
local UIKit = require(script.Parent.UIKit)

type Category = "Rope" | "Boots" | "Title"

type Entry = {
	Id: string,
	Name: string,
	Description: string,
	Stats: string,
	Price: number,
	Era: number,
	Color: Color3,
	LayoutOrder: number,
}

local TABS: { { Category: Category, Label: string } } = {
	{ Category = "Rope", Label = "ROPES" },
	{ Category = "Boots", Label = "BOOTS" },
	{ Category = "Title", Label = "TITLES" },
}

local ShopPanel = {}

local function entriesFor(category: Category): { Entry }
	local entries: { Entry } = {}
	if category == "Rope" then
		for _, rope in GameConfig.Ropes do
			table.insert(entries, {
				Id = rope.Id,
				Name = rope.DisplayName,
				Description = rope.Description,
				Stats = `KP x{rope.BaseKP}   DMG +{rope.BaseDamage}`,
				Price = rope.Price,
				Era = rope.Era,
				Color = rope.Visual.Color,
				LayoutOrder = rope.LayoutOrder,
			})
		end
	elseif category == "Boots" then
		for _, boots in GameConfig.Boots do
			table.insert(entries, {
				Id = boots.Id,
				Name = boots.DisplayName,
				Description = boots.Description,
				Stats = `{NumberFormat.Multiplier(boots.Multiplier)} KP   Stamina {NumberFormat.Abbreviate(
					boots.StaminaCapacity
				)}`,
				Price = boots.Price,
				Era = boots.Era,
				Color = boots.Visual.Color,
				LayoutOrder = boots.LayoutOrder,
			})
		end
	else
		for _, title in GameConfig.Titles do
			table.insert(entries, {
				Id = title.Id,
				Name = title.DisplayName,
				Description = title.Description,
				Stats = "",
				Price = -1,
				Era = 1,
				Color = title.Color,
				LayoutOrder = title.LayoutOrder,
			})
		end
	end
	table.sort(entries, function(a: Entry, b: Entry): boolean
		return a.LayoutOrder < b.LayoutOrder
	end)
	return entries
end

local function ownership(data: GameConfig.PlayerData, category: Category, id: string): (boolean, boolean)
	if category == "Rope" then
		return data.OwnedRopes[id] == true, data.EquippedRope == id
	elseif category == "Boots" then
		return data.OwnedBoots[id] == true, data.EquippedBoots == id
	end
	return data.OwnedTitles[id] == true, data.EquippedTitle == id
end

function ShopPanel.Create(parent: Instance, context: PanelFrame.Context): PanelFrame.Panel
	local card, content = PanelFrame.Create(parent, "ShopPanel", "THE BLACKSMITH", UIKit.Palette.Accent, context.Close)
	local current: Category = "Rope"
	local tabButtons: { [Category]: TextButton } = {}
	local busy = false

	local grid =
		PanelFrame.Grid(content, UDim2.fromScale(0.5, 0.57), UDim2.fromScale(1, 0.84), UDim2.fromScale(0.31, 0.5), 0.85)
	local shards = UIKit.Label(content, "Shards", "", UDim2.fromScale(0.86, 0.06), UDim2.fromScale(0.26, 0.09), 26)
	shards.TextColor3 = UIKit.Palette.Shard
	shards.Font = UIKit.HeadingFont

	local refresh: () -> ()

	local function request(remote: RemoteFunction, category: Category, id: string)
		if busy then
			return
		end
		busy = true
		task.spawn(function()
			local ok, success, message = pcall(function()
				return remote:InvokeServer(category, id)
			end)
			busy = false
			if not ok then
				context.Toast("The Blacksmith is busy. Try again!", UIKit.Palette.Bad)
				return
			end
			context.Toast(tostring(message), if success then UIKit.Palette.Good else UIKit.Palette.Bad)
			refresh()
		end)
	end

	local function buildCard(entry: Entry, data: GameConfig.PlayerData)
		local owned, equipped = ownership(data, current, entry.Id)
		local cardFrame: Frame = UIKit.new("Frame", {
			Name = entry.Id,
			BackgroundColor3 = UIKit.Palette.PanelLight,
			LayoutOrder = entry.LayoutOrder,
			ZIndex = 12,
			Parent = grid,
		}, {
			UIKit.Corner(0.08),
			UIKit.Stroke(if equipped then UIKit.Palette.Good else entry.Color, if equipped then 3 else 2),
		})
		UIKit.new("Frame", {
			Name = "Swatch",
			Position = UDim2.fromScale(0.5, 0.2),
			Size = UDim2.fromScale(0.3, 0.3),
			BackgroundColor3 = entry.Color,
			ZIndex = 13,
			Parent = cardFrame,
		}, { UIKit.Corner(0.5), UIKit.Aspect(1) })
		local name =
			UIKit.Label(cardFrame, "Name", entry.Name, UDim2.fromScale(0.5, 0.43), UDim2.fromScale(0.92, 0.12), 22)
		name.Font = UIKit.HeadingFont
		name.TextColor3 = if current == "Title" then entry.Color else UIKit.Palette.Text
		name.ZIndex = 13
		local description = UIKit.Label(
			cardFrame,
			"Description",
			entry.Description,
			UDim2.fromScale(0.5, 0.57),
			UDim2.fromScale(0.9, 0.14),
			14
		)
		description.TextColor3 = UIKit.Palette.TextDim
		description.ZIndex = 13
		if entry.Stats ~= "" then
			local stats =
				UIKit.Label(cardFrame, "Stats", entry.Stats, UDim2.fromScale(0.5, 0.7), UDim2.fromScale(0.9, 0.1), 16)
			stats.TextColor3 = UIKit.Palette.Kinetic
			stats.ZIndex = 13
		end

		local label: string
		local color: Color3
		local action: (() -> ())?
		if equipped then
			label, color, action = "EQUIPPED", UIKit.Palette.Good, nil
		elseif owned then
			label, color = "EQUIP", UIKit.Palette.Kinetic
			action = function()
				request(Remotes.EquipItem, current, entry.Id)
			end
		elseif current == "Title" then
			label, color, action = "LOCKED", UIKit.Palette.PanelLight, nil
		elseif entry.Era > data.HighestEra then
			label, color, action = `ERA {entry.Era}`, UIKit.Palette.PanelLight, nil
		else
			local affordable = data.Shards >= entry.Price
			label = `BUY {NumberFormat.Abbreviate(entry.Price)}`
			color = if affordable then UIKit.Palette.Accent else UIKit.Palette.Bad
			action = function()
				request(Remotes.PurchaseItem, current, entry.Id)
			end
		end
		local button = UIKit.Button(
			cardFrame,
			"Action",
			label,
			UDim2.fromScale(0.5, 0.87),
			UDim2.fromScale(0.8, 0.16),
			color,
			function()
				if action then
					action()
				end
			end
		)
		button.ZIndex = 13
		button.AutoButtonColor = action ~= nil
	end

	refresh = function()
		PanelFrame.Clear(grid)
		local data = ClientState.Get()
		if data == nil then
			return
		end
		shards.Text = `{NumberFormat.Abbreviate(data.Shards)} Shards`
		for category, button in tabButtons do
			button.BackgroundColor3 = if category == current then UIKit.Palette.Accent else UIKit.Palette.PanelLight
		end
		for _, entry in entriesFor(current) do
			buildCard(entry, data)
		end
	end

	for index, tab in TABS do
		tabButtons[tab.Category] = UIKit.Button(
			content,
			`Tab{tab.Category}`,
			tab.Label,
			UDim2.fromScale(0.1 + (index - 1) * 0.19, 0.06),
			UDim2.fromScale(0.17, 0.09),
			UIKit.Palette.PanelLight,
			function()
				current = tab.Category
				refresh()
			end
		)
	end

	ClientState.Changed:Connect(function(key: string)
		if card.Visible then
			if
				key == "*"
				or key == "Shards"
				or key == "OwnedRopes"
				or key == "OwnedBoots"
				or key == "OwnedTitles"
				or key == "EquippedRope"
				or key == "EquippedBoots"
				or key == "EquippedTitle"
			then
				refresh()
			end
		end
	end)

	return {
		Name = "Shop",
		Frame = card,
		Refresh = refresh,
		DefaultSelection = function(): GuiObject?
			return tabButtons[TABS[1].Category]
		end,
	}
end

return ShopPanel
