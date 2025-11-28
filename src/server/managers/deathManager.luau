--!strict
-- Death Manager (Server)
-- Handles knockdown system: when HP reaches 0, player ragdolls for 6 seconds then gets back up
-- No actual death occurs - player recovers after the knockdown timer

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Configuration
local KNOCKDOWN_DURATION = 6.0 -- Seconds before getting back up
local MIN_KNOCKDOWN_HP = 1 -- Minimum HP while knocked down (prevents death)

-- Remote events
local knockdownRemote: RemoteEvent = nil

local DeathManager = {}
DeathManager.__index = DeathManager

function DeathManager.new()
	local self = setmetatable({}, DeathManager)

	self._connections = {} :: { RBXScriptConnection }
	self._knockedPlayers = {} :: { [Player]: boolean } -- Track players currently knocked down
	self._knockdownTimers = {} :: { [Player]: thread } -- Track knockdown timer threads
	self._knockdownHealthConnections = {} :: { [Player]: RBXScriptConnection } -- Health protection while knocked

	self:_setup()

	print("[DeathManager] Initialized (Knockdown System)")
	return self
end

function DeathManager:_setup()
	-- Create knockdown remote if it doesn't exist
	knockdownRemote = ReplicatedStorage:FindFirstChild("PlayerKnockdown") :: RemoteEvent
	if not knockdownRemote then
		knockdownRemote = Instance.new("RemoteEvent")
		knockdownRemote.Name = "PlayerKnockdown"
		knockdownRemote.Parent = ReplicatedStorage
	end

	-- Initialize for existing players
	for _, player in ipairs(Players:GetPlayers()) do
		if player.Character then
			self:_setupCharacter(player, player.Character)
		end
	end

	-- Handle new players
	table.insert(
		self._connections,
		Players.PlayerAdded:Connect(function(player)
			player.CharacterAdded:Connect(function(character)
				self:_setupCharacter(player, character)
			end)
		end)
	)

	-- Handle existing players' future characters
	for _, player in ipairs(Players:GetPlayers()) do
		table.insert(
			self._connections,
			player.CharacterAdded:Connect(function(character)
				self:_setupCharacter(player, character)
			end)
		)
	end
end

function DeathManager:_setupCharacter(player: Player, character: Model)
	local humanoid = character:WaitForChild("Humanoid", 5) :: Humanoid?
	if not humanoid then
		warn(`[DeathManager] Humanoid not found for {player.Name}`)
		return
	end

	-- Disable BreakJointsOnDeath so we can handle knockdown instead
	humanoid.BreakJointsOnDeath = false

	-- Listen for health changes to intercept "death"
	humanoid.HealthChanged:Connect(function(newHealth)
		-- When health reaches 0 or below, trigger knockdown instead of death
		if newHealth <= 0 and not self._knockedPlayers[player] then
			self:_handleKnockdown(player, character, humanoid)
		end
	end)
end

function DeathManager:_handleKnockdown(player: Player, character: Model, humanoid: Humanoid)
	-- Prevent double-handling
	if self._knockedPlayers[player] then
		return
	end
	self._knockedPlayers[player] = true

	print(`[DeathManager] {player.Name} knocked down`)

	-- CRITICAL: Keep player alive by setting HP to minimum
	humanoid.Health = MIN_KNOCKDOWN_HP

	-- Set ragdoll properties on SERVER
	humanoid.PlatformStand = true
	humanoid.AutoRotate = false
	humanoid:SetStateEnabled(Enum.HumanoidStateType.GettingUp, false)
	humanoid:ChangeState(Enum.HumanoidStateType.Physics)

	-- Lock movement
	humanoid.WalkSpeed = 0
	humanoid.JumpPower = 0
	humanoid.JumpHeight = 0

	-- Enable ragdoll physics
	self:_enableRagdoll(character)

	-- Fire knockdown event to all clients (for any client-side effects)
	knockdownRemote:FireAllClients(character, true)

	-- Setup health protection while knocked down
	-- If player takes damage while knocked, reset timer and keep HP at minimum
	self._knockdownHealthConnections[player] = humanoid.HealthChanged:Connect(function(newHealth)
		if not self._knockedPlayers[player] then
			return
		end

		-- Prevent death while knocked down - always keep at minimum HP
		if newHealth < MIN_KNOCKDOWN_HP then
			humanoid.Health = MIN_KNOCKDOWN_HP
			print(`[DeathManager] {player.Name} hit while knocked - HP protected`)

			-- Reset the knockdown timer (they got hit, restart the countdown)
			if self._knockdownTimers[player] then
				task.cancel(self._knockdownTimers[player])
			end
			self._knockdownTimers[player] = task.delay(KNOCKDOWN_DURATION, function()
				self:_handleRecovery(player, character, humanoid)
			end)
			print(`[DeathManager] {player.Name} knockdown timer reset to {KNOCKDOWN_DURATION}s`)
		end
	end)

	-- Start recovery timer
	self._knockdownTimers[player] = task.delay(KNOCKDOWN_DURATION, function()
		self:_handleRecovery(player, character, humanoid)
	end)
end

