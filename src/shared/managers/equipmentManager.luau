--!strict
-- Equipment Manager (Server)
-- Manages equipped weapons and ensures animations play for all clients
-- Handles physical weapon models with Motor6D joints

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local EquipmentManager = {}
EquipmentManager.__index = EquipmentManager

export type EquipmentManager = typeof(setmetatable(
	{} :: {
		character: any, -- WCS Character
		equipped: string?, -- Currently equipped weapon ID
		idleAnimation: { AnimationTrack }?,
		weaponModel: Model?, -- Physical weapon model instance
		weaponMotor: Motor6D?, -- Motor6D joint for weapon attachment
		weaponInHand: boolean, -- Is weapon in hand (true) or on back (false)
		_weaponJointsFolder: Instance?, -- Reference to weapon's joints folder
	},
	EquipmentManager
))

-- Equipment definitions
-- Physical weapons have ModelPath for the weapon model location
-- CriticalSkill defines which heavy attack skill this weapon uses
local EQUIPMENT = {
	fists = {
		Name = "Fists",
		IdleAnimationIds = { 115261994832101, 118333310231162 },
		Moveset = "Unarmed",
		CriticalSkill = "HeavyPunch", -- Heavy attack for fists
		IsPhysical = false, -- Fists don't have a physical model
	},
	kunai = {
		Name = "Kunai",
		IdleAnimationIds = { 118152163033819, 133017425360708 }, -- torso, hands
		Moveset = "Armed",
		CriticalSkill = "HeavySlash", -- Heavy attack for light weapons
		IsPhysical = true,
		ModelPath = "ReplicatedStorage.Assets.Models.Weapons.Light_Weapons.Kunai", -- Path to weapon folder
		BackAttachment = "Torso", -- Where to attach when on back
		HandAttachment = "Right Arm", -- Where to attach when in hand
		WeaponHandlePart = "handle", -- Part in weapon model that connects to character
	},
}

function EquipmentManager.new(wcsCharacter): EquipmentManager
	local self = setmetatable({}, EquipmentManager)

	self.character = wcsCharacter
	self.equipped = nil
	self.idleAnimation = nil
	self.weaponModel = nil
	self.weaponMotor = nil
	self.weaponInHand = false
	self._weaponJointsFolder = nil

	return self
end

-- Resolve a path string like "ReplicatedStorage.Assets.Weapons.Kunai" to the actual instance
local function resolvePath(pathString: string): Instance?
	local parts = string.split(pathString, ".")
	local current: Instance = game

	for _, part in ipairs(parts) do
		local child = current:FindFirstChild(part)
		if not child then
			warn(`[EquipmentManager] Could not find "{part}" in path: {pathString}`)
			return nil
		end
		current = child
	end

	return current
end

-- Equip a weapon by ID
-- For physical weapons, this puts the weapon on the player's back (not in hand yet)
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

	-- Clear existing moveset first to ensure clean transition
	-- This prevents conflicts when skills exist in multiple movesets
	self.character:ClearMoveset()

	-- Apply weapon moveset
	self.character:ApplyMoveset(weapon.Moveset)

	-- Handle physical weapon model
	if weapon.IsPhysical and weapon.ModelPath then
		self:_spawnWeaponModel(weapon)
		-- Physical weapons start on back, not in hand
		self.weaponInHand = false
		-- Don't play idle animations until weapon is in hand
	else
		-- Non-physical weapons (fists) play idle animation immediately
		if weapon.IdleAnimationIds then
			self:_playIdleAnimation(weapon.IdleAnimationIds)
		end
		-- Fists are always "in hand"
		self.weaponInHand = true
	end

	self.equipped = weaponId

	print(`[EquipmentManager] {weapon.Name} equipped successfully (in hand: {self.weaponInHand})`)

	return true
end

-- Move weapon from back to hand (or vice versa)
-- Called when player presses the weapon slot key again
function EquipmentManager:toggleWeaponInHand(): boolean
	if not self.equipped then
		return false
	end

	local weapon = EQUIPMENT[self.equipped]
	if not weapon or not weapon.IsPhysical then
		-- Non-physical weapons are always in hand
		return false
	end

	if self.weaponInHand then
		-- Move weapon from hand to back
		self:_attachWeaponToBack(weapon)
		self.weaponInHand = false
		-- Stop idle animations
		if self.idleAnimation then
			for _, track in ipairs(self.idleAnimation) do
				if track and track.Stop then
					track:Stop()
				end
			end
			self.idleAnimation = nil
		end
		print(`[EquipmentManager] {weapon.Name} moved to back`)
	else
		-- Move weapon from back to hand
		self:_attachWeaponToHand(weapon)
		self.weaponInHand = true
		-- Start idle animations
		if weapon.IdleAnimationIds then
			self:_playIdleAnimation(weapon.IdleAnimationIds)
		end
		print(`[EquipmentManager] {weapon.Name} moved to hand`)
	end

	return true
