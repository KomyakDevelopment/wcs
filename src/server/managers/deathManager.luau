--!strict
-- Death Manager (Server)
-- Handles knockdown system: when HP reaches 0, player ragdolls for 6 seconds then gets back up
-- No actual death occurs - player recovers after the knockdown timer

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- WCS for status effects
local WCS = require(ReplicatedStorage.Packages.wcs)
local Knockdown = require(ReplicatedStorage.Shared.statusEffects.knockdown)
local EasyRagdoll = require(ReplicatedStorage.Shared.managers.easyRagdoll)

-- Configuration
local KNOCKDOWN_DURATION = 6.0 -- Seconds before getting back up
local MIN_KNOCKDOWN_HP = 1 -- Minimum HP while knocked down (prevents death)
local POST_RECOVERY_IMMUNITY = 8.0 -- Seconds of immunity AFTER recovery (generous buffer)

-- Remote events
local knockdownRemote: RemoteEvent = nil

local DeathManager = {}
DeathManager.__index = DeathManager

function DeathManager.new()
	local self = setmetatable({}, DeathManager)

	self._connections = {} :: { RBXScriptConnection }
	self._knockedPlayers = {} :: { [Player]: boolean } -- Track players currently knocked down
	self._knockdownTimers = {} :: { [Player]: thread } -- Track knockdown timer threads
	self._knockdownHealthConnections = {} :: { [Player]: RBXScriptConnection } -- Health protection while knocked
	self._knockdownStatusEffects = {} :: { [Player]: any } -- Track Knockdown status effects
	self._recoveryTime = {} :: { [Player]: number } -- Track when player RECOVERED (for post-recovery immunity)
	self._executingPlayers = {} :: { [Player]: boolean } -- Track players being executed (skip knockdown)
	self._executionHealthConnections = {} :: { [Player]: RBXScriptConnection } -- Prevent regen during execution
	self._executionLeavers = {} :: { [number]: boolean } -- Track UserIds that left during execution (death on rejoin)

	self:_setup()

	print("[DeathManager] Initialized (Knockdown System)")
	return self
end

function DeathManager:_setup()
	-- Create knockdown remote if it doesn't exist
	knockdownRemote = ReplicatedStorage:FindFirstChild("PlayerKnockdown") :: RemoteEvent
	if not knockdownRemote then
		knockdownRemote = Instance.new("RemoteEvent")
		knockdownRemote.Name = "PlayerKnockdown"
		knockdownRemote.Parent = ReplicatedStorage
	end

	-- Initialize for existing players
	for _, player in ipairs(Players:GetPlayers()) do
		if player.Character then
			self:_setupCharacter(player, player.Character)
		end
	end

	-- Handle new players joining
	table.insert(
		self._connections,
		Players.PlayerAdded:Connect(function(player)
			-- Check if this player left during execution (combat log)
			if self._executionLeavers[player.UserId] then
				print(`[DeathManager] {player.Name} rejoined after leaving during execution - death will be counted`)
				self._executionLeavers[player.UserId] = nil -- Clear the flag

				-- Wait for their character, then kill them immediately
				player.CharacterAdded:Once(function(character)
					task.wait(0.5) -- Brief delay to let character fully load
					local humanoid = character:FindFirstChild("Humanoid") :: Humanoid?
					if humanoid then
						humanoid.BreakJointsOnDeath = true
						humanoid.Health = 0
						print(`[DeathManager] {player.Name} killed for leaving during execution`)
					end
				end)
			end

			player.CharacterAdded:Connect(function(character)
				self:_setupCharacter(player, character)
			end)
		end)
	)

	-- Handle players leaving - track if they left during execution
	table.insert(
		self._connections,
		Players.PlayerRemoving:Connect(function(player)
			-- If player was being executed, mark them for death on rejoin
			if self._executingPlayers[player] then
				self._executionLeavers[player.UserId] = true
				print(`[DeathManager] {player.Name} left during execution - death will be counted on rejoin`)
			end

			-- Clean up all state for this player
			self._knockedPlayers[player] = nil
			self._executingPlayers[player] = nil
			self._recoveryTime[player] = nil

			if self._knockdownTimers[player] then
				task.cancel(self._knockdownTimers[player])
				self._knockdownTimers[player] = nil
			end

			if self._knockdownHealthConnections[player] then
				self._knockdownHealthConnections[player]:Disconnect()
				self._knockdownHealthConnections[player] = nil
			end

			if self._executionHealthConnections[player] then
				self._executionHealthConnections[player]:Disconnect()
				self._executionHealthConnections[player] = nil
			end

			if self._knockdownStatusEffects[player] then
				-- Don't call End() - player is leaving anyway
				self._knockdownStatusEffects[player] = nil
			end
		end)
	)

	-- Handle existing players' future characters
	for _, player in ipairs(Players:GetPlayers()) do
		table.insert(
			self._connections,
			player.CharacterAdded:Connect(function(character)
				self:_setupCharacter(player, character)
			end)
		)
	end
