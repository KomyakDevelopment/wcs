--!strict
-- Combat Controller
-- Manages all combat-related actions, skill execution, and combo systems
-- This is a singleton that handles combat logic on the client

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local CombatConfig = require(ReplicatedStorage.Shared.config.combatConfig)

local WCS = require(ReplicatedStorage.Packages.wcs)
local Punch = require(ReplicatedStorage.Shared.skills.punch)
local Slash = require(ReplicatedStorage.Shared.skills.slash)
local Dodge = require(ReplicatedStorage.Shared.skills.dodge)
local Block = require(ReplicatedStorage.Shared.skills.block)
local HeavyPunch = require(ReplicatedStorage.Shared.skills.heavyPunch)
local HeavySlash = require(ReplicatedStorage.Shared.skills.heavySlash)
local HeavySwing = require(ReplicatedStorage.Shared.skills.heavySwing)

-- Equipment manager for looking up weapon configs
local EquipmentManager = require(ReplicatedStorage.Shared.managers.equipmentManager)

-- Status effects for validation
local Guardbroken = require(ReplicatedStorage.Shared.statusEffects.guardbroken)
local Attacking = require(ReplicatedStorage.Shared.statusEffects.attacking)
local HeavyAttacking = require(ReplicatedStorage.Shared.statusEffects.heavyAttacking)
local SoftHitstun = require(ReplicatedStorage.Shared.statusEffects.softHitstun)
local TrueHitstun = require(ReplicatedStorage.Shared.statusEffects.trueHitstun)
local Stun = require(ReplicatedStorage.Shared.statusEffects.stun)

