--!strict
-- EasyRagdoll Module
-- Standalone ragdoll utility for easy character ragdolling
-- Usage: EasyRagdoll.SetRagdoll(character, true, true, 100) -- Enable with trip
-- Usage: EasyRagdoll.SetRagdoll(character, false) -- Disable

local EasyRagdoll = {}

-- Joint-specific constraint settings to prevent crazy limb rotation
local JOINT_SETTINGS = {
	-- Neck - very limited movement
	Neck = { upperAngle = 10, twistLower = -10, twistUpper = 10 },
	-- Shoulders - moderate movement
	RightShoulder = { upperAngle = 20, twistLower = -20, twistUpper = 20 },
	LeftShoulder = { upperAngle = 20, twistLower = -20, twistUpper = 20 },
	-- Elbows - hinge-like, limited twist
	RightElbow = { upperAngle = 10, twistLower = -5, twistUpper = 60 },
	LeftElbow = { upperAngle = 10, twistLower = -5, twistUpper = 60 },
	-- Wrists - limited
	RightWrist = { upperAngle = 10, twistLower = -10, twistUpper = 10 },
	LeftWrist = { upperAngle = 10, twistLower = -10, twistUpper = 10 },
	-- Waist/Root - moderate
	Waist = { upperAngle = 15, twistLower = -15, twistUpper = 15 },
	Root = { upperAngle = 10, twistLower = -10, twistUpper = 10 },
	-- Hips - moderate movement
	RightHip = { upperAngle = 20, twistLower = -20, twistUpper = 20 },
	LeftHip = { upperAngle = 20, twistLower = -20, twistUpper = 20 },
	-- Knees - hinge-like
	RightKnee = { upperAngle = 10, twistLower = -5, twistUpper = 60 },
	LeftKnee = { upperAngle = 10, twistLower = -5, twistUpper = 60 },
	-- Ankles - limited
	RightAnkle = { upperAngle = 10, twistLower = -10, twistUpper = 10 },
	LeftAnkle = { upperAngle = 10, twistLower = -10, twistUpper = 10 },
}

-- Default settings for any joint not in the list
local DEFAULT_SETTINGS = { upperAngle = 15, twistLower = -15, twistUpper = 15 }

