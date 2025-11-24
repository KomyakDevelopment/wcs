--!strict
-- Hit Effects Manager (Client)
-- Handles client-side replication of hit sounds and VFX for optimal performance and timing

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Debris = game:GetService("Debris")
local TweenService = game:GetService("TweenService")

local HitEffectsManager = {}
HitEffectsManager.__index = HitEffectsManager

-- Weapon class configuration
local WEAPON_EFFECTS = {
	fists = {
		soundPath = { "Assets", "SFX", "Weapon_Classes", "Fists", "hit" },
		vfxPath = { "Assets", "VFX", "Weapon_Classes", "Fists", "hit" },
	},
}

-- Debounce for rollcancel sounds (prevents double sounds from client prediction + server)
local ROLLCANCEL_DEBOUNCE = 0.3 -- seconds

function HitEffectsManager.new()
	local self = setmetatable({}, HitEffectsManager)

	-- Wait for remote event
	local hitEffectsRemote = ReplicatedStorage:WaitForChild("PlayHitEffects") :: RemoteEvent

	-- Listen for hit effects from server
	hitEffectsRemote.OnClientEvent:Connect(function(targetModel: Model, weaponClass: string)
		print(`[HitEffectsManager] Received hit effect event - Target: {if targetModel then targetModel.Name else "nil"}, Weapon: {weaponClass}`)
		self:playHitEffects(targetModel, weaponClass)
	end)

	-- Listen for rollcancel effects from server (when attack hits during iframes)
	local rollCancelRemote = ReplicatedStorage:WaitForChild("PlayRollCancel") :: RemoteEvent
	rollCancelRemote.OnClientEvent:Connect(function(targetModel: Model)
		-- Check debounce via attribute (client prediction may have already played the sound)
		if targetModel then
			local lastRollCancelTime = targetModel:GetAttribute("_RollCancelTime")
			if lastRollCancelTime and (tick() - lastRollCancelTime) < ROLLCANCEL_DEBOUNCE then
				print(`[HitEffectsManager] Roll cancel debounced for {targetModel.Name} (client predicted)`)
				return
			end
		end

		print(`[HitEffectsManager] Roll cancel triggered on {if targetModel then targetModel.Name else "nil"}`)
		self:playRollCancelEffects(targetModel)
	end)

	print("[HitEffectsManager] Initialized - Listening for hit effects")

	return self
end

-- Play hit effects (sound + VFX) for a target
function HitEffectsManager:playHitEffects(targetModel: Model, weaponClass: string)
	if not targetModel or not targetModel:IsA("Model") then
		warn("[HitEffectsManager] Invalid target model")
		return
	end

	local config = WEAPON_EFFECTS[weaponClass]
	if not config then
		warn(`[HitEffectsManager] Unknown weapon class: {weaponClass}`)
		return
	end

	-- Play sound and VFX simultaneously
	self:_playHitSound(targetModel, config.soundPath)
	self:_playHitVFX(targetModel, config.vfxPath)
end