end

-- Spawn the physical weapon model and attach to back
function EquipmentManager:_spawnWeaponModel(weapon)
	print(`[EquipmentManager] _spawnWeaponModel called for: {weapon.Name}`)
	print(`[EquipmentManager] ModelPath: {weapon.ModelPath}`)

	-- Get the weapon folder
	local weaponFolder = resolvePath(weapon.ModelPath)
	if not weaponFolder then
		warn(`[EquipmentManager] Weapon folder not found at: {weapon.ModelPath}`)
		return
	end

	print(`[EquipmentManager] Found weapon folder: {weaponFolder:GetFullName()}`)

	-- Find the first Model in the folder (the actual weapon model)
	local modelTemplate: Model? = nil
	for _, child in ipairs(weaponFolder:GetChildren()) do
		print(`[EquipmentManager] Found child: {child.Name} ({child.ClassName})`)
		if child:IsA("Model") then
			modelTemplate = child
			break
		end
	end

	if not modelTemplate then
		warn(`[EquipmentManager] No Model found in weapon folder: {weapon.ModelPath}`)
		return
	end

	print(`[EquipmentManager] Using model template: {modelTemplate.Name}`)

	-- Store reference to joints folder for later use
	self._weaponJointsFolder = weaponFolder:FindFirstChild("joints")
	if not self._weaponJointsFolder then
		warn(`[EquipmentManager] No joints folder found in weapon folder: {weapon.ModelPath}`)
	else
		print(`[EquipmentManager] Found joints folder`)
	end

	-- Clone the model
	local weaponClone = modelTemplate:Clone()
	weaponClone.Name = weapon.Name .. "_Equipped"

	print(`[EquipmentManager] Cloned model, parenting to: {self.character.Instance:GetFullName()}`)

	-- Parent to character
	weaponClone.Parent = self.character.Instance

	self.weaponModel = weaponClone

	print(`[EquipmentManager] Weapon model parented successfully: {weaponClone:GetFullName()}`)

	-- Attach to back initially
	self:_attachWeaponToBack(weapon)

	print(`[EquipmentManager] Spawned weapon model: {weapon.Name}`)
end

-- Attach weapon to character's back (Torso)
function EquipmentManager:_attachWeaponToBack(weapon)
	if not self.weaponModel then
		return
	end

	local character = self.character.Instance
	local attachPartName = weapon.BackAttachment or "Torso"
	local attachPart = character:FindFirstChild(attachPartName)

	if not attachPart then
		warn(`[EquipmentManager] Back attachment part not found: {attachPartName}`)
		return
	end

	-- Find the handle part in the weapon model (connects to character)
	local handlePartName = weapon.WeaponHandlePart or "handle"
	local handlePart = self.weaponModel:FindFirstChild(handlePartName)
	if not handlePart then
		warn(`[EquipmentManager] Weapon model has no {handlePartName} part`)
		return
	end

	-- Remove existing motor if any
	if self.weaponMotor then
		self.weaponMotor:Destroy()
		self.weaponMotor = nil
	end

	-- Try to use pre-made joint from joints folder
	local motor: Motor6D? = nil
	if self._weaponJointsFolder then
		local jointFolder = self._weaponJointsFolder:FindFirstChild(attachPartName)
		if jointFolder then
			local jointTemplate = jointFolder:FindFirstChild(handlePartName)
			if jointTemplate and jointTemplate:IsA("Motor6D") then
				motor = jointTemplate:Clone()
				print(`[EquipmentManager] Using pre-made joint from joints/{attachPartName}/{handlePartName}`)
			end
		end
	end

	-- Fallback: create Motor6D manually if no pre-made joint found
	if not motor then
		motor = Instance.new("Motor6D")
		motor.Name = "WeaponMotor"
		motor.C0 = CFrame.new(0, 0.5, 0.5) * CFrame.Angles(0, math.rad(90), math.rad(-45))
		motor.C1 = CFrame.new()
		print("[EquipmentManager] Creating Motor6D manually (no pre-made joint found)")
	end

	-- Connect the motor
	motor.Part0 = attachPart
	motor.Part1 = handlePart
	motor.Parent = attachPart

	self.weaponMotor = motor

	print("[EquipmentManager] Weapon attached to back")
end

