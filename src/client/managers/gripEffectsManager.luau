--!strict
-- Grip Effects Manager (Client)
-- Handles grip animations for ALL players (not just local player)
-- This ensures victim animations play even if the victim's Grip skill isn't active

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GripEffectsManager = {}
GripEffectsManager.__index = GripEffectsManager

-- Animation IDs
local GRIP_ATTACKER_ANIMATION = "rbxassetid://130414330071752"
local GRIP_VICTIM_ANIMATION = "rbxassetid://78865882601929"

function GripEffectsManager.new()
	local self = setmetatable({}, GripEffectsManager)

	self._player = Players.LocalPlayer
	self._connections = {} :: { RBXScriptConnection }
	self._activeAnimations = {} :: { [Model]: AnimationTrack } -- character -> animation track

	self:_setup()

	print("[GripEffectsManager] Initialized")
	return self
end

function GripEffectsManager:_setup()
	-- Wait for remotes
	local gripStartRemote = ReplicatedStorage:WaitForChild("GripStart", 10) :: RemoteEvent?
	local gripCancelRemote = ReplicatedStorage:WaitForChild("GripCancelBroadcast", 10) :: RemoteEvent?
	local executedRemote = ReplicatedStorage:WaitForChild("PlayerExecuted", 10) :: RemoteEvent?

	if gripStartRemote then
		table.insert(self._connections, gripStartRemote.OnClientEvent:Connect(function(attacker: Model, victim: Model)
			self:_onGripStart(attacker, victim)
		end))
	end

	if gripCancelRemote then
		table.insert(self._connections, gripCancelRemote.OnClientEvent:Connect(function(attacker: Model, victim: Model)
			self:_onGripCancel(attacker, victim)
		end))
	end

	if executedRemote then
		table.insert(self._connections, executedRemote.OnClientEvent:Connect(function(executedCharacter: Model, killerCharacter: Model?)
			self:_onExecuted(executedCharacter, killerCharacter)
		end))
	end
end

function GripEffectsManager:_onGripStart(attacker: Model, victim: Model)
	-- Play animations for ALL players (not just local) so spectators can see
	-- Each client handles playing animations on all characters
	self:_playAnimation(attacker, GRIP_ATTACKER_ANIMATION, "attacker")
	self:_playAnimation(victim, GRIP_VICTIM_ANIMATION, "victim")

	print(`[GripEffectsManager] Grip started: {attacker.Name} -> {victim.Name}`)
end

function GripEffectsManager:_onGripCancel(attacker: Model, victim: Model)
	-- Stop animations
	self:_stopAnimation(attacker)
	self:_stopAnimation(victim)

	print(`[GripEffectsManager] Grip cancelled: {attacker.Name} -> {victim.Name}`)
end

function GripEffectsManager:_onExecuted(executedCharacter: Model, killerCharacter: Model?)
	-- Stop animation on the executed player
	self:_stopAnimation(executedCharacter)

	-- Stop animation on the killer too
	if killerCharacter then
		self:_stopAnimation(killerCharacter)
	end

	print(`[GripEffectsManager] Execution complete: {executedCharacter.Name}`)
end

function GripEffectsManager:_playAnimation(character: Model, animationId: string, role: string)
	local humanoid = character:FindFirstChild("Humanoid") :: Humanoid?
	if not humanoid then
		warn(`[GripEffectsManager] No humanoid on {character.Name}`)
		return
	end

	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		warn(`[GripEffectsManager] No animator on {character.Name}`)
		return
	end

	-- Stop any existing grip animation on this character
	self:_stopAnimation(character)

	-- Create and load the animation
	local anim = Instance.new("Animation")
	anim.AnimationId = animationId
	local track = animator:LoadAnimation(anim)
	track.Priority = Enum.AnimationPriority.Action4
	track.Looped = false
	track:Play(0.1)

	-- Store reference for cleanup
	self._activeAnimations[character] = track

	print(`[GripEffectsManager] Playing {role} animation on {character.Name}`)
end

function GripEffectsManager:_stopAnimation(character: Model)
	local track = self._activeAnimations[character]
	if track then
		if track.IsPlaying then
			track:Stop(0.2)
		end
		self._activeAnimations[character] = nil
		print(`[GripEffectsManager] Stopped animation on {character.Name}`)
	end
end

function GripEffectsManager:destroy()
	-- Stop all active animations
	for character, _ in pairs(self._activeAnimations) do
		self:_stopAnimation(character)
	end

	for _, connection in ipairs(self._connections) do
		connection:Disconnect()
	end
	self._connections = {}
end

return GripEffectsManager
