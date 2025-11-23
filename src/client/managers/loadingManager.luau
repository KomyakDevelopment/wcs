--!strict
-- Loading Manager (Client)
-- Shows a black screen while waiting for server to be ready
-- Preloads assets and waits for required remotes

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ContentProvider = game:GetService("ContentProvider")
local TweenService = game:GetService("TweenService")

-- Required remote events that must exist before game starts
local REQUIRED_REMOTES = {
	"EquipWeapon",
	"PlayHitEffects",
	"PlayParryFlashVFX",
	"PlayParryVFX",
	"PlayBlockHitVFX",
	"PlayBlockHitAnimation",
	"PlayParriedAnimation",
	"PlayerDeath",
	"PlayRollCancel",
}

-- Assets to preload (animation IDs, sounds, etc.)
local PRELOAD_ASSETS = {
	-- Add animation IDs here as needed
	-- "rbxassetid://123456789",
}

local FADE_OUT_DURATION = 0.5
local TIMEOUT = 30 -- Max seconds to wait before giving up

local LoadingManager = {}
LoadingManager.__index = LoadingManager

function LoadingManager.new()
	local self = setmetatable({}, LoadingManager)

	self.player = Players.LocalPlayer
	self.loadingGui = nil :: ScreenGui?
	self.loadingFrame = nil :: Frame?
	self.isReady = false

	self:_createLoadingScreen()

	print("[LoadingManager] Initialized - showing loading screen")
	return self
end

function LoadingManager:_createLoadingScreen()
	local playerGui = self.player:WaitForChild("PlayerGui")

	-- Create ScreenGui
	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "LoadingGui"
	screenGui.IgnoreGuiInset = true
	screenGui.DisplayOrder = 1000 -- On top of everything
	screenGui.ResetOnSpawn = false
	screenGui.Parent = playerGui

	-- Create black frame
	local frame = Instance.new("Frame")
	frame.Name = "LoadingFrame"
	frame.Size = UDim2.new(1, 0, 1, 0)
	frame.Position = UDim2.new(0, 0, 0, 0)
	frame.BackgroundColor3 = Color3.new(0, 0, 0)
	frame.BackgroundTransparency = 0
	frame.BorderSizePixel = 0
	frame.ZIndex = 100
	frame.Parent = screenGui

	self.loadingGui = screenGui
	self.loadingFrame = frame
end

-- Wait for all required remotes to exist
function LoadingManager:waitForRemotes(): boolean
	print("[LoadingManager] Waiting for server remotes...")

	local startTime = tick()

	for _, remoteName in ipairs(REQUIRED_REMOTES) do
		local remote = ReplicatedStorage:WaitForChild(remoteName, TIMEOUT)
		if not remote then
			warn(`[LoadingManager] Timeout waiting for remote: {remoteName}`)
			return false
		end

		-- Check timeout
		if tick() - startTime > TIMEOUT then
			warn("[LoadingManager] Overall timeout reached")
			return false
		end
	end

	print("[LoadingManager] All remotes found")
	return true
end

-- Preload assets
function LoadingManager:preloadAssets()
	if #PRELOAD_ASSETS == 0 then
		return
	end

	print(`[LoadingManager] Preloading {#PRELOAD_ASSETS} assets...`)

	local assets = {}
	for _, assetId in ipairs(PRELOAD_ASSETS) do
		table.insert(assets, assetId)
	end

	ContentProvider:PreloadAsync(assets)
	print("[LoadingManager] Asset preloading complete")
end

-- Wait for character to be ready
function LoadingManager:waitForCharacter(): boolean
	print("[LoadingManager] Waiting for character...")

	local character = self.player.Character or self.player.CharacterAdded:Wait()
	local humanoid = character:WaitForChild("Humanoid", 10)

	if not humanoid then
		warn("[LoadingManager] Character humanoid not found")
		return false
	end

	print("[LoadingManager] Character ready")
	return true
end

-- Main loading sequence
function LoadingManager:load(): boolean
	-- Wait for remotes
	if not self:waitForRemotes() then
		return false
	end

	-- Preload assets
	self:preloadAssets()

	-- Wait for character
	if not self:waitForCharacter() then
		return false
	end

	self.isReady = true
	print("[LoadingManager] Loading complete - ready to play")
	return true
end

-- Fade out the loading screen
function LoadingManager:fadeOut()
	if not self.loadingFrame then
		return
	end

	local tweenInfo = TweenInfo.new(FADE_OUT_DURATION, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	local tween = TweenService:Create(self.loadingFrame, tweenInfo, { BackgroundTransparency = 1 })

	tween:Play()
	tween.Completed:Wait()

	-- Destroy the loading GUI
	if self.loadingGui then
		self.loadingGui:Destroy()
		self.loadingGui = nil
		self.loadingFrame = nil
	end

	print("[LoadingManager] Loading screen hidden")
end

-- Clean up
function LoadingManager:destroy()
	if self.loadingGui then
		self.loadingGui:Destroy()
		self.loadingGui = nil
		self.loadingFrame = nil
	end
end

return LoadingManager
