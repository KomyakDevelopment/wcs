--!strict
-- Menu Manager (Client)
-- Handles the initial loading screen and continue menu flow
-- UI instances are expected in ReplicatedFirst (placed in Studio)

local ReplicatedFirst = game:GetService("ReplicatedFirst")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

local MusicManager = require(ReplicatedStorage.Client.managers.musicManager)
local AudioConfig = require(ReplicatedStorage.Shared.config.audioConfig)

local player = Players.LocalPlayer

-- Cinematic camera position
local CAMERA_POSITION = Vector3.new(-570.256, 553.223, 8264.481)

-- Smooth camera pan settings
local PAN_SMOOTHNESS = 0.1 -- Lower = smoother/slower follow (0.05-0.15 is good)
local MAX_PAN_OFFSET_X = 3 -- Max horizontal pan in studs
local MAX_PAN_OFFSET_Y = 3 -- Max vertical pan in studs
local MOUSE_INFLUENCE = 0.008 -- How much mouse affects camera

local MenuManager = {}
MenuManager.__index = MenuManager

function MenuManager.new()
	local self = setmetatable({}, MenuManager)

	self._initialScreenGui = nil :: ScreenGui?
	self._continueScreenGui = nil :: ScreenGui?
	self._panConnection = nil :: RBXScriptConnection?
	self._streamingConnection = nil :: RBXScriptConnection?
	self._baseCameraCFrame = nil :: CFrame?
	self._keyPressConnection = nil :: RBXScriptConnection?
	self._continueConnection = nil :: RBXScriptConnection?

	-- Current smoothed offset (for lerping)
	self._currentOffsetX = 0
	self._currentOffsetY = 0

	self:_initialize()

	return self
end

-- Enable the main game UI (called after fade to black, before fade out)
function MenuManager:_enableGameUI()
	local playerGui = player:WaitForChild("PlayerGui")

	-- Wait for Main ScreenGui (may not have replicated from StarterGui yet)
	local mainGui = playerGui:WaitForChild("Main", 10) :: ScreenGui?
	if mainGui and mainGui:IsA("ScreenGui") then
		mainGui.Enabled = true
		print("[MenuManager] Enabled Main ScreenGui")
	else
		warn("[MenuManager] Main ScreenGui not found in PlayerGui after 10s wait")
	end

	-- Wait for HotbarUI ScreenGui
	local hotbarGui = playerGui:WaitForChild("HotbarUI", 5) :: ScreenGui?
	if hotbarGui and hotbarGui:IsA("ScreenGui") then
		hotbarGui.Enabled = true
		print("[MenuManager] Enabled HotbarUI ScreenGui")
	else
		warn("[MenuManager] HotbarUI ScreenGui not found after 5s wait")
	end
end

