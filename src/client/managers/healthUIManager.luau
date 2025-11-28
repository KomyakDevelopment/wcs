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
	self.healthPercentageLabel = nil
	self.healthConnection = nil
	self.characterConnection = nil

	self:_setup()

	print("[HealthUIManager] Initialized")
	return self
end

function HealthUIManager:_setup()
	-- Find the health bar UI
	local playerGui = self.player:WaitForChild("PlayerGui")
	local mainGui = playerGui:WaitForChild("Main", 5)
	if mainGui then
		-- Try both case variants (HealthGui and HealthGUI)
		local healthGui = mainGui:FindFirstChild("HealthGui") or mainGui:FindFirstChild("HealthGUI")
		if healthGui then
			self.healthGuiName = healthGui.Name -- Store actual name for debugging
			local health = healthGui:FindFirstChild("Health")
			if health then
				self.healthBar = health:FindFirstChild("Bar")
				self.healthPercentageLabel = health:FindFirstChild("Percentage")
			end
		end
	end

	if not self.healthBar then
		warn("[HealthUIManager] Health bar not found - check Main.HealthGui.Health.Bar or Main.HealthGUI.Health.Bar")
	end
	if not self.healthPercentageLabel then
		warn("[HealthUIManager] Health percentage label not found")
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

	-- Update percentage text (e.g., "58%")
	if self.healthPercentageLabel then
		local percentageText = math.floor(percentage * 100)
		self.healthPercentageLabel.Text = `{percentageText}%`
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
