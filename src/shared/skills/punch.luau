--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local WCS = require(ReplicatedStorage.Packages.wcs)

local Punch = WCS.RegisterSkill("Punch")

-- Configuration
local PUNCH_DAMAGE = 10
local PUNCH_RANGE = 8
local PUNCH_COOLDOWN = 0.5

-- Hitstun duration for unarmed attacks
local SOFT_HITSTUN_DURATION = 0.8

function Punch:OnConstructServer()
	-- Setup server-side skill data
	self.hitTargets = {}
end

function Punch:OnConstructClient()
	-- Setup client-side skill data
end

function Punch:OnStartServer()
	-- Check if player is in hitstun by checking the flag
	if self.Character.IsInHitstun then
		print("[Punch] Blocked - Player is in hitstun")
		return
	end

	print("[Punch] Server: Punch activated")

	-- Apply cooldown
	self:ApplyCooldown(PUNCH_COOLDOWN)

	-- Perform hitbox detection
	self:_detectHit()
end

function Punch:OnStartClient()
	print("[Punch] Client: Punch animation triggered")

	-- TODO: Play punch animation
	-- local humanoid = self.Character.Instance:FindFirstChild("Humanoid")
	-- if humanoid then
	-- 	local animator = humanoid:FindFirstChild("Animator")
	-- 	if animator then
	-- 		-- animator:LoadAnimation(punchAnimation):Play()
	-- 	end
	-- end
end

-- Server-only hitbox detection
function Punch:_detectHit()
	if not RunService:IsServer() then
		return
	end

	local character = self.Character.Instance
	local humanoidRootPart = character:FindFirstChild("HumanoidRootPart")

	if not humanoidRootPart then
		warn("[Punch] HumanoidRootPart not found")
		return
	end

	-- Get all potential targets in range
	local origin = humanoidRootPart.Position
	local lookDirection = humanoidRootPart.CFrame.LookVector

	-- Find all characters in workspace
	for _, potentialTarget in ipairs(workspace:GetChildren()) do
		if potentialTarget:IsA("Model") and potentialTarget ~= character then
			local targetHumanoid = potentialTarget:FindFirstChild("Humanoid")
			local targetRootPart = potentialTarget:FindFirstChild("HumanoidRootPart")

			if targetHumanoid and targetHumanoid.Health > 0 and targetRootPart then
				-- Check if target is in range
				local distance = (targetRootPart.Position - origin).Magnitude

				if distance <= PUNCH_RANGE then
					-- Check if target is in front of attacker
					local directionToTarget = (targetRootPart.Position - origin).Unit
					local dotProduct = lookDirection:Dot(directionToTarget)

					-- If dot product > 0.5, target is roughly in front (within ~60 degrees)
					if dotProduct > 0.5 then
						self:_hitTarget(potentialTarget, targetHumanoid)
					end
				end
			end
		end
	end
end

-- Apply damage to a target
function Punch:_hitTarget(targetModel: Model, targetHumanoid: Humanoid)
	-- Check if we already hit this target (prevent double-hitting)
	if self.hitTargets[targetModel] then
		return
	end

	self.hitTargets[targetModel] = true

	print(`[Punch] Hit target: {targetModel.Name}`)

	-- Apply damage
	targetHumanoid:TakeDamage(PUNCH_DAMAGE)

	-- Apply soft hitstun to the target (if they have WCS character)
	local targetWCSCharacter = WCS.Character.GetCharacterFromInstance(targetModel)
	if targetWCSCharacter then
		-- Create status effect per WCS docs: StatusEffect.new(character)
		local SoftHitstun = require(ReplicatedStorage.Shared.statusEffects.softHitstun)
		local hitstun = SoftHitstun.new(targetWCSCharacter)

		if hitstun then
			-- Start with duration per WCS docs
			hitstun:Start(SOFT_HITSTUN_DURATION)
			print(`[Punch] Applied SoftHitstun ({SOFT_HITSTUN_DURATION}s) to {targetModel.Name}`)
		else
			warn(`[Punch] Failed to create SoftHitstun for {targetModel.Name}`)
		end
	else
		warn(`[Punch] No WCS character found for {targetModel.Name}`)
	end

	-- TODO: Apply knockback
	-- local targetRootPart = targetModel:FindFirstChild("HumanoidRootPart")
	-- if targetRootPart then
	-- 	local knockbackForce = Instance.new("BodyVelocity")
	-- 	knockbackForce.MaxForce = Vector3.new(50000, 0, 50000)
	-- 	knockbackForce.Velocity = self.Character.Instance.HumanoidRootPart.CFrame.LookVector * 20
	-- 	knockbackForce.Parent = targetRootPart
	-- 	game:GetService("Debris"):AddItem(knockbackForce, 0.1)
	-- end
end

function Punch:OnEndServer()
	-- Clear hit targets when skill ends
	self.hitTargets = {}
end

return Punch
