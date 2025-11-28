--!strict
-- Death Effects Manager (Client)
-- Handles ragdoll, screen fade, and death SFX
-- Deepwoken-style death sequence

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local SoundService = game:GetService("SoundService")

-- Configuration
local FADE_COLOR = Color3.new(0, 0, 0)
local FADE_DURATION = 1.5 -- Time to fade to black
local HOLD_DURATION = 1.0 -- Time to hold black screen
local FADE_IN_DURATION = 0.5 -- Time to fade back in after respawn

-- Death sound (placeholder ID - replace with actual asset)
local DEATH_SOUND_ID = "rbxassetid://0" -- TODO: Add actual death sound

local DeathEffectsManager = {}
DeathEffectsManager.__index = DeathEffectsManager

function DeathEffectsManager.new()
	local self = setmetatable({}, DeathEffectsManager)

	self.player = Players.LocalPlayer
	self.fadeFrame = nil :: Frame?
	self.deathRemote = nil :: RemoteEvent?
	self._connections = {} :: { RBXScriptConnection }

	self:_setup()

	print("[DeathEffectsManager] Initialized")
	return self
end

function DeathEffectsManager:_setup()
	-- Create fade UI
	self:_createFadeUI()

	-- Wait for remote event
	self.deathRemote = ReplicatedStorage:WaitForChild("PlayerDeath", 10) :: RemoteEvent?
	if self.deathRemote then
		table.insert(
			self._connections,
			self.deathRemote.OnClientEvent:Connect(function(data)
				self:_handleDeathEvent(data)
			end)
		)
	else
		warn("[DeathEffectsManager] PlayerDeath remote not found")
	end

	-- Listen for respawn to fade back in
	table.insert(
		self._connections,
		self.player.CharacterAdded:Connect(function(_character)
			self:_fadeIn()
		end)
	)
end

function DeathEffectsManager:_createFadeUI()
	local playerGui = self.player:WaitForChild("PlayerGui")

	-- Check if already exists
	local existing = playerGui:FindFirstChild("DeathFadeGui")
	if existing then
		self.fadeFrame = existing:FindFirstChild("FadeFrame") :: Frame?
		return
	end

	-- Create ScreenGui
	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "DeathFadeGui"
	screenGui.IgnoreGuiInset = true
	screenGui.DisplayOrder = 999 -- On top of everything
	screenGui.ResetOnSpawn = false -- Persist through respawn
	screenGui.Parent = playerGui

	-- Create fade frame
	local fadeFrame = Instance.new("Frame")
	fadeFrame.Name = "FadeFrame"
	fadeFrame.Size = UDim2.new(1, 0, 1, 0)
	fadeFrame.Position = UDim2.new(0, 0, 0, 0)
	fadeFrame.BackgroundColor3 = FADE_COLOR
	fadeFrame.BackgroundTransparency = 1 -- Start invisible
	fadeFrame.BorderSizePixel = 0
	fadeFrame.ZIndex = 100
	fadeFrame.Parent = screenGui

	self.fadeFrame = fadeFrame
end

function DeathEffectsManager:_handleDeathEvent(data: any)
	-- Check if this is our local death
	if data.remainingLives ~= nil then
		-- This is our death
		self:_playDeathSequence(data.remainingLives, data.respawnDelay)
	end
end

function DeathEffectsManager:_playDeathSequence(remainingLives: number, respawnDelay: number)
	print(`[DeathEffectsManager] Playing death sequence - {remainingLives} lives remaining`)

	-- Play ragdoll effect
	self:_enableRagdoll()

	-- Play death sound
	self:_playDeathSound()

	-- Start fade to black
	task.delay(0.5, function() -- Short delay before fade starts
		self:_fadeOut()
	end)

	-- Show lives remaining message (optional, can be enhanced later)
	if remainingLives > 0 then
		print(`[DeathEffectsManager] You have {remainingLives} lives remaining`)
	else
		print("[DeathEffectsManager] PERMADEATH - No lives remaining")
	end
end