-- Play hit sound effect
function HitEffectsManager:_playHitSound(targetModel: Model, pathArray: { string })
	-- Navigate to sound folder
	local hitSoundsFolder = ReplicatedStorage
	for _, folderName in ipairs(pathArray) do
		hitSoundsFolder = hitSoundsFolder:FindFirstChild(folderName)
		if not hitSoundsFolder then
			warn(`[HitEffectsManager] Sound folder not found: {folderName}`)
			return
		end
	end

	-- Get all sound effects
	local sounds = {}
	for _, child in ipairs(hitSoundsFolder:GetChildren()) do
		if child:IsA("Sound") then
			table.insert(sounds, child)
		end
	end

	if #sounds == 0 then
		warn("[HitEffectsManager] No hit sounds found")
		return
	end

	-- Pick random sound
	local randomSound = sounds[math.random(1, #sounds)]

	-- Clone and play at target position
	local soundClone = randomSound:Clone()
	soundClone.Parent = targetModel:FindFirstChild("HumanoidRootPart") or targetModel

	soundClone:Play()
	print(`[HitEffectsManager] Playing sound: {randomSound.Name} at {targetModel.Name}`)

	-- Cleanup after sound finishes
	Debris:AddItem(soundClone, soundClone.TimeLength + 0.1)
end

-- Play hit VFX on target
function HitEffectsManager:_playHitVFX(targetModel: Model, pathArray: { string })
	-- Navigate to VFX part
	local vfxPart = ReplicatedStorage
	for _, folderName in ipairs(pathArray) do
		vfxPart = vfxPart:FindFirstChild(folderName)
		if not vfxPart then
			warn(`[HitEffectsManager] VFX folder not found: {folderName}`)
			return
		end
	end

	if not vfxPart:IsA("BasePart") then
		warn("[HitEffectsManager] Hit VFX part is not a BasePart")
		return
	end

	-- Get first attachment from the VFX part
	local sourceAttachment = vfxPart:FindFirstChildWhichIsA("Attachment")
	if not sourceAttachment then
		warn("[HitEffectsManager] No attachment found in VFX part")
		return
	end

	-- Find target's torso
	local targetTorso = targetModel:FindFirstChild("Torso") or targetModel:FindFirstChild("UpperTorso")
	if not targetTorso then
		warn("[HitEffectsManager] Target torso not found")
		return
	end

	-- Clone attachment to target torso
	local attachmentClone = sourceAttachment:Clone()
	attachmentClone.Parent = targetTorso

	-- Emit all particle emitters
	local emitters = {}
	for _, child in ipairs(attachmentClone:GetChildren()) do
		if child:IsA("ParticleEmitter") then
			table.insert(emitters, child)
			-- Emit particles based on emitter's Rate property
			local emitCount = child:GetAttribute("EmitCount") or child.Rate or 10
			child:Emit(emitCount)
		end
	end

	-- Cleanup attachment after particles finish (use longest lifetime)
	local maxLifetime = 0
	for _, emitter in ipairs(emitters) do
		local lifetime = emitter.Lifetime.Max + (emitter:GetAttribute("Duration") or 1)
		if lifetime > maxLifetime then
			maxLifetime = lifetime
		end
	end

	Debris:AddItem(attachmentClone, maxLifetime + 0.5)
end

-- Play roll cancel effects (sound + animation when hit during iframes)
function HitEffectsManager:playRollCancelEffects(targetModel: Model)
	if not targetModel or not targetModel:IsA("Model") then
		warn("[HitEffectsManager] Invalid target model for roll cancel")
		return
	end

	-- Play roll cancel sound
	self:_playRollCancelSound(targetModel)

	-- Play roll cancel animation
	self:_playRollCancelAnimation(targetModel)

	-- Play successful dodge VFX
	self:_playSuccessfulDodgeVFX(targetModel)

	-- Play successful dodge highlight
	self:_playSuccessfulDodgeHighlight(targetModel)
end

-- Play roll cancel sound effect
function HitEffectsManager:_playRollCancelSound(targetModel: Model)
	local cancelSFXFolder = ReplicatedStorage:FindFirstChild("Assets")
		and ReplicatedStorage.Assets:FindFirstChild("SFX")
		and ReplicatedStorage.Assets.SFX:FindFirstChild("Movement")
		and ReplicatedStorage.Assets.SFX.Movement:FindFirstChild("Dodges")
		and ReplicatedStorage.Assets.SFX.Movement.Dodges:FindFirstChild("Cancel")

	if not cancelSFXFolder then
		warn("[HitEffectsManager] Roll cancel SFX folder not found at Assets.SFX.Movement.Dodges.Cancel")
		return
	end

	-- Get all sounds
	local sounds = {}
	for _, child in ipairs(cancelSFXFolder:GetChildren()) do
		if child:IsA("Sound") then
			table.insert(sounds, child)
		end
	end

	if #sounds == 0 then
		warn("[HitEffectsManager] No roll cancel sounds found")
		return
	end

	-- Pick random sound
	local randomSound = sounds[math.random(1, #sounds)]

	-- Clone and play at target position
	local soundClone = randomSound:Clone()
	soundClone.Parent = targetModel:FindFirstChild("HumanoidRootPart") or targetModel

	soundClone:Play()
	print(`[HitEffectsManager] Playing roll cancel sound: {randomSound.Name} at {targetModel.Name}`)

	-- Cleanup after sound finishes
	Debris:AddItem(soundClone, soundClone.TimeLength + 0.1)
end

-- Play roll cancel animation
function HitEffectsManager:_playRollCancelAnimation(targetModel: Model)
	local humanoid = targetModel:FindFirstChild("Humanoid") :: Humanoid?
	if not humanoid then
		return
	end

	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		return
	end

	local hrp = targetModel:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not hrp then
		return
	end

	-- Stop any current dodge/roll animations by stopping action-priority tracks
	for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
		local priority = track.Priority
		if priority == Enum.AnimationPriority.Action or priority == Enum.AnimationPriority.Action2 then
			track:Stop(0.05)
		end
	end

	-- Determine rollcancel direction based on movement
	local rollCancelAnimId = "rbxassetid://96765830085186" -- Default to right
	local moveDir = humanoid.MoveDirection

	if moveDir.Magnitude > 0.1 then
		local lookVector = hrp.CFrame.LookVector
		local rightVector = hrp.CFrame.RightVector

		-- Project movement onto character's forward and right vectors
		local forwardDot = moveDir:Dot(Vector3.new(lookVector.X, 0, lookVector.Z).Unit)
		local rightDot = moveDir:Dot(Vector3.new(rightVector.X, 0, rightVector.Z).Unit)

		-- Determine primary direction
		if math.abs(forwardDot) > math.abs(rightDot) then
			-- Moving primarily forward/backward
			if forwardDot > 0 then
				rollCancelAnimId = "rbxassetid://96765830085186" -- Forward = right anim
			else
				rollCancelAnimId = "rbxassetid://135861148893814" -- Backward = left anim
			end
		else
			-- Moving primarily left/right
			if rightDot > 0 then
				rollCancelAnimId = "rbxassetid://96765830085186" -- Right = right anim
			else
				rollCancelAnimId = "rbxassetid://135861148893814" -- Left = left anim
			end
		end
	end

	-- Play rollcancel animation with highest priority to prevent interruption
	local rollCancelAnim = Instance.new("Animation")
	rollCancelAnim.AnimationId = rollCancelAnimId
	local rollCancelTrack = animator:LoadAnimation(rollCancelAnim)

	-- Use Action4 priority (highest) to ensure it doesn't get interrupted
	rollCancelTrack.Priority = Enum.AnimationPriority.Action4
	rollCancelTrack:Play(0.05)

	print(`[HitEffectsManager] Playing rollcancel animation ({rollCancelAnimId}) for {targetModel.Name}`)
end

-- Play successful dodge VFX particle effect
function HitEffectsManager:_playSuccessfulDodgeVFX(targetModel: Model)
	local rootPart = targetModel:FindFirstChild("HumanoidRootPart")
	if not rootPart then
		return
	end

	-- Get successful dodge VFX template
	local dodgeVFXPart = ReplicatedStorage.Assets.VFX.General_Combat.successful_dodge
	if not dodgeVFXPart then
		warn("[HitEffectsManager] Successful dodge VFX part not found")
		return
	end

	local vfxAttachment = dodgeVFXPart:FindFirstChild("Attachment")
	if not vfxAttachment then
		warn("[HitEffectsManager] Successful dodge VFX attachment not found")
		return
	end

	-- Clone attachment to player's root part
	local attachmentClone = vfxAttachment:Clone()
	attachmentClone.Parent = rootPart

	-- Emit particles
	for _, child in ipairs(attachmentClone:GetChildren()) do
		if child:IsA("ParticleEmitter") then
			child:Emit(child:GetAttribute("EmitCount") or child.Rate)
		end
	end

	-- Clean up after particles finish
	task.delay(3, function()
		if attachmentClone and attachmentClone.Parent then
			attachmentClone:Destroy()
		end
	end)

	print(`[HitEffectsManager] Playing successful dodge VFX on {targetModel.Name}`)
end

-- Play successful dodge highlight effect
function HitEffectsManager:_playSuccessfulDodgeHighlight(targetModel: Model)
	-- Get highlight template
	local dodgeVFXPart = ReplicatedStorage.Assets.VFX.General_Combat.successful_dodge
	if not dodgeVFXPart then
		warn("[HitEffectsManager] Successful dodge VFX part not found")
		return
	end

	local highlightTemplate = dodgeVFXPart:FindFirstChild("Highlight")
	if not highlightTemplate then
		warn("[HitEffectsManager] Successful dodge highlight not found")
		return
	end

	-- Clone highlight to character
	local highlightClone = highlightTemplate:Clone() :: Highlight
	highlightClone.Parent = targetModel
	highlightClone.Adornee = targetModel
	highlightClone.FillTransparency = 1
	highlightClone.OutlineTransparency = 1

	-- Tween to visible state
	local tweenInfo = TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	local tween = TweenService:Create(highlightClone, tweenInfo, {
		FillTransparency = 0.8,
		OutlineTransparency = 0.9,
	})

	tween:Play()

	-- Fade out and cleanup
	tween.Completed:Once(function()
		task.wait(0.2) -- Hold the highlight briefly
		local fadeOutInfo = TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		local fadeOut = TweenService:Create(highlightClone, fadeOutInfo, {
			FillTransparency = 1,
			OutlineTransparency = 1,
		})
		fadeOut:Play()
		fadeOut.Completed:Once(function()
			if highlightClone and highlightClone.Parent then
				highlightClone:Destroy()
			end
		end)
	end)

	print(`[HitEffectsManager] Playing successful dodge highlight on {targetModel.Name}`)
end

return HitEffectsManager
