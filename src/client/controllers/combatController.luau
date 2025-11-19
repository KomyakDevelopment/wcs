--!strict
-- Combat Controller
-- Manages all combat-related actions, skill execution, and combo systems
-- This is a singleton that handles combat logic on the client

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local WCS = require(ReplicatedStorage.Packages.wcs)
local Punch = require(ReplicatedStorage.Shared.skills.punch)

local CombatController = {}
CombatController.__index = CombatController

function CombatController.new()
	local self = setmetatable({}, CombatController)

	return self
end

-- Get the current WCS character wrapper
function CombatController:getCharacter()
	local characterModel = Players.LocalPlayer.Character
	if not characterModel then
		return nil
	end

	return WCS.Character.GetCharacterFromInstance(characterModel)
end

-- Perform primary attack (M1)
function CombatController:performPrimaryAttack()
	local character = self:getCharacter()
	if not character then
		return
	end

	-- Get the punch skill from character
	local punchSkill = character:GetSkillFromConstructor(Punch)
	if not punchSkill then
		warn("[CombatController] Punch skill not found on character")
		return
	end

	-- Check if skill is on cooldown
	local state = punchSkill:GetState()
	if state.Debounce then
		-- Don't update combo or print anything - skill is on cooldown
		return
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
	if state == Enum.UserInputState.Begin then
		print("[CombatController] Block started")
		-- TODO: Start blocking
	elseif state == Enum.UserInputState.End then
		print("[CombatController] Block ended")
		-- TODO: Stop blocking
	end
end

-- Perform dodge action
function CombatController:performDodge()
	print("[CombatController] Dodge - Not implemented yet")
	-- TODO: Implement dodge roll
end

-- Use ability from hotbar slot
function CombatController:useAbility(slotNumber: number)
	print(`[CombatController] Using ability slot {slotNumber} - Not implemented yet`)
	-- TODO: Get ability from hotbar and execute
end

return CombatController