-- Enable ragdoll physics on a character
local function enableRagdoll(character: Model, tripEnabled: boolean?, tripForce: number?)
	local shouldTrip = tripEnabled ~= false -- Default to true
	local force = tripForce or 100

	-- Ensure all body parts have collision enabled
	for _, part in ipairs(character:GetDescendants()) do
		if part:IsA("BasePart") then
			part.CanCollide = true
			-- Reset to Default collision group so limbs collide with terrain
			part.CollisionGroup = "Default"
		end
	end

	-- Disable all Motor6Ds and create ball socket constraints
	for _, motor in ipairs(character:GetDescendants()) do
		if motor:IsA("Motor6D") then
			local part0 = motor.Part0
			local part1 = motor.Part1

			if part0 and part1 then
				-- Disable the motor (don't destroy - need to restore later)
				motor.Enabled = false

				-- Create attachment on part0
				local attachment0 = Instance.new("Attachment")
				attachment0.Name = "RagdollAttachment0"
				attachment0.CFrame = motor.C0
				attachment0.Parent = part0

				-- Create attachment on part1
				local attachment1 = Instance.new("Attachment")
				attachment1.Name = "RagdollAttachment1"
				attachment1.CFrame = motor.C1
				attachment1.Parent = part1

				-- Get joint-specific settings
				local settings = JOINT_SETTINGS[motor.Name] or DEFAULT_SETTINGS

				-- Create ball socket constraint with limits and HIGH FRICTION to prevent spasms
				local constraint = Instance.new("BallSocketConstraint")
				constraint.Name = "RagdollConstraint"
				constraint.Attachment0 = attachment0
				constraint.Attachment1 = attachment1
				constraint.LimitsEnabled = true
				constraint.TwistLimitsEnabled = true
				constraint.UpperAngle = settings.upperAngle
				constraint.TwistLowerAngle = settings.twistLower
				constraint.TwistUpperAngle = settings.twistUpper
				-- HIGH friction torque to dampen joint movement and prevent spasms
				constraint.MaxFrictionTorque = 500
				constraint.Parent = part0
			end
		end
	end

	-- Set humanoid properties
	local humanoid = character:FindFirstChild("Humanoid") :: Humanoid?
	if humanoid then
		humanoid.PlatformStand = true
		humanoid.AutoRotate = false
		humanoid:SetStateEnabled(Enum.HumanoidStateType.GettingUp, false)
		humanoid:ChangeState(Enum.HumanoidStateType.Physics)
	end

	-- Apply trip to knock them over if enabled
	if shouldTrip then
		local rootPart = character:FindFirstChild("HumanoidRootPart") :: BasePart?

		if rootPart then
			-- Random fall direction (horizontal)
			local fallDirection = Vector3.new(
				math.random() - 0.5,
				0,
				math.random() - 0.5
			).Unit

			-- Calculate rotation axis (perpendicular to fall direction, horizontal)
			local rotationAxis = Vector3.new(0, 1, 0):Cross(fallDirection).Unit

			-- DIRECTLY TILT the root CFrame to put them off-balance BEFORE physics kicks in
			local currentCFrame = rootPart.CFrame
			local tiltAngle = math.rad(50) -- 50 degree tilt
			local tiltRotation = CFrame.fromAxisAngle(rotationAxis, tiltAngle)
			rootPart.CFrame = CFrame.new(currentCFrame.Position) * tiltRotation * currentCFrame.Rotation

			-- Wait for physics to initialize
			task.wait()

			-- Scale velocity based on force parameter
			local forceMultiplier = force / 100
			rootPart.AssemblyAngularVelocity = rotationAxis * (5 * forceMultiplier)
			rootPart.AssemblyLinearVelocity = fallDirection * (10 * forceMultiplier) + Vector3.new(0, -5, 0)
		end
	end
end

-- Disable ragdoll and restore Motor6Ds
local function disableRagdoll(character: Model)
	-- Remove all ragdoll constraints and attachments
	for _, obj in ipairs(character:GetDescendants()) do
		if obj.Name == "RagdollConstraint" or obj.Name == "RagdollAttachment0" or obj.Name == "RagdollAttachment1" then
			obj:Destroy()
		end
	end

	-- Re-enable all Motor6Ds
	for _, motor in ipairs(character:GetDescendants()) do
		if motor:IsA("Motor6D") then
			motor.Enabled = true
		end
	end

	-- Clear all velocities to prevent flinging
	for _, part in ipairs(character:GetDescendants()) do
		if part:IsA("BasePart") then
			part.AssemblyLinearVelocity = Vector3.zero
			part.AssemblyAngularVelocity = Vector3.zero
			-- Restore collision group to "Players"
			part.CollisionGroup = "Players"
		end
	end

	-- Restore humanoid properties
	local humanoid = character:FindFirstChild("Humanoid") :: Humanoid?
	if humanoid then
		humanoid.PlatformStand = false
		humanoid.AutoRotate = true
		humanoid:SetStateEnabled(Enum.HumanoidStateType.GettingUp, true)
		humanoid:ChangeState(Enum.HumanoidStateType.Running)
	end

	-- Reset HumanoidRootPart to upright position
	local rootPart = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if rootPart then
		local currentPos = rootPart.Position
		-- Set upright CFrame - keep position, remove all rotation
		rootPart.CFrame = CFrame.new(currentPos) * CFrame.new(0, 0.5, 0) -- Slight lift to prevent clipping
	end
end

-- Main API function
-- SetRagdoll(character, enabled, tripEnabled?, tripForce?)
-- character: The character model to ragdoll
-- enabled: true to enable ragdoll, false to disable
-- tripEnabled: (optional) true to apply trip force when enabling, default true
-- tripForce: (optional) force multiplier for trip (100 = normal, 200 = double), default 100
function EasyRagdoll.SetRagdoll(character: Model, enabled: boolean, tripEnabled: boolean?, tripForce: number?)
	if not character then
		warn("[EasyRagdoll] No character provided")
		return
	end

	if enabled then
		enableRagdoll(character, tripEnabled, tripForce)
	else
		disableRagdoll(character)
	end
end

-- Check if a character is currently ragdolled
function EasyRagdoll.IsRagdolled(character: Model): boolean
	if not character then
		return false
	end

	-- Check if any ragdoll constraints exist
	for _, obj in ipairs(character:GetDescendants()) do
		if obj.Name == "RagdollConstraint" then
			return true
		end
	end

	return false
end

return EasyRagdoll