function DeathManager:_handleRecovery(player: Player, character: Model, humanoid: Humanoid)
	-- Disconnect health protection first
	if self._knockdownHealthConnections[player] then
		self._knockdownHealthConnections[player]:Disconnect()
		self._knockdownHealthConnections[player] = nil
	end

	-- Check if player/character still exists
	if not player or not player.Parent then
		self._knockedPlayers[player] = nil
		self._knockdownTimers[player] = nil
		return
	end

	if not character or not character.Parent then
		self._knockedPlayers[player] = nil
		self._knockdownTimers[player] = nil
		return
	end

	if not humanoid or humanoid.Health <= 0 then
		self._knockedPlayers[player] = nil
		self._knockdownTimers[player] = nil
		return
	end

	print(`[DeathManager] {player.Name} recovering from knockdown`)

	-- Get the HumanoidRootPart for positioning
	local rootPart = character:FindFirstChild("HumanoidRootPart") :: BasePart?

	-- Clear all velocities BEFORE disabling ragdoll to prevent flinging
	for _, part in ipairs(character:GetDescendants()) do
		if part:IsA("BasePart") then
			part.AssemblyLinearVelocity = Vector3.zero
			part.AssemblyAngularVelocity = Vector3.zero
		end
	end

	-- Disable ragdoll FIRST
	self:_disableRagdoll(character)

	-- Reset HumanoidRootPart to upright position (keep XZ position, reset rotation)
	if rootPart then
		local currentPos = rootPart.Position
		-- Set upright CFrame - keep position, remove all rotation
		rootPart.CFrame = CFrame.new(currentPos) * CFrame.new(0, 0.5, 0) -- Slight lift to prevent clipping
	end

	-- Clear velocities AGAIN after repositioning
	for _, part in ipairs(character:GetDescendants()) do
		if part:IsA("BasePart") then
			part.AssemblyLinearVelocity = Vector3.zero
			part.AssemblyAngularVelocity = Vector3.zero
		end
	end

	-- Restore humanoid properties
	humanoid.PlatformStand = false
	humanoid.AutoRotate = true
	humanoid:SetStateEnabled(Enum.HumanoidStateType.GettingUp, true)

	-- Force to running state
	humanoid:ChangeState(Enum.HumanoidStateType.Running)

	-- Restore movement
	humanoid.WalkSpeed = 16 -- Default walk speed
	humanoid.JumpPower = 50 -- Default jump power
	humanoid.JumpHeight = 7.2 -- Default jump height

	-- NO HP restoration - player keeps their current HP (minimum knockdown HP)
	-- They got knocked down, they don't get rewarded with health

	-- Fire recovery event to all clients
	knockdownRemote:FireAllClients(character, false)

	-- Clear knockdown state
	self._knockedPlayers[player] = nil
	self._knockdownTimers[player] = nil

	print(`[DeathManager] {player.Name} recovered (HP: {humanoid.Health}/{humanoid.MaxHealth})`)
end

-- Enable ragdoll physics by disabling Motor6Ds and creating constraints
function DeathManager:_enableRagdoll(character: Model)
	-- Joint-specific constraint settings to prevent crazy limb rotation
	local jointSettings = {
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
	local defaultSettings = { upperAngle = 15, twistLower = -15, twistUpper = 15 }

	-- Ensure all body parts have collision enabled and proper collision group
	-- Remove from "Players" collision group temporarily so limbs collide with ground
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
				local settings = jointSettings[motor.Name] or defaultSettings

				-- Create ball socket constraint with tighter limits and HIGH FRICTION to prevent spasms
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

	-- Apply gentle trip impulse to knock them over
	local upperTorso = character:FindFirstChild("UpperTorso") :: BasePart?
	local rootPart = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local targetPart = upperTorso or rootPart

	if targetPart then
		-- Random direction for natural-looking fall
		local tripDirection = Vector3.new(
			math.random() - 0.5,
			0,
			math.random() - 0.5
		).Unit

		-- Gentle angular impulse to make them tip over
		targetPart:ApplyAngularImpulse(tripDirection * 20)

		-- Gentle linear impulse to push them down
		targetPart:ApplyImpulse(Vector3.new(0, -15, 0) + tripDirection * 10)
	end

	print("[DeathManager] Ragdoll enabled")
end

-- Disable ragdoll and restore Motor6Ds
function DeathManager:_disableRagdoll(character: Model)
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

	-- Restore collision group to "Players" so player-player collision is disabled again
	for _, part in ipairs(character:GetDescendants()) do
		if part:IsA("BasePart") then
			part.CollisionGroup = "Players"
		end
	end

	print("[DeathManager] Ragdoll disabled")
end

-- Check if a player is currently knocked down
function DeathManager:isKnockedDown(player: Player): boolean
	return self._knockedPlayers[player] == true
end

function DeathManager:destroy()
	-- Cancel all knockdown timers
	for _, timerThread in pairs(self._knockdownTimers) do
		task.cancel(timerThread)
	end
	self._knockdownTimers = {}
	self._knockedPlayers = {}

	-- Disconnect all health protection connections
	for _, connection in pairs(self._knockdownHealthConnections) do
		connection:Disconnect()
	end
	self._knockdownHealthConnections = {}

	for _, connection in ipairs(self._connections) do
		connection:Disconnect()
	end
	self._connections = {}
end

return DeathManager
