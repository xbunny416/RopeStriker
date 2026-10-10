--!strict
--[[
	PetController
	-------------
	Renders every player's equipped pets as local followers (no server parts, no
	replication cost). The server mirrors equipped pet catalogue ids to the Player
	attribute "EquippedPetIds"; this controller rebuilds followers when it changes and
	moves them every frame with frame-rate independent smoothing. Walkers hop along
	behind their owner, the Golden Eagle hovers above. Owners far from the camera are
	skipped entirely.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Tags = require(ReplicatedStorage.Source.Shared.Tags)
local PetModels = require(script.Parent.Parent.Modules.PetModels)

type Follower = {
	Model: Model,
	Flying: boolean,
	Phase: number,
	Current: CFrame?,
	Shown: boolean,
}

type OwnerView = {
	Player: Player,
	Key: string,
	Followers: { Follower },
}

local UPDATE_DISTANCE = 220
local FOLLOW_SHARPNESS = 9

local PetController = {}

local owners: { [Player]: OwnerView } = {}
local folder: Folder

local function clearFollowers(view: OwnerView)
	for _, follower in view.Followers do
		follower.Model:Destroy()
	end
	table.clear(view.Followers)
end

local function rebuild(view: OwnerView)
	local raw = view.Player:GetAttribute("EquippedPetIds")
	local key = if type(raw) == "string" then raw else ""
	if key == view.Key then
		return
	end
	view.Key = key
	clearFollowers(view)
	for index, petId in string.split(key, ",") do
		if petId == "" then
			continue
		end
		local model = PetModels.Build(petId)
		if model then
			-- Parented only once it has been placed next to its owner (see setShown).
			model:AddTag(Tags.ChronoPet)
			table.insert(view.Followers, {
				Model = model,
				Flying = PetModels.IsFlying(petId),
				Phase = index * 1.7,
				Current = nil,
				Shown = false,
			})
		end
	end
end

local function watch(player: Player)
	local view: OwnerView = { Player = player, Key = "\0", Followers = {} }
	owners[player] = view
	rebuild(view)
	player:GetAttributeChangedSignal("EquippedPetIds"):Connect(function()
		rebuild(view)
	end)
end

local function unwatch(player: Player)
	local view = owners[player]
	if view then
		clearFollowers(view)
		owners[player] = nil
	end
end

-- Followers are only in the world while their owner is present and nearby.
local function setShown(view: OwnerView, shown: boolean)
	for _, follower in view.Followers do
		if follower.Shown ~= shown then
			follower.Shown = shown
			follower.Current = nil
			follower.Model.Parent = if shown then folder else nil
		end
	end
end

local function stepOwner(view: OwnerView, now: number, alpha: number, cameraPosition: Vector3)
	local character = view.Player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if root == nil or not root:IsA("BasePart") or humanoid == nil then
		setShown(view, false)
		return
	end
	if (root.Position - cameraPosition).Magnitude > UPDATE_DISTANCE then
		setShown(view, false)
		return
	end
	local count = #view.Followers
	local floorY = root.Position.Y - (humanoid.HipHeight + root.Size.Y / 2)
	local moving = humanoid.MoveDirection.Magnitude > 0.1
	local facing = root.CFrame - root.CFrame.Position

	for index, follower in view.Followers do
		local spread = (index - (count + 1) / 2) * 0.75
		local offset = Vector3.new(math.sin(spread) * 4.5, 0, 3.5 + math.cos(spread) * 1.2)
		local anchor = root.CFrame:PointToWorldSpace(offset)
		local height: number
		if follower.Flying then
			height = root.Position.Y + 2.5 + math.sin(now * 2.4 + follower.Phase) * 0.45
		else
			local hop = if moving then math.abs(math.sin(now * 9 + follower.Phase)) * 0.6 else 0
			height = floorY + 1.1 + hop
		end
		local target = CFrame.new(anchor.X, height, anchor.Z) * facing
		local current = follower.Current
		local nextFrame = if current then current:Lerp(target, alpha) else target
		follower.Current = nextFrame
		follower.Model:PivotTo(nextFrame)
		if not follower.Shown then
			follower.Shown = true
			follower.Model.Parent = folder
		end
	end
end

function PetController.Init()
	local created = Instance.new("Folder")
	created.Name = "ChronoPets"
	created.Parent = workspace
	folder = created
end

function PetController.Start()
	for _, player in Players:GetPlayers() do
		watch(player)
	end
	Players.PlayerAdded:Connect(watch)
	Players.PlayerRemoving:Connect(unwatch)

	RunService.RenderStepped:Connect(function(deltaTime: number)
		local camera = workspace.CurrentCamera
		local cameraPosition = if camera then camera.CFrame.Position else Vector3.zero
		local alpha = 1 - math.exp(-FOLLOW_SHARPNESS * deltaTime)
		local now = os.clock()
		for _, view in owners do
			stepOwner(view, now, alpha, cameraPosition)
		end
	end)
end

return PetController
