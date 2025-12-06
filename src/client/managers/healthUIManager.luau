--!strict
-- Health UI Manager
-- Client-side manager that updates the health bar based on humanoid health

local Players = game:GetService("Players")

local HealthUIManager = {}
HealthUIManager.__index = HealthUIManager

function HealthUIManager.new()
	local self = setmetatable({}, HealthUIManager)

	self.player = Players.LocalPlayer
	self.healthBar = nil
	self.healthConnection = nil
	self.characterConnection = nil

	self:_setup()

	print("[HealthUIManager] Initialized")
	return self
end

function HealthUIManager:_setup()
	-- Find the health bar UI at new path: Main.NGUI.ScreenGui.main_bars.health.bar
	local playerGui = self.player:WaitForChild("PlayerGui")
	local mainGui = playerGui:WaitForChild("Main", 5)
	if mainGui then
		local ngui = mainGui:FindFirstChild("NGUI")
		if ngui then
			local screenGui = ngui:FindFirstChild("ScreenGui")
			if screenGui then
				local mainBars = screenGui:FindFirstChild("main_bars")
				if mainBars then
					local health = mainBars:FindFirstChild("health")
					if health then
						self.healthBar = health:FindFirstChild("bar")
					end
				end
			end
		end
	end

	if not self.healthBar then
		warn("[HealthUIManager] Health bar not found at Main.NGUI.ScreenGui.main_bars.health.bar")
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

function HealthUIManager:_setupCharacter(character: Model)
	-- Disconnect previous health connection
	if self.healthConnection then
		self.healthConnection:Disconnect()
		self.healthConnection = nil
	end

	-- Wait for humanoid
	local humanoid = character:WaitForChild("Humanoid", 5) :: Humanoid?
	if not humanoid then
		warn("[HealthUIManager] Humanoid not found")
		return
	end

	-- Update UI immediately
	self:_updateUI(humanoid)

	-- Listen for health changes
	self.healthConnection = humanoid.HealthChanged:Connect(function()
		self:_updateUI(humanoid)
	end)

	print("[HealthUIManager] Setup complete for character")
end

function HealthUIManager:_updateUI(humanoid: Humanoid)
	local currentHealth = humanoid.Health
	local maxHealth = humanoid.MaxHealth

	-- Calculate percentage (0 to 1)
	local percentage = currentHealth / maxHealth

	-- Update the bar size (only X size, keep Y at {1, 0})
	if self.healthBar then
		self.healthBar.Size = UDim2.fromScale(percentage, 1)
	end
end

function HealthUIManager:destroy()
	if self.healthConnection then
		self.healthConnection:Disconnect()
		self.healthConnection = nil
	end
	if self.characterConnection then
		self.characterConnection:Disconnect()
		self.characterConnection = nil
	end
end

return HealthUIManager
