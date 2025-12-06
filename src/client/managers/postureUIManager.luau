--!strict
-- Posture UI Manager
-- Client-side manager that updates the posture bar based on character attributes

local Players = game:GetService("Players")

local PostureUIManager = {}
PostureUIManager.__index = PostureUIManager

function PostureUIManager.new()
	local self = setmetatable({}, PostureUIManager)

	self.player = Players.LocalPlayer
	self.postureBar = nil
	self.attributeConnection = nil
	self.characterConnection = nil

	self:_setup()

	print("[PostureUIManager] Initialized")
	return self
end

function PostureUIManager:_setup()
	-- Find the posture bar UI at new path: Main.NGUI.ScreenGui.main_bars.posture.bar
	local playerGui = self.player:WaitForChild("PlayerGui")
	local mainGui = playerGui:WaitForChild("Main", 5)
	if mainGui then
		local ngui = mainGui:FindFirstChild("NGUI")
		if ngui then
			local screenGui = ngui:FindFirstChild("ScreenGui")
			if screenGui then
				local mainBars = screenGui:FindFirstChild("main_bars")
				if mainBars then
					local posture = mainBars:FindFirstChild("posture")
					if posture then
						self.postureBar = posture:FindFirstChild("bar")
					end
				end
			end
		end
	end

	if not self.postureBar then
		warn("[PostureUIManager] Posture bar not found at Main.NGUI.ScreenGui.main_bars.posture.bar")
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

	-- Wait for server to set posture attributes (with timeout)
	task.spawn(function()
		local timeout = 5
		local startTime = tick()

		-- Wait for MaxPosture attribute to exist (indicates server initialized posture)
		while character.Parent and not character:GetAttribute("MaxPosture") do
			if tick() - startTime > timeout then
				warn("[PostureUIManager] Timeout waiting for posture attributes")
				return
			end
			task.wait(0.1)
		end

		-- Character might have been destroyed while waiting
		if not character.Parent then
			return
		end

		-- Update UI immediately
		self:_updateUI(character)

		-- Listen for posture attribute changes
		self.attributeConnection = character:GetAttributeChangedSignal("Posture"):Connect(function()
			self:_updateUI(character)
		end)

		print("[PostureUIManager] Setup complete for character")
	end)
end

function PostureUIManager:_updateUI(character: Model)
	local posture = (character:GetAttribute("Posture") or 0) :: number
	local maxPosture = (character:GetAttribute("MaxPosture") or 100) :: number

	-- Calculate percentage (0 to 1)
	local percentage = posture / maxPosture

	-- Update the bar size (only X size, keep Y at {1, 0})
	if self.postureBar then
		self.postureBar.Size = UDim2.fromScale(percentage, 1)
	end
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
