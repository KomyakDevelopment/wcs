--!strict
-- Execution Effects Manager (Client)
-- Handles VFX, SFX, and death animation for player executions (grip kills)
-- Also handles death UI and respawn flow for local player

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

local ExecutionEffectsManager = {}
ExecutionEffectsManager.__index = ExecutionEffectsManager

-- Configuration
local FADE_DURATION = 1.0 -- How long the body fade takes
local SCREEN_FADE_DURATION = 0.5 -- How long screen fade takes
local DEATH_UI_TWEEN_DURATION = 0.5 -- How long death UI elements tween in/out

function ExecutionEffectsManager.new()
	local self = setmetatable({}, ExecutionEffectsManager)

	self._connections = {} :: { RBXScriptConnection }
	self._player = Players.LocalPlayer
	self._continueButtonConnection = nil :: RBXScriptConnection?
	self._hiddenUIElements = {} :: { GuiObject } -- Track UI elements hidden during death

	self:_setup()

	print("[ExecutionEffectsManager] Initialized")
	return self
end

function ExecutionEffectsManager:_setup()
	-- Disable the default Roblox health bar (top right corner)
	local success, err = pcall(function()
		StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Health, false)
	end)
	if success then
		print("[ExecutionEffectsManager] Disabled default Roblox health bar")
	else
		warn("[ExecutionEffectsManager] Failed to disable health bar:", err)
	end

	-- Wait for execution remote
	print("[ExecutionEffectsManager] Waiting for PlayerExecuted remote...")
	local executeRemote = ReplicatedStorage:WaitForChild("PlayerExecuted", 10) :: RemoteEvent?
	if executeRemote then
		print("[ExecutionEffectsManager] Found PlayerExecuted remote, connecting handler...")
		table.insert(
			self._connections,
			executeRemote.OnClientEvent:Connect(function(targetCharacter: Model)
				print(`[ExecutionEffectsManager] Received PlayerExecuted event for: {if targetCharacter then targetCharacter.Name else "nil"}`)
				-- Wrap in pcall to catch any errors
				local handleSuccess, handleErr = pcall(function()
					self:_handleExecution(targetCharacter)
				end)
				if not handleSuccess then
					warn("[ExecutionEffectsManager] ERROR in _handleExecution:", handleErr)
				end
			end)
		)
		print("[ExecutionEffectsManager] Listening for PlayerExecuted events")
	else
		warn("[ExecutionEffectsManager] PlayerExecuted remote NOT FOUND after 10 second wait!")
	end
end

function ExecutionEffectsManager:_handleExecution(targetCharacter: Model)
	print("[ExecutionEffectsManager] _handleExecution called")

	if not targetCharacter then
		warn("[ExecutionEffectsManager] targetCharacter is nil")
		return
	end

	if not targetCharacter:IsA("Model") then
		warn(`[ExecutionEffectsManager] targetCharacter is not a Model, it's a {targetCharacter.ClassName}`)
		return
	end

	print(`[ExecutionEffectsManager] Processing execution for {targetCharacter.Name}`)

	-- Play effects for everyone (wrapped in pcall)
	local vfxSuccess, vfxErr = pcall(function()
		self:_playDeathVFX(targetCharacter)
	end)
	if not vfxSuccess then
		warn("[ExecutionEffectsManager] VFX error:", vfxErr)
	end

	local sfxSuccess, sfxErr = pcall(function()
		self:_playDeathSFX(targetCharacter)
	end)
	if not sfxSuccess then
		warn("[ExecutionEffectsManager] SFX error:", sfxErr)
	end

	local animSuccess, animErr = pcall(function()
		self:_playDeathAnimation(targetCharacter)
	end)
	if not animSuccess then
		warn("[ExecutionEffectsManager] Animation error:", animErr)
	end

	-- Check if this is the local player being executed
	local targetPlayer = Players:GetPlayerFromCharacter(targetCharacter)
	print(`[ExecutionEffectsManager] Target player: {if targetPlayer then targetPlayer.Name else "nil"}, Local player: {self._player.Name}`)

	if targetPlayer == self._player then
		print("[ExecutionEffectsManager] THIS IS THE LOCAL PLAYER - showing death UI")
		local deathUISuccess, deathUIErr = pcall(function()
			self:_handleLocalPlayerDeath(targetCharacter)
		end)
		if not deathUISuccess then
			warn("[ExecutionEffectsManager] Death UI error:", deathUIErr)
		end
	else
		print("[ExecutionEffectsManager] Not the local player, skipping death UI")
	end