function DeathEffectsManager:_enableRagdoll()
	local character = self.player.Character
	if not character then
		return
	end

	local humanoid = character:FindFirstChild("Humanoid") :: Humanoid?
	if not humanoid then
		return
	end

	-- CRITICAL: PlatformStand makes the humanoid stop trying to stand up
	humanoid.PlatformStand = true

	-- Disable auto-rotate so character doesn't face camera
	humanoid.AutoRotate = false

	-- Change humanoid state to ragdoll
	humanoid:ChangeState(Enum.HumanoidStateType.Physics)

	-- Disable GettingUp so they stay ragdolled
	humanoid:SetStateEnabled(Enum.HumanoidStateType.GettingUp, false)

	-- Disable all motor6ds to allow physics ragdoll
	for _, motor in ipairs(character:GetDescendants()) do
		if motor:IsA("Motor6D") then
			-- Create a BallSocketConstraint to replace the motor (basic ragdoll)
			local part0 = motor.Part0
			local part1 = motor.Part1

			if part0 and part1 then
				-- Disable the motor
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

				-- Create ball socket constraint
				local constraint = Instance.new("BallSocketConstraint")
				constraint.Name = "RagdollConstraint"
				constraint.Attachment0 = attachment0
				constraint.Attachment1 = attachment1
				constraint.LimitsEnabled = true
				constraint.TwistLimitsEnabled = true
				constraint.UpperAngle = 45
				constraint.TwistLowerAngle = -45
				constraint.TwistUpperAngle = 45
				constraint.Parent = part0
			end
		end
	end

	-- Apply impulse to knock them over (trip them)
	local upperTorso = character:FindFirstChild("UpperTorso") :: BasePart?
	local rootPart = character:FindFirstChild("HumanoidRootPart") :: BasePart?

	-- Use UpperTorso for R15, fallback to HumanoidRootPart
	local targetPart = upperTorso or rootPart
	if targetPart then
		-- Apply angular impulse to make them fall backwards/forwards
		local tripDirection = Vector3.new(
			math.random() - 0.5, -- Slight random X
			0,
			math.random() - 0.5  -- Slight random Z
		).Unit

		-- Angular impulse makes them spin/fall over
		targetPart:ApplyAngularImpulse(tripDirection * 50)

		-- Also apply a small regular impulse to push them
		targetPart:ApplyImpulse(Vector3.new(0, -20, 0) + tripDirection * 30)
	end

	print("[DeathEffectsManager] Ragdoll enabled with trip impulse")
end

function DeathEffectsManager:_playDeathSound()
	-- Skip if no sound ID set
	if DEATH_SOUND_ID == "rbxassetid://0" then
		return
	end

	local sound = Instance.new("Sound")
	sound.SoundId = DEATH_SOUND_ID
	sound.Volume = 0.8
	sound.Parent = SoundService
	sound:Play()

	-- Cleanup after playing
	sound.Ended:Connect(function()
		sound:Destroy()
	end)
end

function DeathEffectsManager:_fadeOut()
	if not self.fadeFrame then
		return
	end

	local tweenInfo = TweenInfo.new(FADE_DURATION, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	local tween = TweenService:Create(self.fadeFrame, tweenInfo, { BackgroundTransparency = 0 })
	tween:Play()

	print("[DeathEffectsManager] Fading to black")
end

function DeathEffectsManager:_fadeIn()
	if not self.fadeFrame then
		return
	end

	-- Ensure we're faded out first
	self.fadeFrame.BackgroundTransparency = 0

	-- Small delay to let new character load
	task.delay(0.2, function()
		local tweenInfo = TweenInfo.new(FADE_IN_DURATION, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		local tween = TweenService:Create(self.fadeFrame, tweenInfo, { BackgroundTransparency = 1 })
		tween:Play()

		print("[DeathEffectsManager] Fading in")
	end)
end

function DeathEffectsManager:destroy()
	for _, connection in ipairs(self._connections) do
		connection:Disconnect()
	end
	self._connections = {}

	if self.fadeFrame and self.fadeFrame.Parent then
		self.fadeFrame.Parent:Destroy()
	end
end

return DeathEffectsManager