function MenuManager:_initialize()
	-- Remove Roblox's default loading screen IMMEDIATELY (prevents black frame)
	ReplicatedFirst:RemoveDefaultLoadingScreen()

	-- Start loading screen music IMMEDIATELY (earliest possible moment)
	MusicManager.playMusicFromPath(AudioConfig.Music.Tracks.LoadingScreen, AudioConfig.Music.MenuFadeIn)
	print("[MenuManager] Started loading screen music")

	local playerGui = player:WaitForChild("PlayerGui")

	-- Check if ReplicatedFirst script already created the loading screen
	-- If so, take ownership of it; otherwise create it ourselves
	self._initialScreenGui = playerGui:FindFirstChild("InitialLoadingScreen") :: ScreenGui?

	local clonedInitialUI: Frame?

	if self._initialScreenGui then
		-- ReplicatedFirst already created it - just get the UI reference
		clonedInitialUI = self._initialScreenGui:FindFirstChildOfClass("Frame")
		print("[MenuManager] Taking over InitialLoadingScreen from ReplicatedFirst")
	else
		-- Fallback: Create it ourselves (ReplicatedFirst script not present)
		-- Position camera FIRST
		local camera = workspace.CurrentCamera
		camera.CameraType = Enum.CameraType.Scriptable
		camera.CFrame = CFrame.new(CAMERA_POSITION)

		-- Look for UI in ReplicatedFirst (placed in Studio)
		local initialScreen = ReplicatedFirst:FindFirstChild("InitialScreen")
		if not initialScreen then
			warn("[MenuManager] InitialScreen not found in ReplicatedFirst")
			return
		end

		local initialUI = initialScreen:FindFirstChild("UI") :: Frame?
		if not initialUI then
			warn("[MenuManager] InitialScreen.UI not found")
			return
		end

		-- Create loading screen
		local newScreenGui = Instance.new("ScreenGui")
		newScreenGui.Name = "InitialLoadingScreen"
		newScreenGui.IgnoreGuiInset = true
		newScreenGui.DisplayOrder = 999
		newScreenGui.ResetOnSpawn = false
		newScreenGui.Parent = playerGui
		self._initialScreenGui = newScreenGui

		local newClonedUI = initialUI:Clone()
		newClonedUI.Parent = newScreenGui
		newClonedUI.Visible = true
		clonedInitialUI = newClonedUI

		print("[MenuManager] Created InitialLoadingScreen (fallback)")
	end

	-- Request streaming
	pcall(function()
		player:RequestStreamAroundAsync(CAMERA_POSITION)
	end)

	-- Get continue screen from ReplicatedFirst
	local continueScreen = ReplicatedFirst:FindFirstChild("ContinueScreen")
	if not continueScreen then
		warn("[MenuManager] ContinueScreen not found in ReplicatedFirst")
		return
	end

	local continueUI = continueScreen:FindFirstChild("UI") :: Frame?
	if not continueUI then
		warn("[MenuManager] ContinueScreen.UI not found")
		return
	end

	-- Get text label and set it up (invisible, below screen)
	local textLabel = clonedInitialUI and clonedInitialUI:FindFirstChild("TextLabel") :: TextLabel?
	if textLabel then
		textLabel.Text = "- Press any key to continue -"
		textLabel.TextTransparency = 1 -- Start invisible
		-- Position 15% below the screen (1.15 Y scale)
		textLabel.Position = UDim2.new(textLabel.Position.X.Scale, textLabel.Position.X.Offset, 1.15, 0)
	end

	-- Start continuous streaming to keep particles loaded
	-- Camera is already positioned at the start of _initialize()
	local lastStreamTime = tick()
	self._streamingConnection = RunService.Heartbeat:Connect(function()
		local now = tick()
		if now - lastStreamTime > 1 then -- Request every 1 second (more aggressive during load)
			lastStreamTime = now
			pcall(function()
				player:RequestStreamAroundAsync(CAMERA_POSITION)
			end)
		end
	end)

	-- Create continue screen (hidden for now)
	self._continueScreenGui = Instance.new("ScreenGui")
	self._continueScreenGui.Name = "ContinueLoadingScreen"
	self._continueScreenGui.IgnoreGuiInset = true
	self._continueScreenGui.DisplayOrder = 998
	self._continueScreenGui.ResetOnSpawn = false
	self._continueScreenGui.Parent = playerGui

	-- Clone continue UI (continueUI is guaranteed non-nil here due to earlier return)
	local clonedContinueUI = (continueUI :: Frame):Clone()
	clonedContinueUI.Parent = self._continueScreenGui
	clonedContinueUI.Visible = false

	-- Get references from cloned UIs
	local buttonsFolder = clonedContinueUI --:FindFirstChild("Buttons")
	local continueButton = buttonsFolder and buttonsFolder:FindFirstChild("Continue") :: GuiButton?

	if not textLabel then
		warn("[MenuManager] TextLabel not found in InitialScreen.UI")
	end

	if not continueButton then
		warn("[MenuManager] Continue button not found at ContinueScreen.UI.Buttons.Continue")
	end

	-- Wait for game to load AND persistent models to stream in
	local loadStartTime = tick()
	if not game:IsLoaded() then
		game.Loaded:Wait()
	end

	-- Wait for persistent models to finish loading (important for particles!)
	-- This ensures models with ModelStreamingMode = Persistent are fully loaded
	local persistentLoaded = false
	local persistentConnection = workspace.PersistentLoaded:Connect(function(loadedPlayer)
		if loadedPlayer == player then
			persistentLoaded = true
		end
	end)

	-- Wait up to 5 seconds for persistent models, then continue anyway
	local persistentTimeout = tick() + 5
	while not persistentLoaded and tick() < persistentTimeout do
		task.wait(0.1)
	end
	persistentConnection:Disconnect()

	if persistentLoaded then
		print("[MenuManager] Persistent models loaded")
	else
		print("[MenuManager] Persistent models timeout - continuing anyway")
	end

	-- Ensure minimum loading time of 4 seconds total (gives particles time to emit)
	local elapsed = tick() - loadStartTime
	if elapsed < 4 then
		task.wait(4 - elapsed)
	end

	-- Phase 2: Ready for input - animate text sliding up and fading in
	if textLabel then
		-- Tween both position (from 1.15 to 0.75) and transparency (from 1 to 0) together
		local tween =
			TweenService:Create(textLabel, TweenInfo.new(1.0, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				Position = UDim2.new(textLabel.Position.X.Scale, textLabel.Position.X.Offset, 0.75, 0),
				TextTransparency = 0,
			})
		tween:Play()
	end

	print("[MenuManager] Game loaded - waiting for key press")

	-- Wait for any key press
	self._keyPressConnection = UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed then
			return
		end

		if
			input.UserInputType == Enum.UserInputType.Keyboard
			or input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Gamepad1
		then
			if self._keyPressConnection then
				self._keyPressConnection:Disconnect()
				self._keyPressConnection = nil
			end

			-- Transition to continue screen (text animates down, then continue button fades in)
			if clonedInitialUI and clonedContinueUI then
				self:_transitionToScreen(clonedInitialUI, clonedContinueUI, continueButton)
			end
		end
	end)
