--!strict
-- Grip Effects Manager (Client)
-- Handles grip animations for ALL players (not just local player)
-- This ensures victim animations play even if the victim's Grip skill isn't active

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

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

	-- Movement freeze state for local player when gripping
	self._isLocalPlayerGripping = false
	self._originalWalkSpeed = nil :: number?
	self._originalJumpPower = nil :: number?
	self._originalAutoRotate = nil :: boolean?
	self._freezeEnforcementConnection = nil :: RBXScriptConnection?

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

	-- If local player is the attacker, freeze their movement completely
	if attacker == self._player.Character then
		self:_freezeLocalPlayer()
	end

	print(`[GripEffectsManager] Grip started: {attacker.Name} -> {victim.Name}`)
end

function GripEffectsManager:_onGripCancel(attacker: Model, victim: Model)
	-- Stop animations
	self:_stopAnimation(attacker)
	self:_stopAnimation(victim)

	-- If local player was the attacker, unfreeze their movement
	if attacker == self._player.Character then
		self:_unfreezeLocalPlayer()
	end

	print(`[GripEffectsManager] Grip cancelled: {attacker.Name} -> {victim.Name}`)
end

function GripEffectsManager:_onExecuted(executedCharacter: Model, killerCharacter: Model?)
	-- Stop animation on the executed player
	self:_stopAnimation(executedCharacter)

	-- Stop animation on the killer too
	if killerCharacter then
		self:_stopAnimation(killerCharacter)

		-- If local player was the killer, unfreeze their movement
		if killerCharacter == self._player.Character then
			self:_unfreezeLocalPlayer()
		end
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

-- Freeze local player's movement and rotation during grip
function GripEffectsManager:_freezeLocalPlayer()
	if self._isLocalPlayerGripping then
		return -- Already frozen
	end

	local character = self._player.Character
	if not character then
		return
	end

	local humanoid = character:FindFirstChild("Humanoid") :: Humanoid?
	if not humanoid then
		return
	end

	-- Store original values
	self._originalWalkSpeed = humanoid.WalkSpeed
	self._originalJumpPower = humanoid.JumpPower
	self._originalAutoRotate = humanoid.AutoRotate

	-- Freeze everything initially
	humanoid.WalkSpeed = 0
	humanoid.JumpPower = 0
	humanoid.AutoRotate = false

	self._isLocalPlayerGripping = true

	-- Start continuous enforcement to prevent other systems from overriding
	if self._freezeEnforcementConnection then
		self._freezeEnforcementConnection:Disconnect()
	end

	self._freezeEnforcementConnection = RunService.Heartbeat:Connect(function()
		local char = self._player.Character
		if not char then return end

		local hum = char:FindFirstChild("Humanoid") :: Humanoid?
		if not hum then return end

		-- Force freeze every frame
		if hum.WalkSpeed ~= 0 then
			hum.WalkSpeed = 0
		end
		if hum.JumpPower ~= 0 then
			hum.JumpPower = 0
		end
		if hum.AutoRotate ~= false then
			hum.AutoRotate = false
		end
	end)

	print(`[GripEffectsManager] Froze local player with continuous enforcement`)
end

-- Unfreeze local player's movement and rotation after grip
function GripEffectsManager:_unfreezeLocalPlayer()
	if not self._isLocalPlayerGripping then
		return -- Not frozen
	end

	-- Stop enforcement loop FIRST
	if self._freezeEnforcementConnection then
		self._freezeEnforcementConnection:Disconnect()
		self._freezeEnforcementConnection = nil
	end

	local character = self._player.Character
	if not character then
		self._isLocalPlayerGripping = false
		return
	end

	local humanoid = character:FindFirstChild("Humanoid") :: Humanoid?
	if not humanoid then
		self._isLocalPlayerGripping = false
		return
	end

	-- Restore original values
	humanoid.WalkSpeed = self._originalWalkSpeed or 16
	humanoid.JumpPower = self._originalJumpPower or 50
	humanoid.AutoRotate = if self._originalAutoRotate ~= nil then self._originalAutoRotate else true

	self._isLocalPlayerGripping = false
	self._originalWalkSpeed = nil
	self._originalJumpPower = nil
	self._originalAutoRotate = nil

	print(`[GripEffectsManager] Unfroze local player - movement restored`)
end

function GripEffectsManager:destroy()
	-- Stop enforcement connection first
	if self._freezeEnforcementConnection then
		self._freezeEnforcementConnection:Disconnect()
		self._freezeEnforcementConnection = nil
	end

	-- Unfreeze local player if still gripping
	if self._isLocalPlayerGripping then
		self:_unfreezeLocalPlayer()
	end

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
