--!strict
-- R15 Ragdoll System (Server)
-- Pre-sets up ragdoll constraints on character spawn for reliable ragdoll/unragdoll
-- Uses BoolValue trigger for simple state management

local Players = game:GetService("Players")
local PhysicsService = game:GetService("PhysicsService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Create collision group for ragdolled players
pcall(function()
	PhysicsService:RegisterCollisionGroup("Ragdoll")
	PhysicsService:CollisionGroupSetCollidable("Ragdoll", "Ragdoll", false)
	PhysicsService:CollisionGroupSetCollidable("Ragdoll", "Players", false)
end)

-- R15 Joint configurations for BallSocketConstraints
local JOINT_CONFIG = {
	Root = { maxAngle = 10, twistLower = -10, twistUpper = 10 },
	Waist = { maxAngle = 20, twistLower = -20, twistUpper = 20 },
	Neck = { maxAngle = 30, twistLower = -30, twistUpper = 30 },
	LeftShoulder = { maxAngle = 80, twistLower = -80, twistUpper = 80 },
	RightShoulder = { maxAngle = 80, twistLower = -80, twistUpper = 80 },
	LeftElbow = { maxAngle = 10, twistLower = -90, twistUpper = 10 },
	RightElbow = { maxAngle = 10, twistLower = -90, twistUpper = 10 },
	LeftWrist = { maxAngle = 20, twistLower = -20, twistUpper = 20 },
	RightWrist = { maxAngle = 20, twistLower = -20, twistUpper = 20 },
	LeftHip = { maxAngle = 60, twistLower = -60, twistUpper = 60 },
	RightHip = { maxAngle = 60, twistLower = -60, twistUpper = 60 },
	LeftKnee = { maxAngle = 10, twistLower = -90, twistUpper = 10 },
	RightKnee = { maxAngle = 10, twistLower = -90, twistUpper = 10 },
	LeftAnkle = { maxAngle = 20, twistLower = -20, twistUpper = 20 },
	RightAnkle = { maxAngle = 20, twistLower = -20, twistUpper = 20 },
}

local DEFAULT_CONFIG = { maxAngle = 30, twistLower = -30, twistUpper = 30 }

-- Setup ragdoll constraints on a character (called once on spawn)
local function setupRagdoll(character: Model)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then return end

	-- Prevent death from breaking joints
	humanoid.BreakJointsOnDeath = false
	humanoid.RequiresNeck = false

	-- Create folder for ragdoll constraints
	local constraintsFolder = Instance.new("Folder")
	constraintsFolder.Name = "RagdollConstraints"

	-- Create folder to store motor references
	local motorsFolder = Instance.new("Folder")
	motorsFolder.Name = "Motors"
	motorsFolder.Parent = constraintsFolder

	-- Find all Motor6Ds and create constraints for them
	for _, motor in ipairs(character:GetDescendants()) do
		if motor:IsA("Motor6D") and motor.Part0 and motor.Part1 then
			-- Store motor reference
			local motorRef = Instance.new("ObjectValue")
			motorRef.Name = motor.Name
			motorRef.Value = motor
			motorRef.Parent = motorsFolder

			-- Create attachment on Part0
			local att0 = Instance.new("Attachment")
			att0.Name = motor.Name .. "_Att0"
			att0.CFrame = motor.C0
			att0.Parent = motor.Part0

			-- Create attachment on Part1
			local att1 = Instance.new("Attachment")
			att1.Name = motor.Name .. "_Att1"
			att1.CFrame = motor.C1
			att1.Parent = motor.Part1

			-- Create BallSocketConstraint
			local config = JOINT_CONFIG[motor.Name] or DEFAULT_CONFIG
			local constraint = Instance.new("BallSocketConstraint")
			constraint.Name = motor.Name .. "_Constraint"
			constraint.Attachment0 = att0
			constraint.Attachment1 = att1
			constraint.LimitsEnabled = true
			constraint.TwistLimitsEnabled = true
			constraint.UpperAngle = config.maxAngle
			constraint.TwistLowerAngle = config.twistLower
			constraint.TwistUpperAngle = config.twistUpper
			constraint.MaxFrictionTorque = 50
			constraint.Enabled = false -- Start disabled
			constraint.Parent = constraintsFolder
		end
	end

	constraintsFolder.Parent = character

	-- Create ragdoll trigger
	local trigger = Instance.new("BoolValue")
	trigger.Name = "RagdollTrigger"
	trigger.Value = false
	trigger.Parent = character

	-- Handle trigger changes
	trigger.Changed:Connect(function(isRagdolled)
		if isRagdolled then
			-- Enable ragdoll
			humanoid:ChangeState(Enum.HumanoidStateType.Physics)
			humanoid.AutoRotate = false

			-- Disable motors, enable constraints
			for _, motorRef in ipairs(motorsFolder:GetChildren()) do
				if motorRef:IsA("ObjectValue") and motorRef.Value then
					motorRef.Value.Enabled = false
				end
			end

			for _, constraint in ipairs(constraintsFolder:GetChildren()) do
				if constraint:IsA("BallSocketConstraint") then
					constraint.Enabled = true
				end
			end

			-- Set collision group
			for _, part in ipairs(character:GetDescendants()) do
				if part:IsA("BasePart") then
					part.CanCollide = true
					part.CollisionGroup = "Ragdoll"
				end
			end
		else
			-- Disable ragdoll
			-- Enable motors, disable constraints
			for _, motorRef in ipairs(motorsFolder:GetChildren()) do
				if motorRef:IsA("ObjectValue") and motorRef.Value then
					motorRef.Value.Enabled = true
				end
			end

			for _, constraint in ipairs(constraintsFolder:GetChildren()) do
				if constraint:IsA("BallSocketConstraint") then
					constraint.Enabled = false
				end
			end

			-- Clear velocities
			for _, part in ipairs(character:GetDescendants()) do
				if part:IsA("BasePart") then
					part.AssemblyLinearVelocity = Vector3.zero
					part.AssemblyAngularVelocity = Vector3.zero
					part.CollisionGroup = "Players"
				end
			end

			-- Reset to upright
			local rootPart = character:FindFirstChild("HumanoidRootPart")
			if rootPart then
				local pos = rootPart.Position
				rootPart.CFrame = CFrame.new(pos + Vector3.new(0, 0.5, 0))
			end

			-- Restore humanoid
			humanoid.AutoRotate = true
			humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)

			task.delay(0.1, function()
				if humanoid and humanoid.Parent then
					humanoid:ChangeState(Enum.HumanoidStateType.Running)
				end
			end)
		end
	end)

	print(`[RagdollSystem] Setup complete for {character.Name}`)
end

-- Handle player characters
Players.PlayerAdded:Connect(function(player)
	player.CharacterAdded:Connect(function(character)
		-- Wait for humanoid
		local humanoid = character:WaitForChild("Humanoid", 5)
		if humanoid then
			-- Small delay to ensure all parts are loaded
			task.wait(0.1)
			setupRagdoll(character)
		end
	end)

	-- Setup existing character
	if player.Character then
		local humanoid = player.Character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			setupRagdoll(player.Character)
		end
	end
end)

-- Handle existing players
for _, player in ipairs(Players:GetPlayers()) do
	if player.Character then
		local humanoid = player.Character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			setupRagdoll(player.Character)
		end
	end

	player.CharacterAdded:Connect(function(character)
		local humanoid = character:WaitForChild("Humanoid", 5)
		if humanoid then
			task.wait(0.1)
			setupRagdoll(character)
		end
	end)
end

print("[RagdollSystem] Server initialized")
