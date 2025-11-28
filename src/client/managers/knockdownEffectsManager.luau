--!strict
-- Knockdown Effects Manager (Client)
-- Handles client-side effects for knockdown system (camera, UI, etc.)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local KnockdownEffectsManager = {}
KnockdownEffectsManager.__index = KnockdownEffectsManager

function KnockdownEffectsManager.new()
	local self = setmetatable({}, KnockdownEffectsManager)

	self._player = Players.LocalPlayer
	self._connections = {} :: { RBXScriptConnection }
	self._isKnockedDown = false
	self._originalCameraSubject = nil

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

function KnockdownEffectsManager:_onKnockdown(character: Model)
	if self._isKnockedDown then
		return
	end
	self._isKnockedDown = true

	print("[KnockdownEffectsManager] Local player knocked down")

	-- Store original camera subject
	local camera = workspace.CurrentCamera
	if camera then
		self._originalCameraSubject = camera.CameraSubject
	end

	-- Switch camera to follow head for better ragdoll view
	local head = character:FindFirstChild("Head") :: BasePart?
	if head and camera then
		camera.CameraSubject = head
	end
end

function KnockdownEffectsManager:_onRecovery(character: Model)
	if not self._isKnockedDown then
		return
	end
	self._isKnockedDown = false

	print("[KnockdownEffectsManager] Local player recovering")

	-- Restore camera subject
	local camera = workspace.CurrentCamera
	local humanoid = character:FindFirstChild("Humanoid") :: Humanoid?

	if camera and humanoid then
		camera.CameraSubject = humanoid
	end

	self._originalCameraSubject = nil
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