-- Attach weapon to character's hand (Right Arm)
function EquipmentManager:_attachWeaponToHand(weapon)
	if not self.weaponModel then
		return
	end

	local character = self.character.Instance
	local attachPartName = weapon.HandAttachment or "Right Arm"
	local attachPart = character:FindFirstChild(attachPartName)

	if not attachPart then
		warn(`[EquipmentManager] Hand attachment part not found: {attachPartName}`)
		return
	end

	-- Find the handle part in the weapon model (connects to character)
	local handlePartName = weapon.WeaponHandlePart or "handle"
	local handlePart = self.weaponModel:FindFirstChild(handlePartName)
	if not handlePart then
		warn(`[EquipmentManager] Weapon model has no {handlePartName} part`)
		return
	end

	-- Remove existing motor if any
	if self.weaponMotor then
		self.weaponMotor:Destroy()
		self.weaponMotor = nil
	end

	-- Try to use pre-made joint from joints folder
	local motor: Motor6D? = nil
	if self._weaponJointsFolder then
		local jointFolder = self._weaponJointsFolder:FindFirstChild(attachPartName)
		if jointFolder then
			local jointTemplate = jointFolder:FindFirstChild(handlePartName)
			if jointTemplate and jointTemplate:IsA("Motor6D") then
				motor = jointTemplate:Clone()
				print(`[EquipmentManager] Using pre-made joint from joints/{attachPartName}/{handlePartName}`)
			end
		end
	end

	-- Fallback: create Motor6D manually if no pre-made joint found
	if not motor then
		motor = Instance.new("Motor6D")
		motor.Name = "WeaponMotor"
		-- Position weapon in hand (use RightGripAttachment if available)
		local gripAttachment = attachPart:FindFirstChild("RightGripAttachment")
		if gripAttachment then
			motor.C0 = gripAttachment.CFrame
		else
			-- Fallback positioning
			motor.C0 = CFrame.new(0, -1, 0) * CFrame.Angles(math.rad(-90), 0, 0)
		end
		motor.C1 = CFrame.new()
		print("[EquipmentManager] Creating Motor6D manually (no pre-made joint found)")
	end

	-- Connect the motor
	motor.Part0 = attachPart
	motor.Part1 = handlePart
	motor.Parent = attachPart

	self.weaponMotor = motor

	print("[EquipmentManager] Weapon attached to hand")
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

	-- Destroy weapon motor
	if self.weaponMotor then
		self.weaponMotor:Destroy()
		self.weaponMotor = nil
	end

	-- Destroy weapon model
	if self.weaponModel then
		self.weaponModel:Destroy()
		self.weaponModel = nil
	end

	-- Clear joints folder reference
	self._weaponJointsFolder = nil

	-- Reset weapon state
	self.weaponInHand = false

	-- Clear weapon moveset and reapply Base (Dodge only)
	self.character:ClearMoveset()
	self.character:ApplyMoveset("Base")

	self.equipped = nil

	print(`[EquipmentManager] Weapon unequipped - Base moveset (Dodge) restored`)
end

-- Check if player has a weapon equipped
function EquipmentManager:hasWeaponEquipped(): boolean
	return self.equipped ~= nil
end

-- Get currently equipped weapon ID
function EquipmentManager:getEquipped(): string?
	return self.equipped
end

-- Check if weapon is currently in hand (not on back)
function EquipmentManager:isWeaponInHand(): boolean
	return self.weaponInHand
end

-- Get the physical weapon model (if any)
function EquipmentManager:getWeaponModel(): Model?
	return self.weaponModel
end

-- Get weapon definition by ID
function EquipmentManager:getWeaponDefinition(weaponId: string?)
	local id = weaponId or self.equipped
	if not id then
		return nil
	end
	return EQUIPMENT[id]
end

-- Get the critical skill name for the currently equipped weapon
function EquipmentManager:getCriticalSkill(): string?
	if not self.equipped then
		return nil
	end
	local weapon = EQUIPMENT[self.equipped]
	if not weapon then
		return nil
	end
	return weapon.CriticalSkill
end

-- Get all available weapon IDs
function EquipmentManager.getAvailableWeapons(): { string }
	local weapons = {}
	for weaponId, _ in pairs(EQUIPMENT) do
		table.insert(weapons, weaponId)
	end
	return weapons
end

-- Static: Get the critical skill name for a given weapon ID (callable from client)
function EquipmentManager.getCriticalSkillForWeapon(weaponId: string): string?
	local weapon = EQUIPMENT[weaponId]
	if not weapon then
		return nil
	end
	return weapon.CriticalSkill
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
