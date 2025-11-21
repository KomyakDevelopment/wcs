--!strict
-- Equipment Manager (Server)
-- Manages equipped weapons and ensures animations play for all clients

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local EquipmentManager = {}
EquipmentManager.__index = EquipmentManager

export type EquipmentManager = typeof(setmetatable(
	{} :: {
		character: any, -- WCS Character
		equipped: string?, -- Currently equipped weapon ID
		idleAnimation: { AnimationTrack }?,
	},
	EquipmentManager
))

-- Equipment definitions
local EQUIPMENT = {
	fists = {
		Name = "Fists",
		IdleAnimationIds = { 115261994832101, 118333310231162 },
		Moveset = "Unarmed",
	},
}

function EquipmentManager.new(wcsCharacter): EquipmentManager
	local self = setmetatable({}, EquipmentManager)

	self.character = wcsCharacter
	self.equipped = nil
	self.idleAnimation = nil

	return self
end

-- Equip a weapon by ID
function EquipmentManager:equip(weaponId: string): boolean
	local weapon = EQUIPMENT[weaponId]

	if not weapon then
		warn(`[EquipmentManager] Unknown weapon: {weaponId}`)
		return false
	end

	-- Unequip current weapon first
	if self.equipped then
		self:unequip()
	end

	print(`[EquipmentManager] Equipping {weapon.Name} for {self.character.Instance.Name}`)

	-- Apply moveset
	self.character:ApplyMoveset(weapon.Moveset)

	-- Play idle animation (server-side, replicates to all clients)
	if weapon.IdleAnimationIds then
		self:_playIdleAnimation(weapon.IdleAnimationIds)
	end

	self.equipped = weaponId

	print(`[EquipmentManager] {weapon.Name} equipped successfully`)

	return true
end

-- Unequip current weapon
function EquipmentManager:unequip()
	if not self.equipped then
		return
	end

	print(`[EquipmentManager] Unequipping {self.equipped} for {self.character.Instance.Name}`)

	-- Stop idle animation
	if self.idleAnimation then
		for _, track in ipairs(self.idleAnimation) do
			if track and track.Stop then
				track:Stop()
			end
		end
		self.idleAnimation = nil
	end

	-- Clear moveset and reapply Unarmed to keep permanent skills (Dodge, Sprint)
	self.character:ClearMoveset()
	self.character:ApplyMoveset("Unarmed")

	self.equipped = nil

	print(`[EquipmentManager] Weapon unequipped - Unarmed moveset restored`)
end

-- Check if player has a weapon equipped
function EquipmentManager:hasWeaponEquipped(): boolean
	return self.equipped ~= nil
end

-- Get currently equipped weapon ID
function EquipmentManager:getEquipped(): string?
	return self.equipped
end

-- Internal: Play idle animation (server-side, replicates to clients)
function EquipmentManager:_playIdleAnimation(animationIds: { number })
	local humanoid = self.character.Instance:FindFirstChild("Humanoid")
	if not humanoid then
		warn("[EquipmentManager] No Humanoid found")
		return
	end

	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		warn("[EquipmentManager] No Animator found")
		return
	end

	-- Stop previous animations (if any)
	if self.idleAnimation then
		for _, track in ipairs(self.idleAnimation) do
			track:Stop()
		end
	end

	self.idleAnimation = {} -- store multiple tracks

	-- Load & play ALL idle animations
	for _, animId in ipairs(animationIds) do
		local anim = Instance.new("Animation")
		anim.AnimationId = `rbxassetid://{animId}`

		local track = animator:LoadAnimation(anim)
		track.Looped = true
		track:Play()

		table.insert(self.idleAnimation, track)
		print(`[EquipmentManager] Playing idle animation: {animId}`)
	end
end

-- Cleanup
function EquipmentManager:destroy()
	self:unequip()
end

return EquipmentManager
