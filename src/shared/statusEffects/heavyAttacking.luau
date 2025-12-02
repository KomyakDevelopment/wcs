--!strict
-- Heavy Attacking Status Effect
-- Applied during heavy/crit attacks with configurable slowdown
-- Uses SetHumanoidData for proper WCS integration

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local WCS = require(ReplicatedStorage.Packages.wcs)
local CombatConfig = require(ReplicatedStorage.Shared.config.combatConfig)

local HeavyAttacking = WCS.RegisterStatusEffect("HeavyAttacking")

-- Base walk speed to calculate slowdown from
local BASE_WALK_SPEED = 16

function HeavyAttacking:OnConstructServer()
	-- Default slowdown multiplier (can be overridden via metadata)
	self.slowMultiplier = CombatConfig.HeavyAttacks.DefaultSlowMultiplier
end

function HeavyAttacking:OnStartServer()
	print("[HeavyAttacking] Server: Heavy attack in progress")

	-- Check for custom slowdown in metadata
	local metadata = self:GetMetadata()
	if metadata and metadata.SlowMultiplier then
		self.slowMultiplier = metadata.SlowMultiplier
	end

	-- Calculate slowed speed (e.g., 0.1 = 10% of normal = 1.6 WalkSpeed)
	local slowedSpeed = BASE_WALK_SPEED * self.slowMultiplier

	-- Use SetHumanoidData for proper WCS integration
	-- This ensures the slowdown persists and doesn't get overwritten
	self:SetHumanoidData({
		WalkSpeed = { slowedSpeed, "Set" },
		JumpPower = { 0, "Set" },
		JumpHeight = { 0, "Set" },
	})

	print(`[HeavyAttacking] Applied {(1 - self.slowMultiplier) * 100}% slowdown - WalkSpeed: {slowedSpeed}`)
end

function HeavyAttacking:OnEndServer()
	print("[HeavyAttacking] Server: Heavy attack finished")
	-- WCS automatically restores humanoid data when status ends
end

function HeavyAttacking:OnStartClient()
	print("[HeavyAttacking] Client: Heavy attack in progress - Dodge blocked")
end

function HeavyAttacking:OnEndClient()
	print("[HeavyAttacking] Client: Heavy attack finished - Dodge available")
end

return HeavyAttacking