end

function DeathManager:_setupCharacter(player: Player, character: Model)
	local humanoid = character:WaitForChild("Humanoid", 5) :: Humanoid?
	if not humanoid then
		warn(`[DeathManager] Humanoid not found for {player.Name}`)
		return
	end

	-- Clear any execution/knockdown state from previous character (respawn cleanup)
	self._executingPlayers[player] = nil
	self._knockedPlayers[player] = nil
	self._recoveryTime[player] = nil

	-- Disconnect any execution health clamp from previous character
	if self._executionHealthConnections[player] then
		self._executionHealthConnections[player]:Disconnect()
		self._executionHealthConnections[player] = nil
	end

	-- Disable BreakJointsOnDeath so we can handle knockdown instead
	humanoid.BreakJointsOnDeath = false

	-- Track player's HP to detect instant-kills vs combat knockdowns
	local lastKnownHP = humanoid.Health

	-- Listen for health changes to intercept "death"
	humanoid.HealthChanged:Connect(function(newHealth)
		-- When health reaches 0 or below, trigger knockdown instead of death
		-- Skip if already knocked, being executed, or in recovery grace period
		if newHealth <= 0 and not self._knockedPlayers[player] then
			-- Skip if player is being executed (let them actually die)
			if self._executingPlayers[player] then
				print(`[DeathManager] {player.Name} is being executed - allowing death`)
				lastKnownHP = 0
				return
			end

			-- Check post-recovery immunity - prevents re-knockdown after recently recovering
			-- Also check the KnockdownImmunity attribute as a backup
			local recoveryTime = self._recoveryTime[player]
			local hasImmunityAttr = character:GetAttribute("KnockdownImmunity") == true
			if (recoveryTime and (tick() - recoveryTime) < POST_RECOVERY_IMMUNITY) or hasImmunityAttr then
				-- In immunity window - set HP to minimum to prevent 0 HP oscillation
				-- This gives regen a stable base to work from
				humanoid.Health = MIN_KNOCKDOWN_HP
				lastKnownHP = MIN_KNOCKDOWN_HP
				local remaining = recoveryTime and (POST_RECOVERY_IMMUNITY - (tick() - recoveryTime)) or POST_RECOVERY_IMMUNITY
				print(`[DeathManager] {player.Name} post-recovery immunity ({string.format("%.1f", math.max(0, remaining))}s remaining) - HP set to {MIN_KNOCKDOWN_HP}`)
				return
			end

			-- Check if this was an instant-kill (void, massive damage) vs combat knockdown
			-- If they had significant HP before being knocked, it's an instant-kill
			-- Exception: Players carrying someone should always go to knockdown (gives them a chance)
			local instantKillThreshold = humanoid.MaxHealth * 0.15 -- 15% of max HP
			local isCarrying = character:GetAttribute("Carrying") == true

			if lastKnownHP > instantKillThreshold and not isCarrying then
				-- Instant-kill: they had decent HP but got one-shot (void, ability, etc.)
				print(`[DeathManager] {player.Name} instant-killed (had {lastKnownHP} HP, threshold {instantKillThreshold}) - auto-executing`)
				self:_autoExecuteImmediate(player, character, humanoid)
			else
				-- Combat knockdown: they were already low HP from taking hits
				-- OR they were carrying someone (drops the target, gives them a chance)
				if isCarrying then
					print(`[DeathManager] {player.Name} was carrying someone - combat knockdown instead of instant-kill`)
				else
					print(`[DeathManager] {player.Name} combat knockdown (had {lastKnownHP} HP, now {newHealth})`)
				end
				self:_handleKnockdown(player, character, humanoid)
			end
		end

		-- Update last known HP (but not below 0)
		lastKnownHP = math.max(0, newHealth)
	end)
