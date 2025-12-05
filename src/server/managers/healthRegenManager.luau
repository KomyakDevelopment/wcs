--!strict
-- HealthRegenManager
-- Custom health regeneration system that respects combat tag status
-- Disables Roblox's default health regen and implements our own

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

-- Configuration
local REGEN_RATE_OUT_OF_COMBAT = 5 -- HP per second (when not in combat)
local REGEN_RATE_IN_COMBAT = 0.5 -- HP per second (when in combat) = 1 HP per 2 seconds
local REGEN_DELAY = 3 -- Seconds after taking damage before regen starts
local UPDATE_INTERVAL = 0.5 -- How often to apply regen (seconds)

local HealthRegenManager = {}
HealthRegenManager.__index = HealthRegenManager

-- Singleton instance
local instance: HealthRegenManager? = nil

export type HealthRegenManager = typeof(setmetatable({} :: {
	_connections: { RBXScriptConnection },
	_lastDamageTime: { [Player]: number },
}, HealthRegenManager))

function HealthRegenManager.new(): HealthRegenManager
	if instance then
		return instance
	end

	local self = setmetatable({
		_connections = {} :: { RBXScriptConnection },
		_lastDamageTime = {} :: { [Player]: number },
	}, HealthRegenManager)

	self:_setup()

	instance = self
	print("[HealthRegenManager] Initialized")
	return self
end

function HealthRegenManager:_setup()
	-- Handle existing players
	for _, player in ipairs(Players:GetPlayers()) do
		self:_setupPlayer(player)
	end

	-- Handle new players
	local playerAddedConn = Players.PlayerAdded:Connect(function(player)
		self:_setupPlayer(player)
	end)
	table.insert(self._connections, playerAddedConn)

	-- Clean up when players leave
	local playerRemovingConn = Players.PlayerRemoving:Connect(function(player)
		self._lastDamageTime[player] = nil
	end)
	table.insert(self._connections, playerRemovingConn)

	-- Regen loop
	local lastUpdate = 0
	local heartbeatConn = RunService.Heartbeat:Connect(function()
		local now = os.clock()
		if now - lastUpdate < UPDATE_INTERVAL then
			return
		end
		lastUpdate = now

		self:_regenLoop()
	end)
	table.insert(self._connections, heartbeatConn)
end

function HealthRegenManager:_setupPlayer(player: Player)
	-- Handle character spawning
	local function onCharacterAdded(character: Model)
		self:_setupCharacter(player, character)
	end

	if player.Character then
		onCharacterAdded(player.Character)
	end

	local charAddedConn = player.CharacterAdded:Connect(onCharacterAdded)
	table.insert(self._connections, charAddedConn)
end

function HealthRegenManager:_setupCharacter(player: Player, character: Model)
	local humanoid = character:WaitForChild("Humanoid", 5) :: Humanoid?
	if not humanoid then
		return
	end

	-- Disable Roblox's default health regeneration
	-- This prevents the built-in 1% per second regen after 10 seconds
	local healthScript = character:FindFirstChild("Health")
	if healthScript then
		healthScript:Destroy()
		print(`[HealthRegenManager] Disabled default health regen for {player.Name}`)
	end

	-- Track when player takes damage
	local healthConn = humanoid.HealthChanged:Connect(function(newHealth)
		-- If health decreased, record damage time
		if newHealth < humanoid.MaxHealth then
			local prevHealth = humanoid:GetAttribute("_PrevHealth") or humanoid.MaxHealth
			if newHealth < prevHealth then
				self._lastDamageTime[player] = os.clock()
			end
		end
		humanoid:SetAttribute("_PrevHealth", newHealth)
	end)

	-- Clean up connection when humanoid dies
	humanoid.Died:Once(function()
		healthConn:Disconnect()
		self._lastDamageTime[player] = nil
	end)

	-- Initialize previous health tracking
	humanoid:SetAttribute("_PrevHealth", humanoid.Health)
end

function HealthRegenManager:_regenLoop()
	local now = os.clock()

	for _, player in ipairs(Players:GetPlayers()) do
		local character = player.Character
		if not character then
			continue
		end

		local humanoid = character:FindFirstChild("Humanoid") :: Humanoid?
		if not humanoid or humanoid.Health <= 0 then
			continue
		end

		-- Don't regen if at full health
		if humanoid.Health >= humanoid.MaxHealth then
			continue
		end

		-- Check if in combat
		local isInCombat = _G.CombatTagManager and _G.CombatTagManager:isTagged(player)

		-- Don't regen if recently took damage (applies to both in/out of combat)
		local lastDamage = self._lastDamageTime[player]
		if lastDamage and (now - lastDamage) < REGEN_DELAY then
			continue
		end

		-- Apply regen based on combat state
		local regenRate = isInCombat and REGEN_RATE_IN_COMBAT or REGEN_RATE_OUT_OF_COMBAT
		local regenAmount = regenRate * UPDATE_INTERVAL
		local newHealth = math.min(humanoid.Health + regenAmount, humanoid.MaxHealth)
		humanoid.Health = newHealth
	end
end

function HealthRegenManager:destroy()
	for _, conn in ipairs(self._connections) do
		conn:Disconnect()
	end
	self._connections = {}
	self._lastDamageTime = {}
	instance = nil
end

return HealthRegenManager
