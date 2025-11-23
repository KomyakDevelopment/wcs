--!strict
-- Posture UI Manager
-- Client-side manager that updates the posture UI based on character attributes

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local PostureUIManager = {}
PostureUIManager.__index = PostureUIManager

function PostureUIManager.new()
	local self = setmetatable({}, PostureUIManager)

	self.player = Players.LocalPlayer
	self.postureLabel = nil
	self.attributeConnection = nil
	self.characterConnection = nil

	self:_setup()

	print("[PostureUIManager] Initialized")
	return self
end

function PostureUIManager:_setup()
	-- Find the placeholder UI
	local playerGui = self.player:WaitForChild("PlayerGui")
	local testingGui = playerGui:WaitForChild("Testing", 5)
	if testingGui then
		local frame = testingGui:FindFirstChild("Frame")
		if frame then
			self.postureLabel = frame:FindFirstChild("Posture")
		end
	end

	if not self.postureLabel then
		warn("[PostureUIManager] Posture label not found at StarterGui.Testing.Frame.Posture")
	end

	-- Setup for current character
	if self.player.Character then
		self:_setupCharacter(self.player.Character)
	end

	-- Setup for future characters
	self.characterConnection = self.player.CharacterAdded:Connect(function(character)
		self:_setupCharacter(character)
	end)
end

function PostureUIManager:_setupCharacter(character: Model)
	-- Disconnect previous attribute connection
	if self.attributeConnection then
		self.attributeConnection:Disconnect()
		self.attributeConnection = nil
	end

	-- Wait a moment for attributes to be set by server
	task.defer(function()
		-- Update UI immediately
		self:_updateUI(character)

		-- Listen for posture attribute changes
		self.attributeConnection = character:GetAttributeChangedSignal("Posture"):Connect(function()
			self:_updateUI(character)
		end)
	end)
end

function PostureUIManager:_updateUI(character: Model)
	if not self.postureLabel then
		return
	end

	local posture = character:GetAttribute("Posture") or 0
	local maxPosture = character:GetAttribute("MaxPosture") or 100

	-- Update the text label
	self.postureLabel.Text = string.format("P: %d/%d", math.floor(posture), math.floor(maxPosture))
end

function PostureUIManager:destroy()
	if self.attributeConnection then
		self.attributeConnection:Disconnect()
		self.attributeConnection = nil
	end
	if self.characterConnection then
		self.characterConnection:Disconnect()
		self.characterConnection = nil
	end
end

return PostureUIManager