end

-- Auto-execute immediately for instant-kills (void, massive damage when player had decent HP)
function DeathManager:_autoExecuteImmediate(player: Player, character: Model, humanoid: Humanoid)
	-- Mark as executing to prevent any knockdown logic
	self._executingPlayers[player] = true

	-- Mark character for execution (used by client UI)
	character:SetAttribute("MarkedForExecution", true)

	-- Lock HP at 1 to keep them "alive" until they click continue
	humanoid.Health = MIN_KNOCKDOWN_HP

	-- Setup health connection to keep HP locked at 1
	if self._executionHealthConnections[player] then
		self._executionHealthConnections[player]:Disconnect()
	end
	self._executionHealthConnections[player] = humanoid.HealthChanged:Connect(function(newHealth)
		if self._executingPlayers[player] and newHealth ~= MIN_KNOCKDOWN_HP then
			humanoid.Health = MIN_KNOCKDOWN_HP
		end
	end)

	-- Fire PlayerExecuted event to show death UI (same as grip)
	-- Pass nil as killer for environmental/void deaths
	local executeRemote = ReplicatedStorage:FindFirstChild("PlayerExecuted") :: RemoteEvent?
	if executeRemote then
		print(`[DeathManager] Firing PlayerExecuted for {player.Name} (instant-kill, no killer)`)
		executeRemote:FireAllClients(character, nil) -- nil killer = environmental death
	end

	-- Player will respawn when they click "Continue" via ConfirmExecution remote
	-- (handled in init.server.luau)
end

