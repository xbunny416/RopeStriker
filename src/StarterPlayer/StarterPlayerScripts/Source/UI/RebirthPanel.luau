--!strict
--[[
	RebirthPanel
	------------
	Temporal Paradox (Bible §2.2): requirement checklist, what resets/what is kept, the
	compound multiplier preview, a two-step confirm, and the Rebirth Paradox Skill Tree.

	The skill-tree canvas is square (UIAspectRatioConstraint 1), so node positions and
	the connector lines can be expressed purely in Scale coordinates.
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

local CONFIRM_WINDOW = 3

local RebirthPanel = {}

function RebirthPanel.Create(parent: Instance, context: PanelFrame.Context): PanelFrame.Panel
	local paradox = Color3.fromRGB(178, 120, 255)
	local card, content = PanelFrame.Create(parent, "RebirthPanel", "TEMPORAL PARADOX", paradox, context.Close)
	local busy = false
	local confirmUntil = 0

	-- Left column: requirements and the rebirth button.
	local left: Frame = UIKit.new("Frame", {
		Name = "Requirements",
		Position = UDim2.fromScale(0.25, 0.5),
		Size = UDim2.fromScale(0.48, 1),
		BackgroundTransparency = 1,
		ZIndex = 11,
		Parent = content,
	})
	local multiplier = UIKit.Label(left, "Multiplier", "", UDim2.fromScale(0.5, 0.08), UDim2.fromScale(0.95, 0.1), 28)
	multiplier.Font = UIKit.HeadingFont
	multiplier.TextColor3 = paradox
	local eraLine = UIKit.Label(left, "EraRequirement", "", UDim2.fromScale(0.5, 0.21), UDim2.fromScale(0.95, 0.08), 20)
	local strengthLine =
		UIKit.Label(left, "StrengthRequirement", "", UDim2.fromScale(0.5, 0.31), UDim2.fromScale(0.95, 0.08), 20)

	local barBack: Frame = UIKit.new("Frame", {
		Name = "StrengthBar",
		Position = UDim2.fromScale(0.5, 0.39),
		Size = UDim2.fromScale(0.9, 0.045),
		BackgroundColor3 = UIKit.Palette.Background,
		Parent = left,
	}, { UIKit.Corner(0.5) })
	local barFill: Frame = UIKit.new("Frame", {
		Name = "Fill",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.fromScale(0, 0.5),
		Size = UDim2.fromScale(0, 1),
		BackgroundColor3 = paradox,
		Parent = barBack,
	}, { UIKit.Corner(0.5) })

	local info = UIKit.Label(
		left,
		"Info",
		"RESETS: Strength, unbanked KP, ropes & boots\nKEEPS: Rifts, pets, titles, tokens & skills\nGAINS: x1.5 compound base stats + 1 Rebirth Token",
		UDim2.fromScale(0.5, 0.58),
		UDim2.fromScale(0.95, 0.24),
		18
	)
	info.TextColor3 = UIKit.Palette.TextDim

	local rebirthButton: TextButton
	rebirthButton = UIKit.Button(
		left,
		"Rebirth",
		"REBIRTH",
		UDim2.fromScale(0.5, 0.86),
		UDim2.fromScale(0.7, 0.14),
		paradox,
		function()
			local data = ClientState.Get()
			if data == nil or busy then
				return
			end
			local check = Formulas.CheckRebirth(data)
			if not check.Allowed then
				context.Toast(check.Reason or "Requirements not met.", UIKit.Palette.Bad)
				return
			end
			if os.clock() > confirmUntil then
				confirmUntil = os.clock() + CONFIRM_WINDOW
				rebirthButton.Text = "CONFIRM?"
				task.delay(CONFIRM_WINDOW, function()
					if os.clock() >= confirmUntil then
						rebirthButton.Text = "REBIRTH"
					end
				end)
				return
			end
			confirmUntil = 0
			busy = true
			task.spawn(function()
				local ok, success, message = pcall(function()
					return Remotes.RequestRebirth:InvokeServer()
				end)
				busy = false
				rebirthButton.Text = "REBIRTH"
				if ok then
					context.Toast(tostring(message), if success then paradox else UIKit.Palette.Bad)
				end
			end)
		end
	)

	-- Right column: the skill tree.
	local tokens = UIKit.Label(content, "Tokens", "", UDim2.fromScale(0.75, 0.04), UDim2.fromScale(0.45, 0.07), 22)
	tokens.Font = UIKit.HeadingFont
	tokens.TextColor3 = UIKit.Palette.Accent
	local canvas: Frame = UIKit.new("Frame", {
		Name = "SkillTree",
		Position = UDim2.fromScale(0.75, 0.55),
		Size = UDim2.fromScale(0.48, 0.9),
		BackgroundColor3 = UIKit.Palette.Background,
		BackgroundTransparency = 0.3,
		ZIndex = 11,
		Parent = content,
	}, { UIKit.Corner(0.05), UIKit.Aspect(1) })

	-- Connector lines (static).
	for _, node in GameConfig.SkillTree do
		for _, requirement in node.Requires do
			local from = GameConfig.SkillTree[requirement.Id]
			if from == nil then
				continue
			end
			local a = from.LayoutPosition
			local b = node.LayoutPosition
			local delta = b - a
			UIKit.new("Frame", {
				Name = `Link_{from.Id}_{node.Id}`,
				Position = UDim2.fromScale((a.X + b.X) / 2, (a.Y + b.Y) / 2),
				Size = UDim2.fromScale(delta.Magnitude, 0.012),
				Rotation = math.deg(math.atan2(delta.Y, delta.X)),
				BackgroundColor3 = UIKit.Palette.PanelLight,
				ZIndex = 12,
				Parent = canvas,
			})
		end
	end

	local nodeButtons: { [string]: TextButton } = {}
	for nodeId, node in GameConfig.SkillTree do
		local button: TextButton = UIKit.new("TextButton", {
			Name = nodeId,
			Text = "",
			Position = UDim2.fromScale(node.LayoutPosition.X, node.LayoutPosition.Y),
			Size = UDim2.fromScale(0.3, 0.17),
			AutoButtonColor = false,
			BackgroundTransparency = 0,
			BackgroundColor3 = UIKit.Palette.PanelLight,
			Font = UIKit.HeadingFont,
			Selectable = true,
			ZIndex = 13,
			Parent = canvas,
		}, { UIKit.Corner(0.2), UIKit.Stroke(UIKit.Palette.TextDim, 2), UIKit.TextLimit(15), UIKit.Padding(0.06) })
		button.Activated:Connect(function()
			UIKit.Pop(button)
			if busy then
				return
			end
			busy = true
			task.spawn(function()
				local ok, success, message = pcall(function()
					return Remotes.UnlockSkill:InvokeServer(nodeId)
				end)
				busy = false
				if ok then
					context.Toast(tostring(message), if success then UIKit.Palette.Good else UIKit.Palette.Bad)
				end
			end)
		end)
		nodeButtons[nodeId] = button
	end

	local function refresh()
		local data = ClientState.Get()
		if data == nil then
			return
		end
		local now = Formulas.RebirthMultiplier(data.RebirthCount)
		local after = Formulas.RebirthMultiplier(data.RebirthCount + 1)
		multiplier.Text =
			`Rebirths {data.RebirthCount}   {NumberFormat.Multiplier(now)} -> {NumberFormat.Multiplier(after)}`

		local rules = GameConfig.Rebirth
		local eraOk = data.HighestEra >= rules.RequiredEra
		local era = GameConfig.Eras[rules.RequiredEra]
		eraLine.Text = `{if eraOk then "[OK]" else "[  ]"} Reach Era {rules.RequiredEra}: {era.DisplayName}`
		eraLine.TextColor3 = if eraOk then UIKit.Palette.Good else UIKit.Palette.Text

		local strengthOk = data.TotalStrength >= rules.RequiredStrength
		strengthLine.Text = `{if strengthOk then "[OK]" else "[  ]"} Strength {NumberFormat.Abbreviate(
			data.TotalStrength
		)} / {NumberFormat.Abbreviate(rules.RequiredStrength)}`
		strengthLine.TextColor3 = if strengthOk then UIKit.Palette.Good else UIKit.Palette.Text
		barFill.Size = UDim2.fromScale(math.clamp(data.TotalStrength / rules.RequiredStrength, 0, 1), 1)

		local allowed = Formulas.CheckRebirth(data).Allowed
		rebirthButton.BackgroundColor3 = if allowed then paradox else UIKit.Palette.PanelLight
		tokens.Text = `Rebirth Tokens: {data.RebirthTokens}`

		for nodeId, button in nodeButtons do
			local node = GameConfig.SkillTree[nodeId]
			local level = data.SkillLevels[nodeId] or 0
			local maxed = level >= node.MaxLevel
			local unlockable = not maxed and data.RebirthTokens >= node.CostPerLevel
			if unlockable then
				for _, requirement in node.Requires do
					if (data.SkillLevels[requirement.Id] or 0) < requirement.Level then
						unlockable = false
					end
				end
			end
			button.Text =
				`{node.DisplayName}\n{level}/{node.MaxLevel}{if maxed then "" else `  ({node.CostPerLevel} tk)`}`
			button.BackgroundColor3 = if maxed
				then UIKit.Palette.AccentDark
				elseif unlockable then UIKit.Palette.Good
				else UIKit.Palette.PanelLight
			local stroke = button:FindFirstChildOfClass("UIStroke")
			if stroke then
				stroke.Color = if level > 0 then UIKit.Palette.Accent else UIKit.Palette.TextDim
			end
		end
	end

	ClientState.Changed:Connect(function(key: string)
		if card.Visible then
			if
				key == "*"
				or key == "RebirthCount"
				or key == "RebirthTokens"
				or key == "TotalStrength"
				or key == "HighestEra"
				or key == "SkillLevels"
			then
				refresh()
			end
		end
	end)

	return {
		Name = "Rebirth",
		Frame = card,
		Refresh = refresh,
		DefaultSelection = function(): GuiObject?
			return rebirthButton
		end,
	}
end

return RebirthPanel
