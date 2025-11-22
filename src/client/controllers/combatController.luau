--!strict
-- Combat Controller
-- Manages all combat-related actions, skill execution, and combo systems
-- This is a singleton that handles combat logic on the client

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local WCS = require(ReplicatedStorage.Packages.wcs)
local Punch = require(ReplicatedStorage.Shared.skills.punch)
local Dodge = require(ReplicatedStorage.Shared.skills.dodge)
local Block = require(ReplicatedStorage.Shared.skills.block)

local CombatController = {}
CombatController.__index = CombatController

function CombatController.new()
	local self = setmetatable({}, CombatController)

	-- References to other controllers/managers (set later)
	self.equipmentController = nil
	self.sprintManager = nil

	-- Client-side debounce to prevent dodge spam
	self.dodgeDebounce = false

	-- Cached skill references (set on first use for faster subsequent lookups)
	self._cachedCharacter = nil
	self._cachedPunchSkill = nil
	self._cachedBlockSkill = nil
	self._cachedDodgeSkill = nil

	return self
end

-- Set equipment controller reference
function CombatController:setEquipmentController(equipmentController)
	self.equipmentController = equipmentController
end

-- Set sprint manager reference
function CombatController:setSprintManager(sprintManager)
	self.sprintManager = sprintManager
end

-- Get the current WCS character wrapper (cached for performance)
function CombatController:getCharacter()
	local characterModel = Players.LocalPlayer.Character
	if not characterModel then
		self._cachedCharacter = nil
		return nil
	end

	-- Check if cached character is still valid
	if self._cachedCharacter and self._cachedCharacter.Instance == characterModel then
		return self._cachedCharacter
	end

	-- Cache new character and clear skill caches
	self._cachedCharacter = WCS.Character.GetCharacterFromInstance(characterModel)
	self._cachedPunchSkill = nil
	self._cachedBlockSkill = nil
	self._cachedDodgeSkill = nil

	return self._cachedCharacter
end

-- Get punch skill (cached for performance)
function CombatController:getPunchSkill()
	local character = self:getCharacter()
	if not character then
		return nil
	end

	if not self._cachedPunchSkill then
		self._cachedPunchSkill = character:GetSkillFromConstructor(Punch)
	end

	return self._cachedPunchSkill
end

-- Get block skill (cached for performance)
function CombatController:getBlockSkill()
	local character = self:getCharacter()
	if not character then
		return nil
	end

	if not self._cachedBlockSkill then
		self._cachedBlockSkill = character:GetSkillFromConstructor(Block)
	end

	return self._cachedBlockSkill
end

-- Get dodge skill (cached for performance)
function CombatController:getDodgeSkill()
	local character = self:getCharacter()
	if not character then
		return nil
	end

	if not self._cachedDodgeSkill then
		self._cachedDodgeSkill = character:GetSkillFromConstructor(Dodge)
	end

	return self._cachedDodgeSkill
end

-- Perform primary attack (M1)
function CombatController:performPrimaryAttack()
	-- Check if player has a slot selected (waiting to confirm equip/unequip)
	-- IMPORTANT: Check this BEFORE canceling sprint
	if self.equipmentController and self.equipmentController:getSelectedSlot() then
		-- Confirm the equip/unequip action
		local slotNumber = self.equipmentController:getSelectedSlot()

		-- Map slot to weapon ID
		if slotNumber == 1 then
			self.equipmentController:confirmAction("fists")
		end

		-- Don't cancel sprint or perform attack when confirming equipment
		return
	end

	-- Check if player has equipment equipped
	if not self.equipmentController or not self.equipmentController:getEquipped() then
		print("[CombatController] Cannot attack - No weapon equipped")
		return
	end

	-- Get punch skill using cached accessor (fast path)
	local punchSkill = self:getPunchSkill()
	if not punchSkill then
		-- No skill found - player probably doesn't have weapon equipped
		return
	end

	-- Check if skill is on cooldown
	local state = punchSkill:GetState()
	if state.Debounce then
		-- Don't update combo or print anything - skill is on cooldown
		return
	end

	-- Cancel sprint if active (only when actually attacking, after all checks pass)
	if self.sprintManager then
		self.sprintManager:stopSprint()
	end

	-- Execute the skill
	punchSkill:Start()
end

-- Perform secondary attack (M2)
function CombatController:performSecondaryAttack()
	print("[CombatController] Secondary attack - Not implemented yet")
	-- TODO: Implement heavy attack or other secondary action
end

-- Perform block action
function CombatController:performBlock(state: Enum.UserInputState)
	-- Get block skill using cached accessor (fast path)
	local blockSkill = self:getBlockSkill()
	if not blockSkill then
		print("[CombatController] performBlock: No block skill found on character")
		return
	end

	if state == Enum.UserInputState.Begin then
		print("[CombatController] Block started")

		-- Cancel sprint if active
		if self.sprintManager then
			self.sprintManager:stopSprint()
		end

		-- Start blocking
		blockSkill:Start()
	elseif state == Enum.UserInputState.End then
		print("[CombatController] Block ended")

		-- Stop blocking
		blockSkill:End()
	end
end

-- Perform dodge action
function CombatController:performDodge()
	-- Client-side debounce to prevent rapid spam before server state updates
	if self.dodgeDebounce then
		return
	end

	-- Get dodge skill using cached accessor (fast path)
	local dodgeSkill = self:getDodgeSkill()
	if not dodgeSkill then
		print("[CombatController] performDodge: No dodge skill found on character")
		return
	end

	-- Check if skill is on cooldown
	local state = dodgeSkill:GetState()
	if state.Debounce then
		print("[CombatController] performDodge: Dodge is on cooldown")
		return
	end

	-- Set client-side debounce immediately
	self.dodgeDebounce = true
	task.delay(0.5, function()
		self.dodgeDebounce = false
	end)

	-- Cancel sprint if active (AFTER validation)
	if self.sprintManager then
		self.sprintManager:stopSprint()
	end

	print("[CombatController] performDodge: Starting dodge skill")
	-- Execute the dodge skill
	dodgeSkill:Start()
end

-- Use ability from hotbar slot
function CombatController:useAbility(slotNumber: number)
	print(`[CombatController] Using ability slot {slotNumber} - Not implemented yet`)
	-- TODO: Get ability from hotbar and execute
end

return CombatController
