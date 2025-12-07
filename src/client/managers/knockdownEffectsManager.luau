--!strict
-- Knockdown Effects Manager (Client)
-- Handles client-side effects for knockdown system (UI, sounds, etc.)
-- NOTE: Camera and shiftlock are now handled by ragdollClient.client.luau via RagdollTrigger

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local KnockdownEffectsManager = {}
KnockdownEffectsManager.__index = KnockdownEffectsManager

function KnockdownEffectsManager.new()
	local self = setmetatable({}, KnockdownEffectsManager)

	self._player = Players.LocalPlayer
	self._connections = {} :: { RBXScriptConnection }
	self._isKnockedDown = false

	self:_setup()

	print("[KnockdownEffectsManager] Initialized")
	return self
end

function KnockdownEffectsManager:_setup()
	-- Wait for knockdown remote
	local knockdownRemote = ReplicatedStorage:WaitForChild("PlayerKnockdown", 10) :: RemoteEvent?
	if knockdownRemote then
		table.insert(
			self._connections,
			knockdownRemote.OnClientEvent:Connect(function(character: Model, isKnockedDown: boolean)
				self:_handleKnockdownEvent(character, isKnockedDown)
			end)
		)
	else
		warn("[KnockdownEffectsManager] PlayerKnockdown remote not found")
	end
end

function KnockdownEffectsManager:_handleKnockdownEvent(character: Model, isKnockedDown: boolean)
	-- Check if this is our character
	if character ~= self._player.Character then
		return
	end

	if isKnockedDown then
		self:_onKnockdown(character)
	else
		self:_onRecovery(character)
	end
end

function KnockdownEffectsManager:_onKnockdown(_character: Model)
	if self._isKnockedDown then
		return
	end
	self._isKnockedDown = true

	print("[KnockdownEffectsManager] Local player knocked down")

	-- Camera and shiftlock are now handled by ragdollClient.client.luau
	-- Add any knockdown-specific UI effects here (screen effects, sounds, etc.)
end

function KnockdownEffectsManager:_onRecovery(_character: Model)
	if not self._isKnockedDown then
		return
	end
	self._isKnockedDown = false

	print("[KnockdownEffectsManager] Local player recovering")

	-- Camera is now restored by ragdollClient.client.luau
	-- Add any recovery-specific UI effects here
end

function KnockdownEffectsManager:isKnockedDown(): boolean
	return self._isKnockedDown
end

function KnockdownEffectsManager:destroy()
	for _, connection in ipairs(self._connections) do
		connection:Disconnect()
	end
	self._connections = {}
end

return KnockdownEffectsManager
