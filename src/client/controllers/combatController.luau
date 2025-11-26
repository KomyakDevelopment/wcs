--!strict
-- Combat Controller
-- Manages all combat-related actions, skill execution, and combo systems
-- This is a singleton that handles combat logic on the client

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local WCS = require(ReplicatedStorage.Packages.wcs)
local Punch = require(ReplicatedStorage.Shared.skills.punch)
local Slash = require(ReplicatedStorage.Shared.skills.slash)
local Dodge = require(ReplicatedStorage.Shared.skills.dodge)
local Block = require(ReplicatedStorage.Shared.skills.block)
local HeavyPunch = require(ReplicatedStorage.Shared.skills.heavyPunch)
local HeavySlash = require(ReplicatedStorage.Shared.skills.heavySlash)

-- Equipment manager for looking up weapon configs
local EquipmentManager = require(ReplicatedStorage.Shared.managers.equipmentManager)

-- Status effects for validation
local Guardbroken = require(ReplicatedStorage.Shared.statusEffects.guardbroken)

-- Lookup table: maps CriticalSkill names to their constructors
-- Add new heavy attacks here when creating them
local CRITICAL_SKILLS = {
	HeavyPunch = HeavyPunch,
	HeavySlash = HeavySlash,
	-- Future: HeavyGreatswordSpin = HeavyGreatswordSpin,
}

local CombatController = {}
CombatController.__index = CombatController

function CombatController.new()
	local self = setmetatable({}, CombatController)

	-- References to other controllers/managers (set later)
	self.equipmentController = nil
	self.sprintManager = nil

	-- Client-side debounce to prevent dodge spam
	self.dodgeDebounce = false

	-- Cached character reference (cleared on respawn)
	self._cachedCharacter = nil

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

	-- Cache new character
	self._cachedCharacter = WCS.Character.GetCharacterFromInstance(characterModel)

	return self._cachedCharacter
end

-- Get punch skill (fresh lookup - moveset changes can add/remove skills)
function CombatController:getPunchSkill()
	local character = self:getCharacter()
	if not character then
		return nil
	end

	-- Always get fresh reference since moveset changes destroy/recreate skills
	return character:GetSkillFromConstructor(Punch)
end

-- Get slash skill (fresh lookup - moveset changes can add/remove skills)
function CombatController:getSlashSkill()
	local character = self:getCharacter()
	if not character then
		return nil
	end

	-- Always get fresh reference since moveset changes destroy/recreate skills
	return character:GetSkillFromConstructor(Slash)
end

-- Get the appropriate attack skill based on equipped weapon
function CombatController:getAttackSkill()
	-- Check if player has equipment controller and weapon equipped
	if not self.equipmentController then
		return nil
	end

	local equipped = self.equipmentController:getEquipped()
	if not equipped then
		return nil
	end

	-- Fists use Punch, weapons use Slash
	if equipped == "fists" then
		return self:getPunchSkill()
	else
		-- For physical weapons (kunai, etc.), check if weapon is in hand
		if not self.equipmentController:isWeaponInHand() then
			return nil -- Can't attack with weapon on back
		end
		return self:getSlashSkill()
	end
end

-- Get block skill (fresh lookup - moveset changes can add/remove skills)
function CombatController:getBlockSkill()
	local character = self:getCharacter()
	if not character then
		return nil
	end

	-- Always get fresh reference since moveset changes destroy/recreate skills
	return character:GetSkillFromConstructor(Block)
end

-- Get dodge skill (fresh lookup - moveset changes can add/remove skills)
function CombatController:getDodgeSkill()
	local character = self:getCharacter()
	if not character then
		return nil
	end

	-- Always get fresh reference since moveset changes destroy/recreate skills
	return character:GetSkillFromConstructor(Dodge)
end

-- Get heavy attack skill based on equipped weapon's CriticalSkill config
function CombatController:getHeavyAttackSkill()
	local character = self:getCharacter()
	if not character then
		return nil
	end

	if not self.equipmentController then
		return nil
	end

	local equipped = self.equipmentController:getEquipped()
	if not equipped then
		return nil
	end

	-- Look up which critical skill this weapon uses from equipment config
	local criticalSkillName = EquipmentManager.getCriticalSkillForWeapon(equipped)
	if not criticalSkillName then
		warn(`[CombatController] No CriticalSkill defined for weapon: {equipped}`)
		return nil
	end

	-- Get the skill constructor from lookup table
	local skillConstructor = CRITICAL_SKILLS[criticalSkillName]
	if not skillConstructor then
		warn(`[CombatController] Unknown CriticalSkill: {criticalSkillName} (add it to CRITICAL_SKILLS table)`)
		return nil
	end

	return character:GetSkillFromConstructor(skillConstructor)
end

