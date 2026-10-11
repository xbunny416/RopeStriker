--!strict
--[[
	BeamCurve
	---------
	Drives a Beam along an arbitrary cubic Bezier p0 -> p3 with control points p1, p2.

	A Beam's curve is the Bezier (A0, A0 + A0.Axis * CurveSize0, A1 - A1.Axis * CurveSize1, A1),
	where Axis is each attachment's world X axis. We keep both attachments where they are
	(on the rope handles) and only re-orient them each frame, so the rope can orbit the
	body (jump rope), whip forward (Ground Lash) or spin outward (Aerial Sweep).
]]

local BeamCurve = {}

local function frameWithXAxis(position: Vector3, xAxis: Vector3): CFrame
	local up = if math.abs(xAxis.Y) > 0.98 then Vector3.zAxis else Vector3.yAxis
	local yAxis = (up - xAxis * up:Dot(xAxis)).Unit
	return CFrame.fromMatrix(position, xAxis, yAxis)
end

local function setWorldFrame(attachment: Attachment, worldFrame: CFrame)
	local parent = attachment.Parent
	if parent and parent:IsA("BasePart") then
		attachment.CFrame = parent.CFrame:ToObjectSpace(worldFrame)
	end
end

function BeamCurve.Apply(
	beam: Beam,
	attachment0: Attachment,
	attachment1: Attachment,
	p0: Vector3,
	p1: Vector3,
	p2: Vector3,
	p3: Vector3
)
	local fallback = p3 - p0
	if fallback.Magnitude < 1e-4 then
		fallback = Vector3.xAxis
	end

	local leg0 = p1 - p0
	local leg1 = p2 - p3
	local axis0 = if leg0.Magnitude > 1e-4 then leg0.Unit else fallback.Unit
	local axis1 = if leg1.Magnitude > 1e-4 then leg1.Unit else -fallback.Unit

	setWorldFrame(attachment0, frameWithXAxis(p0, axis0))
	setWorldFrame(attachment1, frameWithXAxis(p3, axis1))
	beam.CurveSize0 = leg0.Magnitude
	beam.CurveSize1 = -leg1.Magnitude
end

-- Point on the cubic Bezier at t in [0, 1].
function BeamCurve.Point(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, t: number): Vector3
	local u = 1 - t
	return p0 * (u * u * u) + p1 * (3 * u * u * t) + p2 * (3 * u * t * t) + p3 * (t * t * t)
end

return BeamCurve
