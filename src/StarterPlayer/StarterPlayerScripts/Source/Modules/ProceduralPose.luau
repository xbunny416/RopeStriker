--!strict
--[[
	ProceduralPose
	--------------
	Code-driven stand-ins for the authored R15 animations (Bible §4.2) so the game reads
	correctly before the Blender/Animation Editor exports are uploaded. Each pose writes
	Motor6D.Transform and must therefore run in RunService.PreSimulation (after the
	Animator, before physics). Transform is local-only, so every client applies these
	poses to every visible character from the replicated "RopeState" attribute.

	  JumpRope    - arms out, hands circling in sync with the rope orbit.
	  GroundLash  - 0.35s right-to-left downward diagonal whip crack.
	  AirSweep    - 0.45s 360-degree horizontal spin with the arms extended.

	Poses are only applied when the matching GameConfig.Animations id is empty. R6 rigs
	are skipped (their joint frames differ); the rope itself still animates.
]]

export type Joints = {
	RightShoulder: Motor6D?,
	LeftShoulder: Motor6D?,
	Root: Motor6D?,
}

local ProceduralPose = {}

local function motor(character: Model, partName: string, jointName: string): Motor6D?
	local part = character:FindFirstChild(partName)
	local joint = part and part:FindFirstChild(jointName)
	if joint and joint:IsA("Motor6D") then
		return joint
	end
	return nil
end

function ProceduralPose.FindJoints(character: Model): Joints
	return {
		RightShoulder = motor(character, "RightUpperArm", "RightShoulder"),
		LeftShoulder = motor(character, "LeftUpperArm", "LeftShoulder"),
		Root = motor(character, "LowerTorso", "Root"),
	}
end

local function set(joint: Motor6D?, transform: CFrame)
	if joint and joint.Parent then
		joint.Transform = transform
	end
end

local function easeOutCubic(t: number): number
	local inverse = 1 - math.clamp(t, 0, 1)
	return 1 - inverse * inverse * inverse
end

local function easeInOutSine(t: number): number
	return -(math.cos(math.pi * math.clamp(t, 0, 1)) - 1) / 2
end

-- `ropeAngle` is Rhythm.RopeAngle(): the hands trace small circles with the rope.
function ProceduralPose.JumpRope(joints: Joints, ropeAngle: number)
	local swing = 0.3 + 0.22 * math.sin(ropeAngle)
	local spread = 0.38 + 0.1 * math.cos(ropeAngle)
	set(joints.RightShoulder, CFrame.Angles(swing, 0, spread))
	set(joints.LeftShoulder, CFrame.Angles(swing, 0, -spread))
end

-- t in [0, 1] across the 0.35s attack.
function ProceduralPose.GroundLash(joints: Joints, t: number)
	local strike = easeOutCubic(t * 1.15)
	local raise = 2.7 - 2.3 * strike -- overhead -> forward-down
	local across = 0.65 - 1.1 * strike -- starts out to the right, finishes across the body
	local twist = 0.5 - 1.0 * strike
	set(joints.RightShoulder, CFrame.Angles(raise, twist, across))
	set(joints.LeftShoulder, CFrame.Angles(0.35, 0, -0.25))
end

-- t in [0, 1] across the 0.45s attack.
function ProceduralPose.AirSweep(joints: Joints, t: number)
	local yaw = math.pi * 2 * easeInOutSine(t)
	set(joints.Root, CFrame.Angles(0, yaw, 0))
	set(joints.RightShoulder, CFrame.Angles(0.15, 0, 1.45))
	set(joints.LeftShoulder, CFrame.Angles(0.15, 0, -1.45))
end

-- Yaw (radians) the body has spun at time t of an Aerial Sweep; ropes follow it.
function ProceduralPose.AirSweepYaw(t: number): number
	return math.pi * 2 * easeInOutSine(t)
end

return ProceduralPose