end

-- Handle local player death (hide UI, show death GUI, respawn)
function ExecutionEffectsManager:_handleLocalPlayerDeath(_character: Model)
	print("[ExecutionEffectsManager] _handleLocalPlayerDeath called")

	-- Immediately hide UI elements (no tween)
	print("[ExecutionEffectsManager] Calling _hideOtherUI...")
	local hideSuccess, hideErr = pcall(function()
		self:_hideOtherUI()
	end)
	if not hideSuccess then
		warn("[ExecutionEffectsManager] _hideOtherUI error:", hideErr)
	else
		print("[ExecutionEffectsManager] _hideOtherUI completed successfully")
	end

	-- Show death GUI after a short delay (let body start fading)
	print("[ExecutionEffectsManager] Scheduling death GUI in 0.5s...")
	task.delay(0.5, function()
		print("[ExecutionEffectsManager] Delay finished, showing death GUI...")
		local showSuccess, showErr = pcall(function()
			self:_showDeathGUI()
		end)
		if not showSuccess then
			warn("[ExecutionEffectsManager] _showDeathGUI error:", showErr)
		else
			print("[ExecutionEffectsManager] _showDeathGUI completed successfully")
		end
	end)
end

-- Show death GUI
function ExecutionEffectsManager:_showDeathGUI()
	print("[ExecutionEffectsManager] _showDeathGUI called")

	local playerGui = self._player:FindFirstChild("PlayerGui")
	if not playerGui then
		warn("[ExecutionEffectsManager] PlayerGui not found!")
		return
	end
	print("[ExecutionEffectsManager] Found PlayerGui")

	-- Navigate to DeathGUI.Death
	local mainGui = playerGui:FindFirstChild("Main")
	if not mainGui then
		warn("[ExecutionEffectsManager] Main GUI not found in PlayerGui!")
		-- List what's in PlayerGui for debugging
		print("[ExecutionEffectsManager] PlayerGui children:")
		for _, child in ipairs(playerGui:GetChildren()) do
			print(`  - {child.Name} ({child.ClassName})`)
		end
		return
	end
	print("[ExecutionEffectsManager] Found Main GUI")

	local deathGUI = mainGui:FindFirstChild("DeathGUI")
	if not deathGUI then
		warn("[ExecutionEffectsManager] DeathGUI not found in Main!")
		-- List what's in Main for debugging
		print("[ExecutionEffectsManager] Main children:")
		for _, child in ipairs(mainGui:GetChildren()) do
			print(`  - {child.Name} ({child.ClassName})`)
		end
		return
	end
	print("[ExecutionEffectsManager] Found DeathGUI")

	local deathFrame = deathGUI:FindFirstChild("Death")
	if not deathFrame then
		warn("[ExecutionEffectsManager] Death frame not found in DeathGUI!")
		-- List what's in DeathGUI for debugging
		print("[ExecutionEffectsManager] DeathGUI children:")
		for _, child in ipairs(deathGUI:GetChildren()) do
			print(`  - {child.Name} ({child.ClassName})`)
		end
		return
	end
	print("[ExecutionEffectsManager] Found Death frame")

	-- Show the death frame (UI elements already hidden in _handleLocalPlayerDeath)
	deathFrame.Visible = true
	print("[ExecutionEffectsManager] Death frame set to Visible = true")

	-- Find and tween in the continue button
	local continueButton = deathFrame:FindFirstChild("continue_button")
	if continueButton then
		print(`[ExecutionEffectsManager] Found continue_button, IsA GuiButton: {continueButton:IsA("GuiButton")}`)
	else
		print("[ExecutionEffectsManager] continue_button NOT found in Death frame")
		-- List what's in Death frame for debugging
		print("[ExecutionEffectsManager] Death frame children:")
		for _, child in ipairs(deathFrame:GetChildren()) do
			print(`  - {child.Name} ({child.ClassName})`)
		end
	end

	if continueButton and continueButton:IsA("GuiButton") then
		-- Tween the continue button in (fade + slide up)
		self:_tweenInContinueButton(continueButton)

		-- Disconnect any previous connection
		if self._continueButtonConnection then
			self._continueButtonConnection:Disconnect()
		end

		self._continueButtonConnection = continueButton.Activated:Connect(function()
			print("[ExecutionEffectsManager] Continue button clicked!")
			self:_handleContinuePressed(deathFrame)
		end)
		print("[ExecutionEffectsManager] Death GUI shown, continue button connected")
	else
		warn("[ExecutionEffectsManager] continue_button not found or not a GuiButton")
	end
