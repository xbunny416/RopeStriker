--!strict
--[[
	PanelFrame
	----------
	Shared chrome for the modal panels opened from the left drawer (Rebirth, Shop, Pets):
	a centred card with a title bar, a close button and a content area. The card keeps
	a fixed aspect ratio so it reads the same on phones, tablets, PCs and TVs.
]]

local UIKit = require(script.Parent.UIKit)

export type Context = {
	Toast: (text: string, color: Color3?) -> (),
	Close: () -> (),
}

export type Panel = {
	Name: string,
	Frame: Frame,
	Refresh: () -> (),
	DefaultSelection: () -> GuiObject?,
}

local PanelFrame = {}

-- Returns (card, content). The card starts hidden.
function PanelFrame.Create(
	parent: Instance,
	name: string,
	title: string,
	accent: Color3,
	onClose: () -> ()
): (Frame, Frame)
	local card: Frame = UIKit.new("Frame", {
		Name = name,
		Position = UDim2.fromScale(0.5, 0.53),
		Size = UDim2.fromScale(0.66, 0.74),
		BackgroundColor3 = UIKit.Palette.Panel,
		Visible = false,
		ZIndex = 10,
		Parent = parent,
	}, {
		UIKit.Corner(0.04),
		UIKit.Stroke(accent, 3, 0.1),
		UIKit.Aspect(1.6),
		UIKit.Gradient(Color3.new(1, 1, 1), Color3.fromRGB(200, 200, 210)),
	})

	UIKit.new("TextLabel", {
		Name = "Title",
		Text = title,
		Position = UDim2.fromScale(0.5, 0.065),
		Size = UDim2.fromScale(0.6, 0.09),
		Font = UIKit.HeadingFont,
		TextColor3 = accent,
		ZIndex = 11,
		Parent = card,
	}, { UIKit.TextLimit(40), UIKit.TextStroke(Color3.new(0, 0, 0), 2) })

	local close = UIKit.Button(
		card,
		"Close",
		"X",
		UDim2.fromScale(0.955, 0.07),
		UDim2.fromScale(0.06, 0.1),
		UIKit.Palette.Bad,
		onClose
	)
	close.ZIndex = 12
	UIKit.Aspect(1).Parent = close

	local content: Frame = UIKit.new("Frame", {
		Name = "Content",
		Position = UDim2.fromScale(0.5, 0.56),
		Size = UDim2.fromScale(0.95, 0.83),
		BackgroundTransparency = 1,
		ZIndex = 11,
		Parent = card,
	})
	return card, content
end

-- A vertically scrolling grid of cards sized in Scale units.
function PanelFrame.Grid(
	parent: Instance,
	position: UDim2,
	size: UDim2,
	cellSize: UDim2,
	aspect: number
): ScrollingFrame
	local scroller: ScrollingFrame = UIKit.new("ScrollingFrame", {
		Name = "Grid",
		Position = position,
		Size = size,
		BackgroundTransparency = 1,
		ScrollBarThickness = 6,
		ScrollBarImageColor3 = UIKit.Palette.Accent,
		CanvasSize = UDim2.fromScale(0, 0),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		Selectable = false,
		ZIndex = 11,
		Parent = parent,
	})
	local grid = Instance.new("UIGridLayout")
	grid.CellSize = cellSize
	grid.CellPadding = UDim2.fromScale(0.015, 0.02)
	grid.SortOrder = Enum.SortOrder.LayoutOrder
	grid.HorizontalAlignment = Enum.HorizontalAlignment.Center
	grid.Parent = scroller
	UIKit.Aspect(aspect).Parent = grid
	UIKit.Padding(0.01).Parent = scroller
	return scroller
end

-- Clears generated children (keeps layout objects).
function PanelFrame.Clear(container: Instance)
	for _, child in container:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
end

return PanelFrame