-- Perform primary attack (M1)
function CombatController:performPrimaryAttack()
	-- If slot is selected, ensure equipment is ready first
	if self.equipmentController and self.equipmentController:getSelectedSlot() then
		-- Confirm equipment if needed (equips weapon, puts in hand, keeps selection)
		-- Returns true if weapon was just equipped, false if already equipped
		local justEquipped = self.equipmentController:confirmAction()

		-- If we just equipped, moveset change is async - skills might not be ready yet
		-- Continue to attack anyway - if skills aren't ready, attack will fail silently
		if justEquipped and self.sprintManager then
			self.sprintManager:stopSprint()
		end
		-- Continue to attack (don't return early)
	end

	-- Check if player has equipment equipped
	if not self.equipmentController or not self.equipmentController:getEquipped() then
		print("[CombatController] Cannot attack - No weapon equipped")
		return
	end

	-- Get the appropriate attack skill (Punch for fists, Slash for weapons)
	local attackSkill = self:getAttackSkill()
	if not attackSkill then
		-- No skill found - player might not have weapon in hand or equipped
		local equipped = self.equipmentController:getEquipped()
		if equipped and equipped ~= "fists" and not self.equipmentController:isWeaponInHand() then
			print("[CombatController] Cannot attack - Weapon not in hand (press slot key to draw)")
		end
		return
	end

	-- Check if character is guardbroken (completely stunned)
	local character = self:getCharacter()
	if character and character:HasStatusEffects({ Guardbroken }) then
		print("[CombatController] Cannot attack - Player is guardbroken")
		return
	end

	-- Check if skill is on cooldown
	local state = attackSkill:GetState()
	if state.Debounce then
		-- Don't update combo or print anything - skill is on cooldown
		return
	end

	-- Cancel sprint if active (only when actually attacking, after all checks pass)
	if self.sprintManager then
		self.sprintManager:stopSprint()
	end

	-- Execute the skill
	attackSkill:Start()
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

	-- Check if character is guardbroken (completely stunned)
	local character = self:getCharacter()
	if character and character:HasStatusEffects({ Guardbroken }) then
		print("[CombatController] Cannot dodge - Player is guardbroken")
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

	-- Send camera direction to server BEFORE starting skill (for airdash)
	local player = game:GetService("Players").LocalPlayer
	if player and player.Character then
		local hrp = player.Character:FindFirstChild("HumanoidRootPart")
		local humanoid = player.Character:FindFirstChild("Humanoid")

		if hrp and humanoid then
			-- Check if in air (same logic as dodge skill)
			local humanoidState = humanoid:GetState()
			local isInAirState = humanoidState == Enum.HumanoidStateType.Freefall
				or humanoidState == Enum.HumanoidStateType.Jumping

			-- Also do raycast to check height
			local rayOrigin = hrp.Position
			local rayDirection = Vector3.new(0, -5, 0)
			local raycastParams = RaycastParams.new()
			raycastParams.FilterDescendantsInstances = { player.Character }
			raycastParams.FilterType = Enum.RaycastFilterType.Exclude
			local raycastResult = workspace:Raycast(rayOrigin, rayDirection, raycastParams)
			local isGroundedByRaycast = raycastResult ~= nil

			local isGrounded = not isInAirState and isGroundedByRaycast

			-- If in air, send camera direction to server NOW (before skill activation)
			if not isGrounded then
				local camera = workspace.CurrentCamera
				if camera then
					local cameraLook = camera.CFrame.LookVector
					local airdashRemote = ReplicatedStorage:FindFirstChild("SetAirdashCamera")
					if airdashRemote then
						airdashRemote:FireServer(cameraLook)
						print(`[CombatController] Sent camera direction to server for airdash: {cameraLook}`)
					end
				end
			end
		end
	end

	print("[CombatController] performDodge: Starting dodge skill")
	-- Execute the dodge skill
	dodgeSkill:Start()
end

-- Perform heavy attack (R key)
function CombatController:performCriticalAttack()
	-- Check if player has equipment equipped
	if not self.equipmentController or not self.equipmentController:getEquipped() then
		print("[CombatController] Cannot heavy attack - No weapon equipped")
		return
	end

	-- For weapons (not fists), check if weapon is in hand
	local equipped = self.equipmentController:getEquipped()
	if equipped and equipped ~= "fists" and not self.equipmentController:isWeaponInHand() then
		print("[CombatController] Cannot heavy attack - Weapon not in hand (press slot key to draw)")
		return
	end

	-- Get the appropriate heavy attack skill (HeavyPunch for fists, HeavySlash for weapons)
	local heavySkill = self:getHeavyAttackSkill()
	if not heavySkill then
		print("[CombatController] performCriticalAttack: No heavy attack skill found on character")
		return
	end

	-- Check if character is guardbroken
	local character = self:getCharacter()
	if character and character:HasStatusEffects({ Guardbroken }) then
		print("[CombatController] Cannot heavy attack - Player is guardbroken")
		return
	end

	-- Check if skill is on cooldown
	local state = heavySkill:GetState()
	if state.Debounce then
		print("[CombatController] performCriticalAttack: Heavy attack is on cooldown")
		return
	end

	-- Cancel sprint if active
	if self.sprintManager then
		self.sprintManager:stopSprint()
	end

	print("[CombatController] performCriticalAttack: Starting heavy attack!")
	-- Execute the heavy attack skill
	heavySkill:Start()
end

-- Use ability from hotbar slot
function CombatController:useAbility(slotNumber: number)
	print(`[CombatController] Using ability slot {slotNumber} - Not implemented yet`)
	-- TODO: Get ability from hotbar and execute
end

return CombatController