end

-- Tween in the continue button (fade in + slide up)
function ExecutionEffectsManager:_tweenInContinueButton(button: GuiButton)
	-- Store original position
	local originalPosition = button.Position

	-- Start position: slightly below, fully transparent
	local startOffset = UDim2.fromOffset(0, 20)
	button.Position = originalPosition + startOffset

	-- Handle different transparency properties based on button type
	if button:IsA("TextButton") then
		button.TextTransparency = 1
		button.BackgroundTransparency = 1
	elseif button:IsA("ImageButton") then
		button.ImageTransparency = 1
		button.BackgroundTransparency = 1
	end

	button.Visible = true

	-- Tween to original position with fade in
	local tweenInfo = TweenInfo.new(DEATH_UI_TWEEN_DURATION, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

	local positionTween = TweenService:Create(button, tweenInfo, {
		Position = originalPosition
	})
	positionTween:Play()

	-- Tween transparency
	if button:IsA("TextButton") then
		local textTween = TweenService:Create(button, tweenInfo, {
			TextTransparency = 0,
			BackgroundTransparency = 0
		})
		textTween:Play()
	elseif button:IsA("ImageButton") then
		local imageTween = TweenService:Create(button, tweenInfo, {
			ImageTransparency = 0,
			BackgroundTransparency = 0
		})
		imageTween:Play()
	end
end

-- Immediately hide UI elements when gripped (no tweening)
function ExecutionEffectsManager:_hideOtherUI()
	print("[ExecutionEffectsManager] _hideOtherUI called")

	local playerGui = self._player:FindFirstChild("PlayerGui")
	if not playerGui then
		warn("[ExecutionEffectsManager] PlayerGui not found!")
		return
	end
	print("[ExecutionEffectsManager] Found PlayerGui")

	local mainGui = playerGui:FindFirstChild("Main")
	if not mainGui then
		warn("[ExecutionEffectsManager] Main GUI not found!")
		-- List what's in PlayerGui for debugging
		print("[ExecutionEffectsManager] PlayerGui children:")
		for _, child in ipairs(playerGui:GetChildren()) do
			print(`  - {child.Name} ({child.ClassName})`)
		end
		return
	end
	print("[ExecutionEffectsManager] Found Main GUI")

	-- List Main's children for debugging
	print("[ExecutionEffectsManager] Main GUI children:")
	for _, child in ipairs(mainGui:GetChildren()) do
		print(`  - {child.Name} ({child.ClassName})`)
	end

	-- Clear previous hidden elements list
	self._hiddenUIElements = {}

	-- Helper function to find and hide an element
	local function hideElement(parent: Instance, childName: string): boolean
		-- Try exact name and common variants
		local child = parent:FindFirstChild(childName)
			or parent:FindFirstChild(childName:gsub("Gui$", "GUI"))
			or parent:FindFirstChild(childName:gsub("GUI$", "Gui"))

		if child then
			print(`[ExecutionEffectsManager] Found {childName} in {parent.Name}, IsA GuiObject: {child:IsA("GuiObject")}`)
			if child:IsA("GuiObject") then
				table.insert(self._hiddenUIElements, child)
				child.Visible = false
				print(`[ExecutionEffectsManager] HIDDEN: {child:GetFullName()}`)
				return true
			else
				warn(`[ExecutionEffectsManager] {childName} is not a GuiObject, it's a {child.ClassName}`)
			end
		else
			print(`[ExecutionEffectsManager] {childName} NOT found in {parent.Name}`)
			-- List parent's children
			print(`[ExecutionEffectsManager] {parent.Name} children:`)
			for _, c in ipairs(parent:GetChildren()) do
				print(`    - {c.Name} ({c.ClassName})`)
			end
		end
		return false
	end

	-- Hide HealthGui children
	local healthGui = mainGui:FindFirstChild("HealthGui") or mainGui:FindFirstChild("HealthGUI")
	if healthGui then
		print(`[ExecutionEffectsManager] Found health GUI: {healthGui.Name}`)
		hideElement(healthGui, "Health")
		-- Try both spellings: "Separation" (correct) and "Seperation" (typo in actual UI)
		if not hideElement(healthGui, "Separation") then
			hideElement(healthGui, "Seperation")
		end
	else
		warn("[ExecutionEffectsManager] HealthGui/HealthGUI not found in Main")
	end

	-- Hide PostureGUI children
	local postureGui = mainGui:FindFirstChild("PostureGUI") or mainGui:FindFirstChild("PostureGui")
	if postureGui then
		print(`[ExecutionEffectsManager] Found posture GUI: {postureGui.Name}`)
		hideElement(postureGui, "Posture")
	else
		warn("[ExecutionEffectsManager] PostureGUI/PostureGui not found in Main")
	end

	-- Hide Main.Ctag (yes, there's a "Main" child inside the "Main" ScreenGui)
	local mainChild = mainGui:FindFirstChild("Main")
	if mainChild then
		print("[ExecutionEffectsManager] Found Main child inside Main GUI")
		hideElement(mainChild, "Ctag")
	else
		print("[ExecutionEffectsManager] No 'Main' child inside Main GUI")
	end

	-- Hide Interact
	hideElement(mainGui, "Interact")

	-- Also hide the Hotbar (separate ScreenGui)
	local hotbarGui = playerGui:FindFirstChild("HotbarUI")
	if hotbarGui and hotbarGui:IsA("ScreenGui") then
		print("[ExecutionEffectsManager] Found HotbarUI")
		local hotbarContainer = hotbarGui:FindFirstChildWhichIsA("Frame")
		if hotbarContainer then
			table.insert(self._hiddenUIElements, hotbarContainer)
			hotbarContainer.Visible = false
			print(`[ExecutionEffectsManager] HIDDEN: HotbarUI container`)
		else
			print("[ExecutionEffectsManager] No Frame found in HotbarUI")
		end
	else
		print("[ExecutionEffectsManager] HotbarUI not found or not a ScreenGui")
	end

	print(`[ExecutionEffectsManager] Total hidden elements: {#self._hiddenUIElements}`)
end

-- Restore UI elements that were hidden during death screen
function ExecutionEffectsManager:_restoreHiddenUI()
	for _, element in ipairs(self._hiddenUIElements) do
		if element and element.Parent then
			element.Visible = true
		end
	end

	-- Clear the list
	self._hiddenUIElements = {}
	print("[ExecutionEffectsManager] Restored hidden UI elements")
end

-- Handle continue button pressed
function ExecutionEffectsManager:_handleContinuePressed(deathFrame: GuiObject)
	print("[ExecutionEffectsManager] Continue button pressed")

	-- Disconnect button
	if self._continueButtonConnection then
		self._continueButtonConnection:Disconnect()
		self._continueButtonConnection = nil
	end

	-- Hide death frame
	deathFrame.Visible = false

	-- Fade screen to black
	self:_fadeScreenToBlack(function()
		-- Black screen is now fully visible
		-- Restore hidden UI elements (they'll be behind the black screen)
		self:_restoreHiddenUI()

		-- Confirm execution to server (this will kill the player and respawn them)
		self:_confirmExecution()

		-- Wait for character to spawn, then fade back in
		self:_waitForRespawnAndFadeIn()
	end)
end

-- Fade screen to black
function ExecutionEffectsManager:_fadeScreenToBlack(callback: () -> ())
	local playerGui = self._player:FindFirstChild("PlayerGui")
	if not playerGui then
		callback()
		return
	end

	-- Create or find fade frame
	local fadeGui = playerGui:FindFirstChild("ExecutionFadeGui") :: ScreenGui?
	if not fadeGui then
		fadeGui = Instance.new("ScreenGui")
		fadeGui.Name = "ExecutionFadeGui"
		fadeGui.DisplayOrder = 100 -- Above other GUIs
		fadeGui.IgnoreGuiInset = true
		fadeGui.Parent = playerGui
	end

	local fadeFrame = fadeGui:FindFirstChild("FadeFrame") :: Frame?
	if not fadeFrame then
		fadeFrame = Instance.new("Frame")
		fadeFrame.Name = "FadeFrame"
		fadeFrame.Size = UDim2.fromScale(1, 1)
		fadeFrame.Position = UDim2.fromScale(0, 0)
		fadeFrame.BackgroundColor3 = Color3.new(0, 0, 0)
		fadeFrame.BackgroundTransparency = 1
		fadeFrame.BorderSizePixel = 0
		fadeFrame.Parent = fadeGui
	end

	-- Ensure it's visible and transparent to start
	fadeFrame.BackgroundTransparency = 1
	fadeGui.Enabled = true

	-- Tween to black
	local tweenInfo = TweenInfo.new(SCREEN_FADE_DURATION, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	local tween = TweenService:Create(fadeFrame, tweenInfo, {
		BackgroundTransparency = 0
	})
	tween:Play()

	tween.Completed:Once(function()
		callback()
	end)
end

-- Fade screen from black
function ExecutionEffectsManager:_fadeScreenFromBlack()
	local playerGui = self._player:FindFirstChild("PlayerGui")
	if not playerGui then
		return
	end

	local fadeGui = playerGui:FindFirstChild("ExecutionFadeGui") :: ScreenGui?
	if not fadeGui then
		return
	end

	local fadeFrame = fadeGui:FindFirstChild("FadeFrame") :: Frame?
	if not fadeFrame then
		return
	end

	-- Tween from black to transparent
	local tweenInfo = TweenInfo.new(SCREEN_FADE_DURATION, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	local tween = TweenService:Create(fadeFrame, tweenInfo, {
		BackgroundTransparency = 1
	})
	tween:Play()

	tween.Completed:Once(function()
		fadeGui.Enabled = false
	end)
end

-- Confirm execution to server (kills and respawns the player)
function ExecutionEffectsManager:_confirmExecution()
	local confirmRemote = ReplicatedStorage:FindFirstChild("ConfirmExecution") :: RemoteEvent?
	if confirmRemote then
		confirmRemote:FireServer()
		print("[ExecutionEffectsManager] Confirmed execution to server")
	else
		-- Fallback: Use respawn remote
		local respawnRemote = ReplicatedStorage:FindFirstChild("RequestRespawn") :: RemoteEvent?
		if respawnRemote then
			respawnRemote:FireServer()
			print("[ExecutionEffectsManager] Fallback: Requested respawn from server")
		end
	end
end

-- Request respawn from server (legacy, kept for compatibility)
function ExecutionEffectsManager:_requestRespawn()
	local respawnRemote = ReplicatedStorage:FindFirstChild("RequestRespawn") :: RemoteEvent?
	if respawnRemote then
		respawnRemote:FireServer()
		print("[ExecutionEffectsManager] Requested respawn from server")
	end
end

-- Wait for character to respawn, then fade screen back in
function ExecutionEffectsManager:_waitForRespawnAndFadeIn()
	-- Store the OLD character reference - we need to wait for a DIFFERENT character
	local oldCharacter = self._player.Character

	-- Wait for new character (CharacterAdded fires when a new character spawns)
	local connection: RBXScriptConnection?
	local hasResponded = false

	connection = self._player.CharacterAdded:Connect(function(newCharacter)
		-- Only respond if this is a DIFFERENT character than the old one
		if newCharacter ~= oldCharacter and not hasResponded then
			hasResponded = true

			if connection then
				connection:Disconnect()
				connection = nil
			end

			-- Wait for humanoid to be ready
			local humanoid = newCharacter:WaitForChild("Humanoid", 5)
			if humanoid then
				-- Wait a bit for character to be fully loaded
				task.wait(0.2)
			end

			-- Fade screen back in (UI already restored before respawn)
			self:_fadeScreenFromBlack()

			print("[ExecutionEffectsManager] New character spawned, fading in")
		end
	end)

	-- Store connection for cleanup
	table.insert(self._connections, connection)

	-- Safety timeout - if character doesn't spawn in 5 seconds, fade in anyway
	task.delay(5, function()
		if not hasResponded then
			hasResponded = true

			if connection then
				connection:Disconnect()
				connection = nil
			end

			-- Check if still on black screen
			local fadeGui = self._player:FindFirstChild("PlayerGui")
				and self._player.PlayerGui:FindFirstChild("ExecutionFadeGui")
			if fadeGui and fadeGui.Enabled then
				print("[ExecutionEffectsManager] Safety timeout - fading in anyway")
				self:_fadeScreenFromBlack()
			end
		end
	end)
end

-- Play death VFX (particles from ReplicatedStorage.Assets.VFX.General_Combat.death)
function ExecutionEffectsManager:_playDeathVFX(targetCharacter: Model)
	-- Get death VFX template
	local deathVFXPath = ReplicatedStorage:FindFirstChild("Assets")
		and ReplicatedStorage.Assets:FindFirstChild("VFX")
		and ReplicatedStorage.Assets.VFX:FindFirstChild("General_Combat")
		and ReplicatedStorage.Assets.VFX.General_Combat:FindFirstChild("death")

	if not deathVFXPath then
		warn("[ExecutionEffectsManager] Death VFX not found at Assets.VFX.General_Combat.death")
		return
	end

	-- Get the attachment from the death part
	local sourceAttachment = deathVFXPath:FindFirstChild("Attachment")
	if not sourceAttachment then
		warn("[ExecutionEffectsManager] No Attachment found in death VFX part")
		return
	end

	-- Find target's torso
	local targetTorso = targetCharacter:FindFirstChild("Torso")
		or targetCharacter:FindFirstChild("UpperTorso")
		or targetCharacter:FindFirstChild("HumanoidRootPart")

	if not targetTorso then
		warn("[ExecutionEffectsManager] Target torso not found")
		return
	end

	-- Clone attachment to target torso
	local attachmentClone = sourceAttachment:Clone()
	attachmentClone.Parent = targetTorso

	-- Emit all particle emitters according to their properties
	local emitters = {}
	for _, child in ipairs(attachmentClone:GetChildren()) do
		if child:IsA("ParticleEmitter") then
			table.insert(emitters, child)
			-- Emit particles based on EmitCount attribute or Rate
			local emitCount = child:GetAttribute("EmitCount") or child.Rate or 15
			child:Emit(emitCount)
		end
	end

	-- Cleanup attachment after particles finish
	local maxLifetime = 0
	for _, emitter in ipairs(emitters) do
		local lifetime = emitter.Lifetime.Max + (emitter:GetAttribute("Duration") or 1)
		if lifetime > maxLifetime then
			maxLifetime = lifetime
		end
	end

	Debris:AddItem(attachmentClone, maxLifetime + 0.5)
	print(`[ExecutionEffectsManager] Playing death VFX on {targetCharacter.Name}`)
end

-- Play death SFX (random sound from ReplicatedStorage.Assets.SFX.General_Combat.death)
function ExecutionEffectsManager:_playDeathSFX(targetCharacter: Model)
	-- Get death SFX folder
	local deathSFXFolder = ReplicatedStorage:FindFirstChild("Assets")
		and ReplicatedStorage.Assets:FindFirstChild("SFX")
		and ReplicatedStorage.Assets.SFX:FindFirstChild("General_Combat")
		and ReplicatedStorage.Assets.SFX.General_Combat:FindFirstChild("death")

	if not deathSFXFolder then
		warn("[ExecutionEffectsManager] Death SFX folder not found at Assets.SFX.General_Combat.death")
		return
	end

	-- Get all sounds from folder
	local sounds = {}
	for _, child in ipairs(deathSFXFolder:GetChildren()) do
		if child:IsA("Sound") then
			table.insert(sounds, child)
		end
	end

	if #sounds == 0 then
		warn("[ExecutionEffectsManager] No death sounds found in folder")
		return
	end

	-- Pick random sound
	local randomSound = sounds[math.random(1, #sounds)]

	-- Clone and play at target position
	local soundClone = randomSound:Clone()
	soundClone.Parent = targetCharacter:FindFirstChild("HumanoidRootPart") or targetCharacter

	soundClone:Play()
	print(`[ExecutionEffectsManager] Playing death sound: {randomSound.Name}`)

	-- Cleanup after sound finishes
	Debris:AddItem(soundClone, soundClone.TimeLength + 0.1)
end

-- Play death animation (fade transparency only, no sinking)
function ExecutionEffectsManager:_playDeathAnimation(targetCharacter: Model)
	-- Get all body parts to fade
	local bodyParts: { BasePart } = {}
	local accessories: { Instance } = {}

	for _, descendant in ipairs(targetCharacter:GetDescendants()) do
		if descendant:IsA("BasePart") then
			table.insert(bodyParts, descendant)
		elseif descendant:IsA("Accessory") then
			table.insert(accessories, descendant)
		end
	end

	-- Also fade accessories
	for _, accessory in ipairs(accessories) do
		local handle = accessory:FindFirstChild("Handle")
		if handle and handle:IsA("BasePart") then
			table.insert(bodyParts, handle)
		end
	end

	if #bodyParts == 0 then
		warn("[ExecutionEffectsManager] No body parts found to animate")
		return
	end

	-- Create tween info for fade
	local fadeInfo = TweenInfo.new(
		FADE_DURATION,
		Enum.EasingStyle.Quad,
		Enum.EasingDirection.Out
	)

	-- Fade all parts to transparent (no sinking)
	for _, part in ipairs(bodyParts) do
		-- Only tween parts that can have transparency
		if part.Transparency < 1 then
			local fadeTween = TweenService:Create(part, fadeInfo, {
				Transparency = 1
			})
			fadeTween:Play()
		end

		-- Also fade any decals/textures on the part
		for _, child in ipairs(part:GetChildren()) do
			if child:IsA("Decal") or child:IsA("Texture") then
				local decalTween = TweenService:Create(child, fadeInfo, {
					Transparency = 1
				})
				decalTween:Play()
			end
		end
	end

	print(`[ExecutionEffectsManager] Playing death animation for {targetCharacter.Name}`)

	-- Clean up the character model after animations complete
	task.delay(FADE_DURATION + 0.5, function()
		-- The server will handle actual character destruction
		-- We just ensure visibility is gone
		for _, part in ipairs(bodyParts) do
			if part and part.Parent then
				part.Transparency = 1
			end
		end
	end)
end

function ExecutionEffectsManager:destroy()
	-- Disconnect continue button if connected
	if self._continueButtonConnection then
		self._continueButtonConnection:Disconnect()
		self._continueButtonConnection = nil
	end

	for _, connection in ipairs(self._connections) do
		connection:Disconnect()
	end
	self._connections = {}
end

return ExecutionEffectsManager
