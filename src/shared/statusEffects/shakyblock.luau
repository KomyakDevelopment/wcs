--!strict
-- Shakyblock Status Effect
-- Applied when a player fails a parry (was blocking but got hit anyway)
-- Disables parrying ability for duration to punish failed parries

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Players = game:GetService("Players")

local WCS = require(ReplicatedStorage.Packages.wcs)

local Shakyblock = WCS.RegisterStatusEffect("Shakyblock")

function Shakyblock:OnConstructServer()
	-- Store reference to prevent duplicate shakyblocks
	if self.Character._ActiveShakyblock then
		self.Character._ActiveShakyblock:Stop()
	end
	self.Character._ActiveShakyblock = self
end

function Shakyblock:OnStartServer()
	local character = self.Character

	-- Set flag on WCS Character to disable parrying
	character.HasShakyblock = true

	-- Replicate state to clients via metadata
	self:SetMetadata({
		Active = true,
		Type = "Shakyblock",
	})

	print(`[Shakyblock] Applied to {character.Instance.Name} - Parrying disabled`)
end

function Shakyblock:OnEndServer()
	-- Only clear flag if this is the active shakyblock
	if self.Character._ActiveShakyblock == self then
		self.Character.HasShakyblock = false
		self.Character._ActiveShakyblock = nil
	end

	-- Clear metadata
	self:SetMetadata({
		Active = false,
		Type = nil,
	})

	print(`[Shakyblock] Ended on {self.Character.Instance.Name}`)
end

function Shakyblock:OnStartClient()
	-- Show visual indicator (tween in the shaky_block frame)
	self:_showShakyBlockIndicator()

	print("[Shakyblock] Client effect started")
end

function Shakyblock:OnEndClient()
	-- Hide visual indicator (tween out the shaky_block frame)
	self:_hideShakyBlockIndicator()

	print("[Shakyblock] Client effect ended")
end

-- Show the shaky block visual indicator
function Shakyblock:_showShakyBlockIndicator()
	if not RunService:IsClient() then
		return
	end

	local player = Players.LocalPlayer
	if not player then
		return
	end

	-- Only show for the local player
	local character = self.Character.Instance
	if character ~= player.Character then
		return
	end

	local shakyBlockFrame = Players.LocalPlayer.PlayerGui:FindFirstChild("Main")
		and Players.LocalPlayer.PlayerGui.Main:FindFirstChild("PostureGUI")
		and Players.LocalPlayer.PlayerGui.Main.PostureGUI:FindFirstChild("Posture")
		and Players.LocalPlayer.PlayerGui.Main.PostureGUI.Posture:FindFirstChild("shaky_block")

	if not shakyBlockFrame then
		warn("[Shakyblock] Could not find shaky_block frame")
		return
	end

	-- Tween in (fade in and scale up)
	shakyBlockFrame.Visible = true
	shakyBlockFrame.BackgroundTransparency = 1
	shakyBlockFrame.Size = UDim2.fromScale(0.8, 0.8)

	local tweenInfo = TweenInfo.new(
		0.2, -- Duration
		Enum.EasingStyle.Back, -- Easing style (bouncy effect)
		Enum.EasingDirection.Out
	)

	local tweenGoal = {
		BackgroundTransparency = 0,
		Size = UDim2.fromScale(1, 1),
	}

	local tween = TweenService:Create(shakyBlockFrame, tweenInfo, tweenGoal)
	tween:Play()

	print("[Shakyblock] Showing visual indicator")
end

-- Hide the shaky block visual indicator
function Shakyblock:_hideShakyBlockIndicator()
	if not RunService:IsClient() then
		return
	end

	local player = Players.LocalPlayer
	if not player then
		return
	end

	-- Only hide for the local player
	local character = self.Character.Instance
	if character ~= player.Character then
		return
	end

	local shakyBlockFrame = Players.LocalPlayer.PlayerGui:FindFirstChild("Main")
		and Players.LocalPlayer.PlayerGui.Main:FindFirstChild("PostureGUI")
		and Players.LocalPlayer.PlayerGui.Main.PostureGUI:FindFirstChild("Posture")
		and Players.LocalPlayer.PlayerGui.Main.PostureGUI.Posture:FindFirstChild("shaky_block")

	if not shakyBlockFrame then
		return
	end

	-- Tween out (fade out and scale down)
	local tweenInfo = TweenInfo.new(
		0.2, -- Duration
		Enum.EasingStyle.Quad,
		Enum.EasingDirection.In
	)

	local tweenGoal = {
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(0.8, 0.8),
	}

	local tween = TweenService:Create(shakyBlockFrame, tweenInfo, tweenGoal)
	tween:Play()

	-- Hide after tween completes
	tween.Completed:Connect(function()
		shakyBlockFrame.Visible = false
	end)

	print("[Shakyblock] Hiding visual indicator")
end

return Shakyblock