-- Lookup table: maps CriticalSkill names to their constructors
-- Add new heavy attacks here when creating them
local CRITICAL_SKILLS = {
	HeavyPunch = HeavyPunch,
	HeavySlash = HeavySlash,
	HeavySwing = HeavySwing,
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

	-- Input buffer system
	local bufferConfig = CombatConfig.InputBuffer
	self.inputBufferEnabled = bufferConfig.EnabledByDefault
	self.inputBufferWindow = bufferConfig.BufferWindow
	self.blockBufferWindow = 1.5 -- Longer buffer window for block (covers full crit duration ~1.13s)
	self.inputBuffer = {
		m1 = { pressed = false, timestamp = 0 },
		heavy = { pressed = false, timestamp = 0 },
		dodge = { pressed = false, timestamp = 0 },
		block = { pressed = false, timestamp = 0 }, -- Block buffer for hold-based input
	}

	-- Track if block button is currently held
	self.blockHeld = false

	-- Hold to M1 system
	local holdToM1Config = CombatConfig.HoldToM1
	self.holdToM1Enabled = holdToM1Config.EnabledByDefault
	self.m1Held = false -- Track if M1 is currently held down

	-- Equip cooldown: prevents hold-to-M1 and buffer from attacking immediately after equipping
	self._equipCooldownUntil = 0

	-- Start buffer processing loop (also handles hold-to-M1)
	self._bufferConnection = RunService.Heartbeat:Connect(function()
		self:_processInputBuffer()
		self:_processHoldToM1()
	end)

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

		-- If we just equipped, don't also attack - player only wanted to equip
		if justEquipped then
			if self.sprintManager then
				self.sprintManager:stopSprint()
			end
			-- Set cooldown to prevent hold-to-M1 and buffer from triggering attack
			self._equipCooldownUntil = tick() + 0.15
			return
		end
	end

	-- Check if we can perform M1 right now
	if self:_canPerformM1() then
		self:_executeM1()
	else
		-- Buffer the input for later execution
		self:_bufferInput("m1")
	end
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
		self.blockHeld = true

		-- Cancel sprint if active
		if self.sprintManager then
			self.sprintManager:stopSprint()
		end

		-- Check if we can block right now
		if self:_canPerformBlock() then
			blockSkill:Start()
		else
			-- Buffer the block input for when we can block
			self:_bufferInput("block")
			print("[CombatController] Block buffered - waiting for attack to end")
		end
	elseif state == Enum.UserInputState.End then
		print("[CombatController] Block ended")
		self.blockHeld = false

		-- Clear block buffer when released
		self:_clearBuffer("block")

		-- Stop blocking
		blockSkill:End()
	end
end

-- Perform dodge action
function CombatController:performDodge()
	-- Check if we can perform dodge right now
	if self:_canPerformDodge() then
		self:_executeDodge()
	else
		-- Buffer the input for later execution
		self:_bufferInput("dodge")
	end
end

-- Perform heavy attack (R key)
function CombatController:performCriticalAttack()
	-- Check if we can perform heavy attack right now
	if self:_canPerformHeavy() then
		self:_executeHeavy()
	else
		-- Buffer the input for later execution
		self:_bufferInput("heavy")
	end
end

-- Use ability from hotbar slot
function CombatController:useAbility(slotNumber: number)
	print(`[CombatController] Using ability slot {slotNumber} - Not implemented yet`)
	-- TODO: Get ability from hotbar and execute
end

--============================================================================--
-- INPUT BUFFER SYSTEM
--============================================================================--

-- Toggle input buffering on/off (for player settings)
function CombatController:setInputBufferEnabled(enabled: boolean)
	self.inputBufferEnabled = enabled
	-- Clear any pending buffered inputs when disabling
	if not enabled then
		self:_clearAllBuffers()
	end
	print(`[CombatController] Input buffering {enabled and "enabled" or "disabled"}`)
end

-- Check if input buffering is enabled
function CombatController:isInputBufferEnabled(): boolean
	return self.inputBufferEnabled
end

-- Toggle hold-to-M1 on/off (for player settings)
function CombatController:setHoldToM1Enabled(enabled: boolean)
	self.holdToM1Enabled = enabled
	-- Release held state when disabling
	if not enabled then
		self.m1Held = false
	end
	print(`[CombatController] Hold-to-M1 {enabled and "enabled" or "disabled"}`)
end

-- Check if hold-to-M1 is enabled
function CombatController:isHoldToM1Enabled(): boolean
	return self.holdToM1Enabled
end

-- Set M1 held state (called from input binding)
function CombatController:setM1Held(held: boolean)
	self.m1Held = held
end

-- Process hold-to-M1 (called every frame)
function CombatController:_processHoldToM1()
	-- Skip if hold-to-M1 is disabled or M1 is not held
	if not self.holdToM1Enabled or not self.m1Held then
		return
	end

	-- Skip if in equip cooldown (just equipped a weapon, don't attack immediately)
	if tick() < self._equipCooldownUntil then
		return
	end

	-- Safety check: verify mouse is actually held down
	-- This catches edge cases where the End event was missed (e.g., window focus loss)
	if not UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1) then
		self.m1Held = false
		return
	end

	-- Try to execute M1 if we can
	if self:_canPerformM1() then
		self:_executeM1()
	end
end

-- Buffer an input for later execution
function CombatController:_bufferInput(action: string)
	if not self.inputBufferEnabled then
		return
	end

	self.inputBuffer[action] = {
		pressed = true,
		timestamp = tick(),
	}
end

-- Check if a buffered input is still valid (not expired)
function CombatController:_getBufferedInput(action: string): boolean
	local buffer = self.inputBuffer[action]
	if not buffer or not buffer.pressed then
		return false
	end

	-- Use longer buffer window for block
	local bufferWindow = action == "block" and self.blockBufferWindow or self.inputBufferWindow

	local age = tick() - buffer.timestamp
	if age > bufferWindow then
		buffer.pressed = false -- Expired
		return false
	end

	return true
end

-- Clear a specific buffer after execution
function CombatController:_clearBuffer(action: string)
	if self.inputBuffer[action] then
		self.inputBuffer[action].pressed = false
	end
end

-- Clear all buffers
function CombatController:_clearAllBuffers()
	for action, _ in pairs(self.inputBuffer) do
		self.inputBuffer[action].pressed = false
	end
end

-- Process buffered inputs each frame
function CombatController:_processInputBuffer()
	if not self.inputBufferEnabled then
		return
	end

	-- Check M1 buffer (respect equip cooldown)
	if self:_getBufferedInput("m1") then
		if tick() >= self._equipCooldownUntil and self:_canPerformM1() then
			self:_clearBuffer("m1")
			self:_executeM1()
		end
	end

	-- Check Heavy attack buffer
	if self:_getBufferedInput("heavy") then
		if self:_canPerformHeavy() then
			self:_clearBuffer("heavy")
			self:_executeHeavy()
		end
	end

	-- Check Dodge buffer
	if self:_getBufferedInput("dodge") then
		if self:_canPerformDodge() then
			self:_clearBuffer("dodge")
			self:_executeDodge()
		end
	end

	-- Check Block buffer (only execute if block button is still held)
	if self:_getBufferedInput("block") then
		if self.blockHeld and self:_canPerformBlock() then
			self:_clearBuffer("block")
			local blockSkill = self:getBlockSkill()
			if blockSkill then
				blockSkill:Start()
				print("[CombatController] Block executed from buffer")
			end
		end
	end
end

-- Check if M1 can be performed (without side effects)
function CombatController:_canPerformM1(): boolean
	if not self.equipmentController or not self.equipmentController:getEquipped() then
		return false
	end

	local attackSkill = self:getAttackSkill()
	if not attackSkill then
		return false
	end

	local character = self:getCharacter()
	if not character then
		return false
	end

	if character:HasStatusEffects({ Guardbroken }) then
		return false
	end

	-- Check if heavy attack is currently active (prevents M1 during heavy)
	local heavySkill = self:getHeavyAttackSkill()
	if heavySkill then
		local heavyState = heavySkill:GetState()
		if heavyState.IsActive then
			return false
		end
	end

	local state = attackSkill:GetState()
	if state.Debounce then
		return false
	end

	return true
end

-- Execute M1 (actual attack, no validation)
function CombatController:_executeM1()
	if self.sprintManager then
		self.sprintManager:stopSprint()
	end

	local attackSkill = self:getAttackSkill()
	if attackSkill then
		attackSkill:Start()
	end
end

-- Check if heavy attack can be performed
function CombatController:_canPerformHeavy(): boolean
	if not self.equipmentController or not self.equipmentController:getEquipped() then
		return false
	end

	local equipped = self.equipmentController:getEquipped()
	if equipped and equipped ~= "fists" and not self.equipmentController:isWeaponInHand() then
		return false
	end

	local heavySkill = self:getHeavyAttackSkill()
	if not heavySkill then
		return false
	end

	local character = self:getCharacter()
	if not character then
		return false
	end

	-- Check guardbroken, attacking, or any hitstun (prevents spam during endlag/flourish recovery)
	if character:HasStatusEffects({ Guardbroken, Attacking, HeavyAttacking, SoftHitstun, TrueHitstun, Stun }) then
		return false
	end

	local state = heavySkill:GetState()
	-- Check both debounce AND if skill is currently active
	if state.Debounce or state.IsActive then
		return false
	end

	return true
end

-- Execute heavy attack
function CombatController:_executeHeavy()
	if self.sprintManager then
		self.sprintManager:stopSprint()
	end

	local heavySkill = self:getHeavyAttackSkill()
	if heavySkill then
		heavySkill:Start()
	end
end

-- Check if dodge can be performed
function CombatController:_canPerformDodge(): boolean
	if self.dodgeDebounce then
		return false
	end

	local dodgeSkill = self:getDodgeSkill()
	if not dodgeSkill then
		return false
	end

	local character = self:getCharacter()
	if not character then
		return false
	end

	-- Check guardbroken OR attacking (can't dodge during attack windup/endlag)
	if character:HasStatusEffects({ Guardbroken, Attacking, HeavyAttacking }) then
		return false
	end

	-- Also check if M1 skill is currently active (client-side state for faster response)
	-- This catches the case where Attacking status hasn't replicated yet
	local punchSkill = self:getPunchSkill()
	if punchSkill then
		local punchState = punchSkill:GetState()
		if punchState.IsActive then
			return false
		end
	end

	local slashSkill = self:getSlashSkill()
	if slashSkill then
		local slashState = slashSkill:GetState()
		if slashState.IsActive then
			return false
		end
	end

	-- Also check heavy skills
	local heavySkill = self:getHeavyAttackSkill()
	if heavySkill then
		local heavyState = heavySkill:GetState()
		if heavyState.IsActive then
			return false
		end
	end

	local state = dodgeSkill:GetState()
	if state.Debounce then
		return false
	end

	return true
end

-- Check if block can be performed (for buffering)
-- This checks the main blocker: Attacking status
function CombatController:_canPerformBlock(): boolean
	local blockSkill = self:getBlockSkill()
	if not blockSkill then
		return false
	end

	local character = self:getCharacter()
	if not character then
		return false
	end

	-- Check if player is attacking (main reason for block buffer)
	if character:HasStatusEffects({ Attacking, HeavyAttacking }) then
		return false
	end

	-- Check if player is sprinting
	if character.Instance:GetAttribute("IsSprinting") == true then
		return false
	end

	return true
end

-- Execute dodge (handles airdash camera, etc.)
function CombatController:_executeDodge()
	self.dodgeDebounce = true
	task.delay(0.5, function()
		self.dodgeDebounce = false
	end)

	if self.sprintManager then
		self.sprintManager:stopSprint()
	end

	-- Handle airdash camera direction
	local player = Players.LocalPlayer
	if player and player.Character then
		local hrp = player.Character:FindFirstChild("HumanoidRootPart")
		local humanoid = player.Character:FindFirstChild("Humanoid")

		if hrp and humanoid then
			local humanoidState = humanoid:GetState()
			local isInAirState = humanoidState == Enum.HumanoidStateType.Freefall
				or humanoidState == Enum.HumanoidStateType.Jumping

			local rayOrigin = hrp.Position
			local rayDirection = Vector3.new(0, -5, 0)
			local raycastParams = RaycastParams.new()
			raycastParams.FilterDescendantsInstances = { player.Character }
			raycastParams.FilterType = Enum.RaycastFilterType.Exclude
			local raycastResult = workspace:Raycast(rayOrigin, rayDirection, raycastParams)
			local isGroundedByRaycast = raycastResult ~= nil

			local isGrounded = not isInAirState and isGroundedByRaycast

			if not isGrounded then
				local camera = workspace.CurrentCamera
				if camera then
					local cameraLook = camera.CFrame.LookVector
					local airdashRemote = ReplicatedStorage:FindFirstChild("SetAirdashCamera")
					if airdashRemote then
						airdashRemote:FireServer(cameraLook)
					end
				end
			end
		end
	end

	local dodgeSkill = self:getDodgeSkill()
	if dodgeSkill then
		dodgeSkill:Start()
	end
end

-- Cleanup (call when controller is destroyed)
function CombatController:destroy()
	if self._bufferConnection then
		self._bufferConnection:Disconnect()
		self._bufferConnection = nil
	end
end

return CombatController
