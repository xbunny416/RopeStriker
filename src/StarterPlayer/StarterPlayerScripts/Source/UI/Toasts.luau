--!strict
--[[
	Toasts
	------
	Short stacked notifications under the top of the screen (rewards, banking, errors).
	At most MAX_VISIBLE are shown; older ones slide away first.
]]

local UIKit = require(script.Parent.UIKit)

export type Toasts = {
	Push: (self: Toasts, text: string, color: Color3?, seconds: number?) -> (),
}

local MAX_VISIBLE = 4

local Toasts = {}

function Toasts.new(parent: Instance): Toasts
	local stack: Frame = UIKit.new("Frame", {
		Name = "Toasts",
		Position = UDim2.fromScale(0.5, 0.27),
		Size = UDim2.fromScale(0.46, 0.22),
		BackgroundTransparency = 1,
		Parent = parent,
	})
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Top
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0.03, 0)
	layout.Parent = stack

	local order = 0
	local live: { Frame } = {}

	local toasts: Toasts = {
		Push = function(_: Toasts, text: string, color: Color3?, seconds: number?)
			order += 1
			local tint = color or UIKit.Palette.Text
			local toast: Frame = UIKit.new("Frame", {
				Name = "Toast",
				Size = UDim2.fromScale(1, 0.22),
				BackgroundColor3 = UIKit.Palette.Background,
				BackgroundTransparency = 0.2,
				LayoutOrder = order,
				Parent = stack,
			}, {
				UIKit.Corner(0.4),
				UIKit.Stroke(tint, 2, 0.3),
			})
			local label: TextLabel = UIKit.new("TextLabel", {
				Name = "Text",
				Text = text,
				Position = UDim2.fromScale(0.5, 0.5),
				Size = UDim2.fromScale(0.94, 0.8),
				TextColor3 = tint,
				Font = UIKit.HeadingFont,
				Parent = toast,
			}, { UIKit.TextLimit(22), UIKit.TextStroke(Color3.new(0, 0, 0), 1) })

			table.insert(live, toast)
			if #live > MAX_VISIBLE then
				local oldest = table.remove(live, 1)
				if oldest then
					oldest:Destroy()
				end
			end

			task.delay(seconds or 2.6, function()
				if toast.Parent == nil then
					return
				end
				UIKit.Tween(toast, 0.3, { BackgroundTransparency = 1 })
				UIKit.Tween(label, 0.3, { TextTransparency = 1 })
				task.wait(0.3)
				local index = table.find(live, toast)
				if index then
					table.remove(live, index)
				end
				toast:Destroy()
			end)
		end,
	}
	return toasts
end

return Toasts
