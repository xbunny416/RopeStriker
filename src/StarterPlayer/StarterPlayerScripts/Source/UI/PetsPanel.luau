--!strict
--[[
	PetsPanel
	---------
	Pet inventory: equip/unequip (tap a card), Equip Best, and the live
	PetMultiplierSum. Eggs are hatched in the world at the Chrono-Egg Incubator.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Source = ReplicatedStorage.Source
local GameConfig = require(Source.Configuration.GameConfig)
local Formulas = require(Source.Shared.Formulas)
local NumberFormat = require(Source.Shared.NumberFormat)
local Remotes = require(Source.Network.Remotes)

local ClientState = require(script.Parent.Parent.Modules.ClientState)
local PanelFrame = require(script.Parent.PanelFrame)
local UIKit = require(script.Parent.UIKit)

type PetRecord = GameConfig.PetRecord

local PetsPanel = {}

function PetsPanel.Create(parent: Instance, context: PanelFrame.Context): PanelFrame.Panel
	local card, content = PanelFrame.Create(parent, "PetsPanel", "CHRONO PETS", UIKit.Palette.Shard, context.Close)
	local busy = false

	local summary = UIKit.Label(content, "Summary", "", UDim2.fromScale(0.36, 0.06), UDim2.fromScale(0.7, 0.09), 22)
	summary.Font = UIKit.HeadingFont
	local grid =
		PanelFrame.Grid(content, UDim2.fromScale(0.5, 0.57), UDim2.fromScale(1, 0.84), UDim2.fromScale(0.23, 0.42), 0.9)
	local empty = UIKit.Label(
		content,
		"Empty",
		"No pets yet! Hatch Chrono-Eggs at the Incubator in the Training Piazza.",
		UDim2.fromScale(0.5, 0.5),
		UDim2.fromScale(0.8, 0.12),
		24
	)
	empty.TextColor3 = UIKit.Palette.TextDim
	empty.Visible = false

	local refresh: () -> ()

	local function setEquipped(uid: string, equipped: boolean)
		if busy then
			return
		end
		busy = true
		task.spawn(function()
			local ok, success, message = pcall(function()
				return Remotes.SetPetEquipped:InvokeServer(uid, equipped)
			end)
			busy = false
			if ok and not success then
				context.Toast(tostring(message), UIKit.Palette.Bad)
			end
			refresh()
		end)
	end

	local bestButton = UIKit.Button(
		content,
		"EquipBest",
		"EQUIP BEST",
		UDim2.fromScale(0.86, 0.06),
		UDim2.fromScale(0.24, 0.09),
		UIKit.Palette.Good,
		function()
			setEquipped("*best", true)
		end
	)

	refresh = function()
		PanelFrame.Clear(grid)
		local data = ClientState.Get()
		if data == nil then
			return
		end
		local records: { PetRecord } = {}
		for _, record in data.Pets do
			if GameConfig.Pets[record.Id] then
				table.insert(records, record)
			end
		end
		table.sort(records, function(a: PetRecord, b: PetRecord): boolean
			local pa = GameConfig.Pets[a.Id]
			local pb = GameConfig.Pets[b.Id]
			if pa.Multiplier ~= pb.Multiplier then
				return pa.Multiplier > pb.Multiplier
			end
			return a.Uid < b.Uid
		end)

		local equippedIds = Formulas.EquippedPetIds(data)
		summary.Text = `Equipped {#data.EquippedPets}/{Formulas.MaxEquippedPets(data)}   Bonus {NumberFormat.Multiplier(
			Formulas.PetMultiplierSum(equippedIds)
		)}   Inventory {#records}/{GameConfig.Pet.MaxInventory}`
		empty.Visible = #records == 0

		for index, record in records do
			local pet = GameConfig.Pets[record.Id]
			local equipped = table.find(data.EquippedPets, record.Uid) ~= nil
			local rarityColor = GameConfig.Pet.RarityColors[pet.Rarity]
			local cardFrame: TextButton = UIKit.new("TextButton", {
				Name = record.Uid,
				Text = "",
				AutoButtonColor = false,
				BackgroundTransparency = 0,
				BackgroundColor3 = if equipped then UIKit.Palette.PanelLight else UIKit.Palette.Background,
				LayoutOrder = index,
				Selectable = true,
				ZIndex = 12,
				Parent = grid,
			}, {
				UIKit.Corner(0.1),
				UIKit.Stroke(if equipped then UIKit.Palette.Good else rarityColor, if equipped then 4 else 2),
			})
			cardFrame.Activated:Connect(function()
				UIKit.Pop(cardFrame)
				setEquipped(record.Uid, not equipped)
			end)
			UIKit.new("Frame", {
				Name = "Portrait",
				Position = UDim2.fromScale(0.5, 0.3),
				Size = UDim2.fromScale(0.5, 0.5),
				BackgroundColor3 = pet.Visual.PrimaryColor,
				ZIndex = 13,
				Parent = cardFrame,
			}, { UIKit.Corner(0.5), UIKit.Aspect(1), UIKit.Stroke(pet.Visual.AccentColor, 3) })
			local name = UIKit.Label(
				cardFrame,
				"Name",
				pet.DisplayName,
				UDim2.fromScale(0.5, 0.64),
				UDim2.fromScale(0.92, 0.13),
				18
			)
			name.Font = UIKit.HeadingFont
			name.ZIndex = 13
			local rarity =
				UIKit.Label(cardFrame, "Rarity", pet.Rarity, UDim2.fromScale(0.5, 0.76), UDim2.fromScale(0.8, 0.1), 14)
			rarity.TextColor3 = rarityColor
			rarity.ZIndex = 13
			local multiplier = UIKit.Label(
				cardFrame,
				"Multiplier",
				if equipped
					then `{NumberFormat.Multiplier(pet.Multiplier)}  EQUIPPED`
					else NumberFormat.Multiplier(pet.Multiplier),
				UDim2.fromScale(0.5, 0.89),
				UDim2.fromScale(0.9, 0.1),
				16
			)
			multiplier.TextColor3 = if equipped then UIKit.Palette.Good else UIKit.Palette.Kinetic
			multiplier.ZIndex = 13
		end
	end

	ClientState.Changed:Connect(function(key: string)
		if card.Visible and (key == "*" or key == "Pets" or key == "EquippedPets" or key == "SkillLevels") then
			refresh()
		end
	end)

	return {
		Name = "Pets",
		Frame = card,
		Refresh = refresh,
		DefaultSelection = function(): GuiObject?
			return bestButton
		end,
	}
end

return PetsPanel
