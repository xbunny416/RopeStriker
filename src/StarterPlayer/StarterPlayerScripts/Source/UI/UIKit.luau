--!strict
--[[
	UIKit
	-----
	Tiny declarative helpers for the cross-platform UI blueprint (Bible §5.1):

	  * Every element is centred with AnchorPoint (0.5, 0.5) and laid out with Scale-only
	    UDim2 values (no pixel offsets), so it reflows on any resolution.
	  * Squares/circles/cards keep their shape with UIAspectRatioConstraint.
	  * Text uses TextScaled + UITextSizeConstraint so it stays legible on phones and
	    does not balloon on 4K monitors.

	    local card = UIKit.new("Frame", {
	        Name = "Card", Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(0.3, 0.2),
	        BackgroundColor3 = UIKit.Palette.Panel, Parent = screen,
	    }, { UIKit.Corner(0.15), UIKit.Aspect(1.5) })
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local GameConfig = require(ReplicatedStorage.Source.Configuration.GameConfig)

local UIKit = {}

UIKit.Palette = GameConfig.UI.Palette
UIKit.HeadingFont = Enum.Font.FredokaOne
UIKit.BodyFont = Enum.Font.GothamBold
UIKit.Center = Vector2.new(0.5, 0.5)

-- Creates `className`, applies `props` (Parent last) and parents `children` to it.
-- Centred anchor by default for GuiObjects, as the blueprint requires.
function UIKit.new(className: string, props: { [string]: any }, children: { Instance }?): any
	local instance: any = Instance.new(className :: any)
	if instance:IsA("GuiObject") then
		instance.AnchorPoint = UIKit.Center
		instance.BorderSizePixel = 0
	end
	if instance:IsA("TextLabel") or instance:IsA("TextButton") or instance:IsA("TextBox") then
		instance.TextScaled = true
		instance.Font = UIKit.BodyFont
		instance.TextColor3 = UIKit.Palette.Text
		instance.BackgroundTransparency = 1
	end
	for key, value in props do
		if key ~= "Parent" then
			instance[key] = value
		end
	end
	if children then
		for _, child in children do
			child.Parent = instance
		end
	end
	local parent = props.Parent
	if parent then
		instance.Parent = parent
	end
	return instance
end

function UIKit.Corner(scale: number?): Instance
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(scale or 0.2, 0)
	return corner
end

function UIKit.Stroke(color: Color3, thickness: number?, transparency: number?): Instance
	local stroke = Instance.new("UIStroke")
	stroke.Color = color
	stroke.Thickness = thickness or 2
	stroke.Transparency = transparency or 0
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	return stroke
end

function UIKit.TextStroke(color: Color3, thickness: number?): Instance
	local stroke = Instance.new("UIStroke")
	stroke.Color = color
	stroke.Thickness = thickness or 1.5
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	return stroke
end

function UIKit.Aspect(ratio: number): Instance
	local aspect = Instance.new("UIAspectRatioConstraint")
	aspect.AspectRatio = ratio
	return aspect
end

function UIKit.TextLimit(maxSize: number, minSize: number?): Instance
	local limit = Instance.new("UITextSizeConstraint")
	limit.MaxTextSize = maxSize
	limit.MinTextSize = minSize or 8
	return limit
end

function UIKit.Padding(scale: number): Instance
	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(scale, 0)
	padding.PaddingBottom = UDim.new(scale, 0)
	padding.PaddingLeft = UDim.new(scale, 0)
	padding.PaddingRight = UDim.new(scale, 0)
	return padding
end

function UIKit.Gradient(top: Color3, bottom: Color3): Instance
	local gradient = Instance.new("UIGradient")
	gradient.Color = ColorSequence.new(top, bottom)
	gradient.Rotation = 90
	return gradient
end

function UIKit.Tween(instance: Instance, seconds: number, goals: { [string]: any }, style: Enum.EasingStyle?): Tween
	local tween = TweenService:Create(
		instance,
		TweenInfo.new(seconds, style or Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		goals
	)
	tween:Play()
	return tween
end

-- Squash-and-stretch feedback for a pressed control (needs a UIScale child).
function UIKit.Pop(target: GuiObject, amount: number?)
	local scale = target:FindFirstChildOfClass("UIScale")
	if scale == nil then
		local created = Instance.new("UIScale")
		created.Parent = target
		scale = created
	end
	local uiScale = scale :: UIScale
	uiScale.Scale = amount or 0.88
	UIKit.Tween(uiScale, 0.18, { Scale = 1 }, Enum.EasingStyle.Back)
end

-- Standard rounded button. `onActivated` runs on click/tap/gamepad A.
function UIKit.Button(
	parent: Instance,
	name: string,
	text: string,
	position: UDim2,
	size: UDim2,
	color: Color3,
	onActivated: () -> ()
): TextButton
	local button: TextButton = UIKit.new("TextButton", {
		Name = name,
		Text = text,
		Position = position,
		Size = size,
		BackgroundTransparency = 0,
		BackgroundColor3 = color,
		AutoButtonColor = false,
		Font = UIKit.HeadingFont,
		Selectable = true,
		Parent = parent,
	}, {
		UIKit.Corner(0.3),
		UIKit.TextLimit(28),
		UIKit.TextStroke(Color3.new(0, 0, 0), 1),
		UIKit.Padding(0.12),
	})
	button.Activated:Connect(function()
		UIKit.Pop(button)
		onActivated()
	end)
	return button
end

function UIKit.Label(
	parent: Instance,
	name: string,
	text: string,
	position: UDim2,
	size: UDim2,
	maxTextSize: number?
): TextLabel
	return UIKit.new("TextLabel", {
		Name = name,
		Text = text,
		Position = position,
		Size = size,
		Parent = parent,
	}, { UIKit.TextLimit(maxTextSize or 24) })
end

return UIKit