end

function MenuManager:_transitionToScreen(initialUI: Frame, continueUI: Frame, continueButton: GuiButton?)
	-- Find the text label and animate it back down (reverse of the entry animation)
	local textLabel = initialUI:FindFirstChild("TextLabel") :: TextLabel?
	if textLabel then
		-- Tween back down (0.75 to 1.15) and fade out (0 to 1)
		local textTween =
			TweenService:Create(textLabel, TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
				Position = UDim2.new(textLabel.Position.X.Scale, textLabel.Position.X.Offset, 1.15, 0),
				TextTransparency = 1,
			})
		textTween:Play()
		textTween.Completed:Wait()
	end

	-- Hide initial screen, show continue screen
	initialUI.Visible = false
	self:_showContinueScreen(initialUI, continueUI, continueButton)
end

function MenuManager:_showContinueScreen(initialUI: Frame, continueUI: Frame, continueButton: GuiButton?)
	-- Hide initial screen
	initialUI.Visible = false

	-- Position camera at cinematic backdrop position
	local cameraCFrame = CFrame.new(CAMERA_POSITION)
	self:_startCameraPan(cameraCFrame)
	print("[MenuManager] Camera positioned at backdrop")

	-- Show continue UI
	continueUI.Visible = true

	-- Animate continue button sliding up from bottom while fading in
	if continueButton then
		-- Store original position values
		local originalXScale = continueButton.Position.X.Scale
		local originalXOffset = continueButton.Position.X.Offset
		local originalYScale = continueButton.Position.Y.Scale
		local originalYOffset = continueButton.Position.Y.Offset

		-- Find text children and start them invisible
		local textLabel = continueButton:FindFirstChildOfClass("TextLabel")
		local textButton = continueButton:FindFirstChildOfClass("TextButton")

		if textLabel then
			textLabel.TextTransparency = 1
		end
		if textButton then
			textButton.TextTransparency = 1
		end

		-- Start below screen (push down by 500 pixels)
		continueButton.Position = UDim2.new(originalXScale, originalXOffset, originalYScale, originalYOffset + 500)

		-- Tween button position back up to original
		TweenService:Create(
			continueButton,
			TweenInfo.new(1.0, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ Position = UDim2.new(originalXScale, originalXOffset, originalYScale, originalYOffset) }
		):Play()

		-- Tween text transparency
		if textLabel then
			TweenService:Create(
				textLabel,
				TweenInfo.new(1.0, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
				{ TextTransparency = 0 }
			):Play()
		end
		if textButton then
			TweenService:Create(
				textButton,
				TweenInfo.new(1.0, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
				{ TextTransparency = 0 }
			):Play()
		end

		-- Connect button click handler
		self._continueConnection = continueButton.MouseButton1Click:Connect(function()
			if self._continueConnection then
				self._continueConnection:Disconnect()
				self._continueConnection = nil
			end

			self:_handleContinue(continueUI)
		end)
	end

	print("[MenuManager] Continue screen shown")
end

function MenuManager:_startCameraPan(anchorCFrame: CFrame)
	local camera = workspace.CurrentCamera
	self._baseCameraCFrame = anchorCFrame
	camera.CameraType = Enum.CameraType.Scriptable
	camera.CFrame = anchorCFrame

	-- Reset smoothed offsets
	self._currentOffsetX = 0
	self._currentOffsetY = 0

	local viewportSize = camera.ViewportSize
	local centerX = viewportSize.X / 2
	local centerY = viewportSize.Y / 2

	-- Note: Continuous streaming is already running from _initialize()
	-- No need to create a new connection here

	-- Smooth camera pan with lerping
	self._panConnection = RunService.RenderStepped:Connect(function(deltaTime)
		if not self._baseCameraCFrame then
			return
		end

		local mousePos = UserInputService:GetMouseLocation()

		-- Calculate normalized mouse position (-1 to 1)
		local normalizedX = (mousePos.X - centerX) / centerX
		local normalizedY = (mousePos.Y - centerY) / centerY

		-- Calculate target offset
		local targetOffsetX = normalizedX * MAX_PAN_OFFSET_X * MOUSE_INFLUENCE * 100
		local targetOffsetY = normalizedY * MAX_PAN_OFFSET_Y * MOUSE_INFLUENCE * 100

		-- Clamp target offset
		targetOffsetX = math.clamp(targetOffsetX, -MAX_PAN_OFFSET_X, MAX_PAN_OFFSET_X)
		targetOffsetY = math.clamp(targetOffsetY, -MAX_PAN_OFFSET_Y, MAX_PAN_OFFSET_Y)

		-- Smoothly lerp current offset towards target (frame-rate independent)
		local lerpFactor = 1 - math.pow(1 - PAN_SMOOTHNESS, deltaTime * 60)
		self._currentOffsetX = self._currentOffsetX + (targetOffsetX - self._currentOffsetX) * lerpFactor
		self._currentOffsetY = self._currentOffsetY + (targetOffsetY - self._currentOffsetY) * lerpFactor

		-- Apply smoothed pan to camera
		camera.CFrame = self._baseCameraCFrame * CFrame.new(self._currentOffsetX, -self._currentOffsetY, 0)
	end)
end

function MenuManager:_stopCameraPan()
	if self._panConnection then
		self._panConnection:Disconnect()
		self._panConnection = nil
	end

	if self._streamingConnection then
		self._streamingConnection:Disconnect()
		self._streamingConnection = nil
	end

	self._baseCameraCFrame = nil
end

function MenuManager:_handleContinue(continueUI: Frame)
	print("[MenuManager] Continue clicked - transitioning to game")

	-- Crossfade from loading screen music to background music
	MusicManager.playMusicFromPath(AudioConfig.Music.Tracks.Background, AudioConfig.Music.MenuCrossfade)
	print("[MenuManager] Crossfading to background music")

	-- Create fade frame
	local fadeFrame = Instance.new("Frame")
	fadeFrame.Name = "FadeFrame"
	fadeFrame.Size = UDim2.fromScale(1, 1)
	fadeFrame.Position = UDim2.fromScale(0, 0)
	fadeFrame.BackgroundColor3 = Color3.new(0, 0, 0)
	fadeFrame.BackgroundTransparency = 1
	fadeFrame.BorderSizePixel = 0
	fadeFrame.ZIndex = 100

	if self._continueScreenGui then
		fadeFrame.Parent = self._continueScreenGui
	end

	-- Fade to black
	local fadeIn = TweenService:Create(fadeFrame, TweenInfo.new(0.5, Enum.EasingStyle.Quad), {
		BackgroundTransparency = 0,
	})
	fadeIn:Play()
	fadeIn.Completed:Wait()

	-- Stop camera pan but keep it scriptable for now
	self:_stopCameraPan()

	-- Hide continue UI
	continueUI.Visible = false

	-- Request character spawn from server
	local requestSpawnRemote = ReplicatedStorage:WaitForChild("RequestSpawn", 5)
	if requestSpawnRemote then
		requestSpawnRemote:FireServer()
		print("[MenuManager] Requested character spawn")

		-- Wait for character to spawn
		if not player.Character then
			player.CharacterAdded:Wait()
		end

		-- Give character a moment to fully load
		task.wait(0.1)
	end

	-- NOW reset camera to follow the spawned character
	local camera = workspace.CurrentCamera
	camera.CameraType = Enum.CameraType.Custom
	camera.CameraSubject = player.Character and player.Character:FindFirstChild("Humanoid") or nil

	-- Enable the main game UI
	self:_enableGameUI()

	task.wait(0.2)

	-- Fade from black
	local fadeOut = TweenService:Create(fadeFrame, TweenInfo.new(0.5, Enum.EasingStyle.Quad), {
		BackgroundTransparency = 1,
	})
	fadeOut:Play()
	fadeOut.Completed:Wait()

	-- Clean up
	self:_cleanup()

	print("[MenuManager] Transition complete - game ready")
end

function MenuManager:_cleanup()
	if self._initialScreenGui then
		self._initialScreenGui:Destroy()
		self._initialScreenGui = nil
	end

	if self._continueScreenGui then
		self._continueScreenGui:Destroy()
		self._continueScreenGui = nil
	end

	if self._keyPressConnection then
		self._keyPressConnection:Disconnect()
		self._keyPressConnection = nil
	end

	if self._continueConnection then
		self._continueConnection:Disconnect()
		self._continueConnection = nil
	end

	self:_stopCameraPan()
end

function MenuManager:destroy()
	self:_cleanup()
end

return MenuManager
