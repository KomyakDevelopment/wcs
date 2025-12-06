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
		weaponModel: Model?, -- Physical weapon model instance (blade for scabbard weapons)
		weaponMotor: Motor6D?, -- Motor6D joint for weapon attachment
		weaponInHand: boolean, -- Is weapon in hand (true) or on back (false)
		scabbardModel: Model?, -- Scabbard model for medium weapons (stays on torso)
		scabbardMotor: Motor6D?, -- Motor6D joint for scabbard attachment
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
	ninjato = {
		Name = "Ninjato",
		IdleAnimationIds = { 115261994832101, 116358842043289 }, -- torso, hands
		Moveset = "Armed",
		CriticalSkill = "HeavySwing", -- Heavy attack for medium weapons
		IsPhysical = true,
		ModelPath = "ReplicatedStorage.Assets.Models.Weapons.Medium_Weapons.Ninjato", -- Path to weapon folder
		BackAttachment = "Torso", -- Where to attach when on back
		HandAttachment = "Right Arm", -- Where to attach when in hand
		WeaponHandlePart = "handle", -- Part in weapon model that connects to character
		-- Scabbard configuration for medium weapons
		HasScabbard = true, -- This weapon has a separate scabbard
		ScabbardPart = "Scabbard", -- Name of scabbard model/part in weapon model
		ScabbardAttachment = "Torso", -- Where scabbard attaches (always stays here)
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
	self.scabbardModel = nil
	self.scabbardMotor = nil
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

	-- Set attribute so other systems can check what weapon is equipped
	self.character.Instance:SetAttribute("EquippedWeapon", weaponId)

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

	-- Disable all trails in the weapon model (they get enabled during swings)
	for _, descendant in ipairs(weaponClone:GetDescendants()) do
		if descendant:IsA("Trail") then
			descendant.Enabled = false
		end
	end

	print(`[EquipmentManager] Cloned model, parenting to: {self.character.Instance:GetFullName()}`)

	-- Handle scabbard weapons (medium weapons like ninjato)
	if weapon.HasScabbard then
		-- Find scabbard_handle (attachment point) and Scabbard (visual mesh)
		local scabbardHandle = weaponClone:FindFirstChild("scabbard_handle")
		local scabbardMesh = weaponClone:FindFirstChild("Scabbard")

		if scabbardHandle then
			print(`[EquipmentManager] Found scabbard_handle`)

			-- Create a model to hold scabbard parts
			local scabbardModel = Instance.new("Model")
			scabbardModel.Name = weapon.Name .. "_Scabbard"

			-- Move scabbard parts into the model
			scabbardHandle.Parent = scabbardModel
			if scabbardMesh then
				scabbardMesh.Parent = scabbardModel
				print(`[EquipmentManager] Found Scabbard mesh`)
			end

			-- Parent scabbard model to character
			scabbardModel.Parent = self.character.Instance
			self.scabbardModel = scabbardModel

			-- Attach scabbard to torso permanently
			self:_attachScabbardToTorso(weapon)

			print(`[EquipmentManager] Scabbard separated and attached to torso`)
		else
			warn(`[EquipmentManager] scabbard_handle not found in weapon model`)
		end
	end

	-- Parent blade/weapon to character
	weaponClone.Parent = self.character.Instance

	self.weaponModel = weaponClone

	print(`[EquipmentManager] Weapon model parented successfully: {weaponClone:GetFullName()}`)

	-- Attach to back initially (for scabbard weapons, this positions blade in scabbard)
	self:_attachWeaponToBack(weapon)

	print(`[EquipmentManager] Spawned weapon model: {weapon.Name}`)
end

-- Attach scabbard to character's torso (permanent position for medium weapons)
function EquipmentManager:_attachScabbardToTorso(weapon)
	if not self.scabbardModel then
		return
	end

	local character = self.character.Instance
	local attachPartName = weapon.ScabbardAttachment or "Torso"
	local attachPart = character:FindFirstChild(attachPartName)

	if not attachPart then
		warn(`[EquipmentManager] Scabbard attachment part not found: {attachPartName}`)
		return
	end

	-- Find the scabbard handle part
	local scabbardHandle = self.scabbardModel:FindFirstChild("scabbard_handle")
		or self.scabbardModel:FindFirstChild("handle")
		or self.scabbardModel:FindFirstChild("Handle")

	if not scabbardHandle then
		warn("[EquipmentManager] Scabbard has no handle part")
		return
	end

	-- Remove existing scabbard motor if any
	if self.scabbardMotor then
		self.scabbardMotor:Destroy()
		self.scabbardMotor = nil
	end

	-- Use pre-made joint from joints folder: joints/Torso/scabbard_handle
	local motor: Motor6D? = nil
	if self._weaponJointsFolder then
		local bodyPartFolder = self._weaponJointsFolder:FindFirstChild(attachPartName)
		if bodyPartFolder then
			local jointTemplate = bodyPartFolder:FindFirstChild("scabbard_handle")
			if jointTemplate and jointTemplate:IsA("Motor6D") then
				motor = jointTemplate:Clone()
				motor.Part0 = attachPart
				motor.Part1 = scabbardHandle
				motor.Parent = attachPart
				print(`[EquipmentManager] Using pre-made scabbard joint from joints/{attachPartName}/scabbard_handle`)
			end
		end
	end

	if not motor then
		warn("[EquipmentManager] No scabbard joint found in joints folder - scabbard attachment failed")
		return
	end

	self.scabbardMotor = motor

	print("[EquipmentManager] Scabbard attached to torso")
end

-- Attach weapon to character's back (Torso) or into scabbard for scabbard weapons
function EquipmentManager:_attachWeaponToBack(weapon)
	if not self.weaponModel then
		return
	end

	local character = self.character.Instance

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

	local motor: Motor6D? = nil

	-- For scabbard weapons, try to attach blade to scabbard first
	if weapon.HasScabbard and self.scabbardModel then
		-- Find scabbard handle to attach blade to
		local scabbardHandle = self.scabbardModel:FindFirstChild("scabbard_handle")
			or self.scabbardModel:FindFirstChild("handle")

		if scabbardHandle and self._weaponJointsFolder then
			-- Try joints/Scabbard/handle first (blade positioned relative to scabbard)
			local scabbardJointsFolder = self._weaponJointsFolder:FindFirstChild("Scabbard")
			if scabbardJointsFolder then
				local jointTemplate = scabbardJointsFolder:FindFirstChild(handlePartName)
				if jointTemplate and jointTemplate:IsA("Motor6D") then
					local clonedMotor = jointTemplate:Clone() :: Motor6D
					clonedMotor.Part0 = scabbardHandle
					clonedMotor.Part1 = handlePart
					clonedMotor.Parent = scabbardHandle
					motor = clonedMotor
					print(`[EquipmentManager] Using pre-made joint from joints/Scabbard/{handlePartName}`)
				end
			end
		end
	end

	-- If no scabbard joint found (or not a scabbard weapon), attach to torso
	if not motor then
		local attachPartName = weapon.BackAttachment or "Torso"
		local attachPart = character:FindFirstChild(attachPartName)

		if not attachPart then
			warn(`[EquipmentManager] Back attachment part not found: {attachPartName}`)
			return
		end

		if self._weaponJointsFolder then
			-- First try joints/Torso/handle
			local bodyPartFolder = self._weaponJointsFolder:FindFirstChild(attachPartName)
			if bodyPartFolder then
				local jointTemplate = bodyPartFolder:FindFirstChild(handlePartName)
				if jointTemplate and jointTemplate:IsA("Motor6D") then
					local clonedMotor = jointTemplate:Clone() :: Motor6D
					clonedMotor.Part0 = attachPart
					clonedMotor.Part1 = handlePart
					clonedMotor.Parent = attachPart
					motor = clonedMotor
					print(`[EquipmentManager] Using pre-made joint from joints/{attachPartName}/{handlePartName} (sheathed to torso)`)
				end
			end

			-- Fallback: use Right Arm/handle joint but reparent to Torso
			if not motor then
				local handPartName = weapon.HandAttachment or "Right Arm"
				local handFolder = self._weaponJointsFolder:FindFirstChild(handPartName)
				if handFolder then
					local jointTemplate = handFolder:FindFirstChild(handlePartName)
					if jointTemplate and jointTemplate:IsA("Motor6D") then
						local clonedMotor = jointTemplate:Clone() :: Motor6D
						clonedMotor.Part0 = attachPart -- Use Torso instead of Right Arm
						clonedMotor.Part1 = handlePart
						clonedMotor.Parent = attachPart
						motor = clonedMotor
						print(`[EquipmentManager] Using joints/{handPartName}/{handlePartName} reparented to {attachPartName} (sheathed)`)
					end
				end
			end
		end
	end

	if not motor then
		warn(`[EquipmentManager] No back joint found in joints folder - weapon attachment failed`)
		return
	end

	self.weaponMotor = motor

	print("[EquipmentManager] Weapon sheathed/attached to back")
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

	-- Use pre-made joint from joints folder: joints/["Right Arm"]/handle
	local motor: Motor6D? = nil
	if self._weaponJointsFolder then
		local bodyPartFolder = self._weaponJointsFolder:FindFirstChild(attachPartName)
		if bodyPartFolder then
			local jointTemplate = bodyPartFolder:FindFirstChild(handlePartName)
			if jointTemplate and jointTemplate:IsA("Motor6D") then
				motor = jointTemplate:Clone()
				motor.Part0 = attachPart
				motor.Part1 = handlePart
				motor.Parent = attachPart
				print(`[EquipmentManager] Using pre-made joint from joints/{attachPartName}/{handlePartName}`)
			end
		end
	end

	if not motor then
		warn(`[EquipmentManager] No hand joint found in joints folder - weapon attachment failed`)
		return
	end

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

	-- Destroy scabbard motor (for medium weapons)
	if self.scabbardMotor then
		self.scabbardMotor:Destroy()
		self.scabbardMotor = nil
	end

	-- Destroy scabbard model (for medium weapons)
	if self.scabbardModel then
		self.scabbardModel:Destroy()
		self.scabbardModel = nil
	end

	-- Clear joints folder reference
	self._weaponJointsFolder = nil

	-- Reset weapon state
	self.weaponInHand = false

	-- Clear weapon moveset and reapply Base (Dodge only)
	self.character:ClearMoveset()
	self.character:ApplyMoveset("Base")

	self.equipped = nil

	-- Clear equipped weapon attribute
	self.character.Instance:SetAttribute("EquippedWeapon", nil)

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
