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
		idleAnimation: AnimationTrack?,
	},
	EquipmentManager
))

-- Equipment definitions
local EQUIPMENT = {
	fists = {
		Name = "Fists",
		IdleAnimationId = 139347452198150,
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
	if weapon.IdleAnimationId then
		self:_playIdleAnimation(weapon.IdleAnimationId)
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
		self.idleAnimation:Stop()
		self.idleAnimation = nil
	end

	-- Clear moveset
	self.character:ClearMoveset()

	self.equipped = nil

	print(`[EquipmentManager] Weapon unequipped`)
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
function EquipmentManager:_playIdleAnimation(animationId: number)
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

	-- Create animation instance
	local animation = Instance.new("Animation")
	animation.AnimationId = `rbxassetid://{animationId}`

	-- Load and play animation
	local track = animator:LoadAnimation(animation)
	track.Looped = true
	track:Play()

	self.idleAnimation = track

	print(`[EquipmentManager] Playing idle animation: {animationId}`)
end

-- Cleanup
function EquipmentManager:destroy()
	self:unequip()
end

return EquipmentManager