function DeathManager:_handleKnockdown(player: Player, character: Model, humanoid: Humanoid)
	-- Prevent double-handling
	if self._knockedPlayers[player] then
		return
	end

	self._knockedPlayers[player] = true

	-- Clear any previous recovery time and immunity (new knockdown starts fresh)
	self._recoveryTime[player] = nil
	character:SetAttribute("KnockdownImmunity", nil)

	print(`[DeathManager] {player.Name} knocked down`)

	-- CRITICAL: Keep player alive by setting HP to minimum
	humanoid.Health = MIN_KNOCKDOWN_HP

	-- Apply Knockdown status effect to block all skills
	local wcsCharacter = WCS.Character.GetCharacterFromInstance(character)
	if wcsCharacter then
		local knockdownEffect = Knockdown.new(wcsCharacter)
		if knockdownEffect then
			knockdownEffect:Start(-1) -- Infinite duration until manually ended
			self._knockdownStatusEffects[player] = knockdownEffect
			print(`[DeathManager] Applied Knockdown status effect to {player.Name}`)
		end
	end

	-- Set knockdown-specific properties
	humanoid.PlatformStand = true

	-- Lock movement
	humanoid.WalkSpeed = 0
	humanoid.JumpPower = 0
	humanoid.JumpHeight = 0

	-- Enable ragdoll via trigger system (handles AutoRotate, Physics state, etc.)
	EasyRagdoll.SetRagdoll(character, true, true, 100)

	-- Fire knockdown event to all clients (for any client-side effects)
	knockdownRemote:FireAllClients(character, true)

	-- Track previous HP to detect overkill damage
	local previousHP = MIN_KNOCKDOWN_HP

	-- Setup health protection while knocked down
	-- M1 damage: clamps to 1 HP and resets timer (never auto-executes)
	-- Overkill damage (void, abilities dealing more than current HP): auto-executes
	self._knockdownHealthConnections[player] = humanoid.HealthChanged:Connect(function(newHealth)
		if not self._knockedPlayers[player] then
			return
		end

		-- Only process if health went DOWN (ignore regen)
		if newHealth >= previousHP then
			previousHP = newHealth
			return
		end

		-- Calculate damage taken
		local damageTaken = previousHP - newHealth

		-- Check if this was M1 damage (never auto-execute from M1s)
		local wasM1Damage = character:GetAttribute("LastDamageWasM1") == true
		-- Clear the attribute immediately after reading
		character:SetAttribute("LastDamageWasM1", nil)

		-- Check for overkill damage (damage >= previous HP means lethal hit like void/ability)
		-- BUT only auto-execute if it was NOT M1 damage
		if damageTaken >= previousHP and not wasM1Damage then
			print(`[DeathManager] {player.Name} took overkill damage ({damageTaken} >= {previousHP}) while knocked - auto-executing`)
			self:_autoExecuteKnocked(player, character, humanoid)
			return
		end

		-- Normal damage (or M1 damage) - clamp to minimum HP and reset timer
		if newHealth < MIN_KNOCKDOWN_HP then
			humanoid.Health = MIN_KNOCKDOWN_HP
			previousHP = MIN_KNOCKDOWN_HP
			if wasM1Damage then
				print(`[DeathManager] {player.Name} hit by M1 while knocked - HP protected (M1s never auto-execute)`)
			else
				print(`[DeathManager] {player.Name} hit while knocked - HP protected`)
			end

			-- Reset the knockdown timer ONLY if not being carried
			-- (carried players have paused knockdown, don't restart it)
			if not character:GetAttribute("BeingCarried") then
				if self._knockdownTimers[player] then
					task.cancel(self._knockdownTimers[player])
				end
				self._knockdownTimers[player] = task.delay(KNOCKDOWN_DURATION, function()
					self:_handleRecovery(player, character, humanoid)
				end)
				print(`[DeathManager] {player.Name} knockdown timer reset to {KNOCKDOWN_DURATION}s`)
			else
				print(`[DeathManager] {player.Name} is being carried - knockdown timer NOT reset`)
			end
		else
			previousHP = newHealth
		end
	end)

	-- Start recovery timer
	self._knockdownTimers[player] = task.delay(KNOCKDOWN_DURATION, function()
		self:_handleRecovery(player, character, humanoid)
	end)
end

function DeathManager:_handleRecovery(player: Player, character: Model, humanoid: Humanoid)
	-- Check if player/character still exists FIRST (before any state changes)
	if not player or not player.Parent then
		self._knockedPlayers[player] = nil
		self._knockdownTimers[player] = nil
		return
	end

	if not character or not character.Parent then
		self._knockedPlayers[player] = nil
		self._knockdownTimers[player] = nil
		return
	end

	if not humanoid then
		self._knockedPlayers[player] = nil
		self._knockdownTimers[player] = nil
		return
	end

	-- CRITICAL: Set HP to minimum BEFORE disconnecting health protection
	-- This ensures HP is never 0 when recovery completes, preventing the "stiff" bug
	if humanoid.Health <= 0 then
		humanoid.Health = MIN_KNOCKDOWN_HP
		print(`[DeathManager] {player.Name} HP was 0 at recovery start - set to {MIN_KNOCKDOWN_HP}`)
	end

	-- Set recovery time for post-recovery immunity
	self._recoveryTime[player] = tick()

	-- Set immunity attribute on character so other systems can check
	character:SetAttribute("KnockdownImmunity", true)

	-- Schedule removal of immunity attribute
	task.delay(POST_RECOVERY_IMMUNITY, function()
		if character and character.Parent then
			character:SetAttribute("KnockdownImmunity", nil)
		end
	end)

	print(`[DeathManager] {player.Name} recovering - {POST_RECOVERY_IMMUNITY}s immunity started`)

	-- Disconnect health protection
	if self._knockdownHealthConnections[player] then
		self._knockdownHealthConnections[player]:Disconnect()
		self._knockdownHealthConnections[player] = nil
	end

	-- End Knockdown status effect
	if self._knockdownStatusEffects[player] then
		self._knockdownStatusEffects[player]:End()
		self._knockdownStatusEffects[player] = nil
		print(`[DeathManager] Ended Knockdown status effect for {player.Name}`)
	end

	print(`[DeathManager] {player.Name} recovering from knockdown`)

	-- Clear all velocities BEFORE disabling ragdoll to prevent flinging
	for _, part in ipairs(character:GetDescendants()) do
		if part:IsA("BasePart") then
			part.AssemblyLinearVelocity = Vector3.zero
			part.AssemblyAngularVelocity = Vector3.zero
		end
	end

	-- Disable ragdoll via trigger system (handles velocities, upright position, AutoRotate, Running state)
	EasyRagdoll.SetRagdoll(character, false)

	-- Restore knockdown-specific properties
	humanoid.PlatformStand = false

	-- Restore movement
	humanoid.WalkSpeed = 16 -- Default walk speed
	humanoid.JumpPower = 50 -- Default jump power
	humanoid.JumpHeight = 7.2 -- Default jump height

	-- Don't set HP on recovery - Roblox's automatic health regen handles HP restoration
	-- The grace period protects them from knockdown while their HP regenerates
	print(`[DeathManager] {player.Name} HP at recovery: {humanoid.Health}/{humanoid.MaxHealth} (regen will heal)`)

	-- Fire recovery event to all clients
	knockdownRemote:FireAllClients(character, false)

	-- Clear knockdown state
	self._knockedPlayers[player] = nil
	self._knockdownTimers[player] = nil

	print(`[DeathManager] {player.Name} recovered (HP: {humanoid.Health}/{humanoid.MaxHealth})`)
end

-- Auto-execute a knocked player who took lethal damage (overkill from void, abilities, etc.)
function DeathManager:_autoExecuteKnocked(player: Player, _character: Model, humanoid: Humanoid)
	-- Mark as executing FIRST to prevent HealthChanged from re-triggering knockdown
	self._executingPlayers[player] = true

	-- Cancel the knockdown timer
	if self._knockdownTimers[player] then
		task.cancel(self._knockdownTimers[player])
		self._knockdownTimers[player] = nil
	end

	-- Disconnect knockdown health protection
	if self._knockdownHealthConnections[player] then
		self._knockdownHealthConnections[player]:Disconnect()
		self._knockdownHealthConnections[player] = nil
	end

	-- End knockdown status effect
	if self._knockdownStatusEffects[player] then
		self._knockdownStatusEffects[player]:End()
		self._knockdownStatusEffects[player] = nil
	end

	-- Clear knockdown state
	self._knockedPlayers[player] = nil

	-- Enable BreakJointsOnDeath so death properly breaks the character
	humanoid.BreakJointsOnDeath = true

	-- Kill the player
	humanoid.Health = 0

	-- Clear executing state and respawn after a short delay
	task.delay(1.0, function()
		self._executingPlayers[player] = nil
		if player and player.Parent then
			player:LoadCharacter()
			print(`[DeathManager] {player.Name} respawned after lethal damage while knocked`)
		end
	end)
end

-- Check if a player is currently knocked down
function DeathManager:isKnockedDown(player: Player): boolean
	return self._knockedPlayers[player] == true
end

-- Pause knockdown timer (for carry - player is being carried so shouldn't recover)
function DeathManager:pauseKnockdown(player: Player)
	if not self._knockedPlayers[player] then return end

	-- Cancel the knockdown timer
	if self._knockdownTimers[player] then
		task.cancel(self._knockdownTimers[player])
		self._knockdownTimers[player] = nil
		print(`[DeathManager] {player.Name} knockdown timer paused (being carried)`)
	end
end

-- Resume knockdown timer (for carry drop - restart the timer)
function DeathManager:resumeKnockdown(player: Player)
	if not self._knockedPlayers[player] then return end

	local character = player.Character
	if not character then return end

	local humanoid = character:FindFirstChild("Humanoid") :: Humanoid?
	if not humanoid then return end

	-- Re-apply knockdown movement restrictions
	humanoid.PlatformStand = true
	humanoid.WalkSpeed = 0
	humanoid.JumpPower = 0
	humanoid.JumpHeight = 0

	-- Re-enable ragdoll
	EasyRagdoll.SetRagdoll(character, true, true, 100)

	-- Start fresh knockdown timer
	if self._knockdownTimers[player] then
		task.cancel(self._knockdownTimers[player])
	end
	self._knockdownTimers[player] = task.delay(KNOCKDOWN_DURATION, function()
		self:_handleRecovery(player, character, humanoid)
	end)

	print(`[DeathManager] {player.Name} knockdown timer resumed ({KNOCKDOWN_DURATION}s) with movement restrictions restored`)
end

-- Check if a player is marked for execution (grip in progress)
function DeathManager:isMarkedForExecution(player: Player): boolean
	return self._executingPlayers[player] == true
end

-- Mark a player for execution - stops regen, gives complete iframes, disables collision
-- Called by grip skill when grip starts (before the actual execution)
-- Does NOT disable ragdoll - keeps them ragdolled during grip animation
function DeathManager:markForExecution(player: Player)
	print(`[DeathManager] Marking {player.Name} for execution (complete protection)`)

	-- Mark as being executed early (prevents any knockdown re-triggers)
	self._executingPlayers[player] = true

	-- Cancel knockdown timer (they won't recover anymore)
	if self._knockdownTimers[player] then
		task.cancel(self._knockdownTimers[player])
		self._knockdownTimers[player] = nil
	end

	-- Disconnect knockdown health protection
	if self._knockdownHealthConnections[player] then
		self._knockdownHealthConnections[player]:Disconnect()
		self._knockdownHealthConnections[player] = nil
	end

	-- Disconnect any existing execution health connection
	if self._executionHealthConnections[player] then
		self._executionHealthConnections[player]:Disconnect()
		self._executionHealthConnections[player] = nil
	end

	local character = player.Character
	if character then
		local humanoid = character:FindFirstChild("Humanoid") :: Humanoid?
		if humanoid then
			-- Set HP to 1 (1%) - low but safe, won't cause accidental death
			humanoid.Health = 1

			-- Add connection to PREVENT any health changes during execution
			-- This blocks both damage AND regen - complete protection
			self._executionHealthConnections[player] = humanoid.HealthChanged:Connect(function(newHealth)
				-- Keep HP locked at 1 no matter what
				if self._executingPlayers[player] and newHealth ~= 1 then
					humanoid.Health = 1
				end
			end)

			print(`[DeathManager] {player.Name} HP locked at 1 (complete protection)`)
		end

		-- Set attribute so clients know this player is being executed (hides interaction UI)
		character:SetAttribute("MarkedForExecution", true)

		-- Set collision group to "Players" so they don't collide with other players
		-- but still collide with the ground (won't fall through terrain)
		-- "Players" collision group is configured to not collide with itself
		for _, part in ipairs(character:GetDescendants()) do
			if part:IsA("BasePart") then
				part.CollisionGroup = "Players"
			end
		end
		print(`[DeathManager] {player.Name} collision group set to Players (no player collision)`)
	end
end

-- Cancel an execution in progress (grip was cancelled before completion)
-- Restores the player to knockdown state with a fresh timer
function DeathManager:cancelExecution(player: Player)
	print(`[DeathManager] Cancelling execution for {player.Name}`)

	-- Clear execution state
	self._executingPlayers[player] = nil

	-- Disconnect execution health clamp
	if self._executionHealthConnections[player] then
		self._executionHealthConnections[player]:Disconnect()
		self._executionHealthConnections[player] = nil
	end

	local character = player.Character
	if not character then return end

	local humanoid = character:FindFirstChild("Humanoid") :: Humanoid?
	if not humanoid then return end

	-- Clear the MarkedForExecution attribute
	character:SetAttribute("MarkedForExecution", nil)

	-- Always restore to knockdown state (don't check PlatformStand - ragdoll might have been disabled during grip)
	-- Mark as knocked
	self._knockedPlayers[player] = true

	-- Restore HP to minimum
	humanoid.Health = MIN_KNOCKDOWN_HP

	-- Re-apply knockdown movement restrictions
	humanoid.PlatformStand = true
	humanoid.WalkSpeed = 0
	humanoid.JumpPower = 0
	humanoid.JumpHeight = 0

	-- Re-enable ragdoll
	EasyRagdoll.SetRagdoll(character, true, true, 100)

	-- Re-apply knockdown health protection
	if self._knockdownHealthConnections[player] then
		self._knockdownHealthConnections[player]:Disconnect()
	end
	local previousHP = MIN_KNOCKDOWN_HP
	self._knockdownHealthConnections[player] = humanoid.HealthChanged:Connect(function(newHealth)
		if not self._knockedPlayers[player] then return end
		if newHealth >= previousHP then
			previousHP = newHealth
			return
		end
		local damageTaken = previousHP - newHealth
		local wasM1Damage = character:GetAttribute("LastDamageWasM1") == true
		character:SetAttribute("LastDamageWasM1", nil)
		if damageTaken >= previousHP and not wasM1Damage then
			self:_autoExecuteKnocked(player, character, humanoid)
			return
		end
		if newHealth < MIN_KNOCKDOWN_HP then
			humanoid.Health = MIN_KNOCKDOWN_HP
			previousHP = MIN_KNOCKDOWN_HP
			if self._knockdownTimers[player] then
				task.cancel(self._knockdownTimers[player])
			end
			self._knockdownTimers[player] = task.delay(KNOCKDOWN_DURATION, function()
				self:_handleRecovery(player, character, humanoid)
			end)
		else
			previousHP = newHealth
		end
	end)

	-- Start fresh knockdown timer
	if self._knockdownTimers[player] then
		task.cancel(self._knockdownTimers[player])
	end
	self._knockdownTimers[player] = task.delay(KNOCKDOWN_DURATION, function()
		self:_handleRecovery(player, character, humanoid)
	end)

	-- Re-apply knockdown status effect if needed
	local wcsCharacter = WCS.Character.GetCharacterFromInstance(character)
	if wcsCharacter and not self._knockdownStatusEffects[player] then
		local knockdownEffect = Knockdown.new(wcsCharacter)
		if knockdownEffect then
			knockdownEffect:Start(-1)
			self._knockdownStatusEffects[player] = knockdownEffect
		end
	end

	print(`[DeathManager] {player.Name} returned to knockdown state with fresh {KNOCKDOWN_DURATION}s timer`)
end

-- Prepare a player for execution (clear all knockdown protection so they can die)
-- Called by grip skill right before killing the target
function DeathManager:prepareForExecution(player: Player)
	print(`[DeathManager] Preparing {player.Name} for execution`)

	-- Mark player as being executed (prevents re-knockdown when HP hits 0)
	self._executingPlayers[player] = true

	-- Cancel knockdown timer
	if self._knockdownTimers[player] then
		task.cancel(self._knockdownTimers[player])
		self._knockdownTimers[player] = nil
	end

	-- Disconnect knockdown health protection so HP can go to 0
	if self._knockdownHealthConnections[player] then
		self._knockdownHealthConnections[player]:Disconnect()
		self._knockdownHealthConnections[player] = nil
	end

	-- Disconnect execution health clamp (so HP can go to 0)
	if self._executionHealthConnections[player] then
		self._executionHealthConnections[player]:Disconnect()
		self._executionHealthConnections[player] = nil
	end

	-- End knockdown status effect
	if self._knockdownStatusEffects[player] then
		self._knockdownStatusEffects[player]:End()
		self._knockdownStatusEffects[player] = nil
	end

	-- Clear knockdown state
	self._knockedPlayers[player] = nil
	self._recoveryTime[player] = nil

	-- Disable ragdoll on the character and clear immunity
	local character = player.Character
	if character then
		character:SetAttribute("KnockdownImmunity", nil)
		-- Disable ragdoll via trigger system (handles AutoRotate, Running state, etc.)
		EasyRagdoll.SetRagdoll(character, false)

		local humanoid = character:FindFirstChild("Humanoid") :: Humanoid?
		if humanoid then
			-- Restore knockdown-specific property
			humanoid.PlatformStand = false
		end
	end

	print(`[DeathManager] {player.Name} ready for execution (knockdown protection removed)`)
end

function DeathManager:destroy()
	-- Cancel all knockdown timers
	for _, timerThread in pairs(self._knockdownTimers) do
		task.cancel(timerThread)
	end
	self._knockdownTimers = {}
	self._knockedPlayers = {}
	self._recoveryTime = {}
	self._executingPlayers = {}
	self._executionLeavers = {}

	-- End all knockdown status effects
	for _, effect in pairs(self._knockdownStatusEffects) do
		effect:End()
	end
	self._knockdownStatusEffects = {}

	-- Disconnect all knockdown health protection connections
	for _, connection in pairs(self._knockdownHealthConnections) do
		connection:Disconnect()
	end
	self._knockdownHealthConnections = {}

	-- Disconnect all execution health clamp connections
	for _, connection in pairs(self._executionHealthConnections) do
		connection:Disconnect()
	end
	self._executionHealthConnections = {}

	for _, connection in ipairs(self._connections) do
		connection:Disconnect()
	end
	self._connections = {}
end

return DeathManager
