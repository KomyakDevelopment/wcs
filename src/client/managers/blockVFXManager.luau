--!strict
-- Block VFX Manager
-- Handles visual and sound effects for blocking, parrying, and block hits

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Players = game:GetService("Players")

local BlockVFXManager = {}
BlockVFXManager.__index = BlockVFXManager

function BlockVFXManager.new()
	local self = setmetatable({}, BlockVFXManager)

	-- VFX attachment paths
	self.parryFlashAttachment = ReplicatedStorage.Assets.VFX.General_Combat.parry_flash.Attachment
	self.blockAttachment = ReplicatedStorage.Assets.VFX.General_Combat.block.Attachment
	self.parryAttachment = ReplicatedStorage.Assets.VFX.General_Combat.parry.Attachment
	self.blockHighlight = ReplicatedStorage.Assets.VFX.General_Combat.block.Highlight

	-- SFX folder paths
	self.blockSFXFolder = ReplicatedStorage.Assets.SFX.Weapon_Classes.Fists.block
	self.parrySFXFolder = ReplicatedStorage.Assets.SFX.General_Combat.parry

	-- Setup remote event listeners
	self:_setupRemotes()

	print("[BlockVFXManager] Initialized")
	return self
end

-- Setup remote event listeners
function BlockVFXManager:_setupRemotes()
	-- Wait for remotes created by server
	local parryFlashRemote = ReplicatedStorage:WaitForChild("PlayParryFlashVFX") :: RemoteEvent
	parryFlashRemote.OnClientEvent:Connect(function(targetCharacter, attackPhase)
		self:playParryFlashVFX(targetCharacter, attackPhase)
	end)

	local parryVFXRemote = ReplicatedStorage:WaitForChild("PlayParryVFX") :: RemoteEvent
	parryVFXRemote.OnClientEvent:Connect(function(targetCharacter)
		self:playParryVFX(targetCharacter)
	end)

	local blockHitVFXRemote = ReplicatedStorage:WaitForChild("PlayBlockHitVFX") :: RemoteEvent
	blockHitVFXRemote.OnClientEvent:Connect(function(targetCharacter)
		self:playBlockHitVFX(targetCharacter)
	end)

	print("[BlockVFXManager] Remote events setup complete")
end

-- Play parry flash VFX (timing indicator shown at start of every M1 attack)
function BlockVFXManager:playParryFlashVFX(character: Model, attackPhase: number?)
	if not character then
		return
	end

	-- Default to phase 2 (right arm) if no phase specified
	attackPhase = attackPhase or 2

	print(`[BlockVFXManager] Playing parry flash for {character.Name}, phase {attackPhase}`)

	-- Get the parry flash attachment source
	local parryFlashSource = self.parryFlashAttachment
	if not parryFlashSource then
		warn("[BlockVFXManager] Parry flash attachment not found")
		return
	end

	-- Determine target grip attachment based on phase
	local targetGripAttachment

	if attackPhase == 1 or attackPhase == 3 then
		-- Left arm
		local leftArm = character:FindFirstChild("Left Arm") or character:FindFirstChild("LeftHand")
		if leftArm then
			targetGripAttachment = leftArm:FindFirstChild("LeftGripAttachment")
		end
	elseif attackPhase == 2 then
		-- Right arm
		local rightArm = character:FindFirstChild("Right Arm") or character:FindFirstChild("RightHand")
		if rightArm then
			targetGripAttachment = rightArm:FindFirstChild("RightGripAttachment")
		end
	elseif attackPhase == 4 then
		-- Left foot
		local leftLeg = character:FindFirstChild("Left Leg") or character:FindFirstChild("LeftFoot")
		if leftLeg then
			targetGripAttachment = leftLeg:FindFirstChild("LeftFootAttachment")
		end
	end

	if not targetGripAttachment then
		warn(`[BlockVFXManager] Could not find grip attachment for phase {attackPhase}`)
		return
	end

	-- CLONE the attachment so each client has their own copy
	local parryFlashClone = parryFlashSource:Clone()
	parryFlashClone.Parent = targetGripAttachment

	-- Emit all ParticleEmitters
	local maxLifetime = 0
	for _, child in ipairs(parryFlashClone:GetChildren()) do
		if child:IsA("ParticleEmitter") then
			-- Get emit count
			local emitCount = child:GetAttribute("EmitCount")
			if typeof(emitCount) ~= "number" then
				emitCount = child.Rate or 10
			end

			-- Emit particles
			child:Emit(emitCount)

			-- Calculate lifetime for cleanup
			local duration = child:GetAttribute("Duration")
			if typeof(duration) ~= "number" then
				duration = 1
			end
			local lifetime = child.Lifetime.Max + duration
			if lifetime > maxLifetime then
				maxLifetime = lifetime
			end
		end
	end

	-- Destroy the cloned attachment after VFX finishes
	task.delay(maxLifetime + 0.5, function()
		if parryFlashClone and parryFlashClone.Parent then
			parryFlashClone:Destroy()
		end
	end)

	print(`[BlockVFXManager] Played parry flash VFX for phase {attackPhase}`)
end

-- Play parry VFX (parry flash on right hand + parry effect on torso)
function BlockVFXManager:playParryVFX(character: Model)
	if not character then
		return
	end

	print(`[BlockVFXManager] Playing parry VFX for {character.Name}`)

	-- Parry flash on right arm's RightGripAttachment
	local rightArm = character:FindFirstChild("Right Arm") or character:FindFirstChild("RightHand")
	if rightArm then
		local rightGripAttachment = rightArm:FindFirstChild("RightGripAttachment")
		if rightGripAttachment and rightGripAttachment:IsA("Attachment") then
			self:_emitAttachmentVFXAtAttachment(self.parryFlashAttachment, rightGripAttachment)
		else
			self:_emitAttachmentVFX(self.parryFlashAttachment, rightArm)
		end
	else
		warn(`[BlockVFXManager] Right arm not found on {character.Name}`)
	end

	-- Parry effect on torso
	local torso = character:FindFirstChild("UpperTorso") or character:FindFirstChild("Torso")
	if torso then
		self:_emitAttachmentVFX(self.parryAttachment, torso)
	else
		warn(`[BlockVFXManager] Torso not found on {character.Name}`)
	end

	-- Play parry SFX
	self:_playSFXFromFolder(self.parrySFXFolder, character)
end

-- Play block hit VFX (block effect on torso + highlight outline)
function BlockVFXManager:playBlockHitVFX(character: Model)
	if not character then
		return
	end

	print(`[BlockVFXManager] Playing block hit VFX for {character.Name}`)

	-- Block effect on torso
	local torso = character:FindFirstChild("UpperTorso") or character:FindFirstChild("Torso")
	if torso then
		self:_emitAttachmentVFX(self.blockAttachment, torso)
	else
		warn(`[BlockVFXManager] Torso not found on {character.Name}`)
	end

	-- Play block highlight outline effect
	self:_playBlockHighlight(character)

	-- Play block SFX
	self:_playSFXFromFolder(self.blockSFXFolder, character)
end

-- Play block highlight outline effect (flash on block)
function BlockVFXManager:_playBlockHighlight(character: Model)
	if not self.blockHighlight then
		warn("[BlockVFXManager] Block highlight template not found")
		return
	end

	-- Clone the highlight and parent to character
	local highlightClone = self.blockHighlight:Clone() :: Highlight
	highlightClone.Parent = character
	highlightClone.Adornee = character

	-- Start fully transparent
	highlightClone.FillTransparency = 1
	highlightClone.OutlineTransparency = 1

	-- Tween settings
	local flashInTime = 0.08
	local flashOutTime = 0.15

	-- Tween in (flash visible)
	local tweenInInfo = TweenInfo.new(flashInTime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	local tweenIn = TweenService:Create(highlightClone, tweenInInfo, {
		FillTransparency = 0.6,
		OutlineTransparency = 0.25,
	})

	-- Tween out (fade back to invisible)
	local tweenOutInfo = TweenInfo.new(flashOutTime, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	local tweenOut = TweenService:Create(highlightClone, tweenOutInfo, {
		FillTransparency = 1,
		OutlineTransparency = 1,
	})

	-- Play tween sequence
	tweenIn:Play()
	tweenIn.Completed:Once(function()
		tweenOut:Play()
	end)

	-- Cleanup after tweens complete
	tweenOut.Completed:Once(function()
		if highlightClone and highlightClone.Parent then
			highlightClone:Destroy()
		end
	end)

	print(`[BlockVFXManager] Playing block highlight for {character.Name}`)
end

-- Emit VFX at a specific attachment's location (parents to body part, positioned at attachment)
function BlockVFXManager:_emitAttachmentVFXAtAttachment(templateAttachment: Attachment, targetAttachment: Attachment)
	if not targetAttachment or not targetAttachment:IsA("Attachment") then
		warn("[BlockVFXManager] Target attachment is invalid")
		return
	end

	local targetBodyPart = targetAttachment.Parent
	if not targetBodyPart or not targetBodyPart:IsA("BasePart") then
		warn("[BlockVFXManager] Target attachment's parent is not a BasePart")
		return
	end

	-- Clone the template attachment and parent to the body part
	local attachmentClone = templateAttachment:Clone()
	attachmentClone.Parent = targetBodyPart
	attachmentClone.Name = templateAttachment.Name .. "_VFX"

	-- Position it at the target attachment's location
	attachmentClone.CFrame = targetAttachment.CFrame

	-- Emit all particle emitters in the cloned attachment
	local emitters = {}
	for _, child in ipairs(attachmentClone:GetChildren()) do
		if child:IsA("ParticleEmitter") then
			table.insert(emitters, child)
			local emitCount = child:GetAttribute("EmitCount") or child.Rate or 10
			child:Emit(emitCount)
			print(`[BlockVFXManager] Emitted {emitCount} particles from {child.Name} at attachment`)
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

	task.delay(maxLifetime + 0.5, function()
		if attachmentClone and attachmentClone.Parent then
			attachmentClone:Destroy()
		end
	end)
end

-- Emit all particle emitters from a template attachment to a target body part
function BlockVFXManager:_emitAttachmentVFX(templateAttachment: Attachment, targetBodyPart: BasePart)
	-- Clone the entire attachment to the target body part
	local attachmentClone = templateAttachment:Clone()
	attachmentClone.Parent = targetBodyPart

	-- Emit all particle emitters in the cloned attachment
	local emitters = {}
	for _, child in ipairs(attachmentClone:GetChildren()) do
		if child:IsA("ParticleEmitter") then
			table.insert(emitters, child)
			-- Emit particles based on emitter's Rate/EmitCount
			local emitCount = child:GetAttribute("EmitCount") or child.Rate or 10
			child:Emit(emitCount)
			print(`[BlockVFXManager] Emitted {emitCount} particles from {child.Name}`)
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

	-- Clean up attachment after all particles expire
	task.delay(maxLifetime + 0.5, function()
		if attachmentClone and attachmentClone.Parent then
			attachmentClone:Destroy()
		end
	end)
end

-- Play a random sound from a folder with spatial audio
function BlockVFXManager:_playSFXFromFolder(folder: Folder, character: Model)
	if not folder or not character then
		return
	end

	-- Get all Sound instances from folder
	local sounds = {}
	for _, child in ipairs(folder:GetChildren()) do
		if child:IsA("Sound") then
			table.insert(sounds, child)
		end
	end

	if #sounds == 0 then
		warn(`[BlockVFXManager] No sounds found in folder {folder.Name}`)
		return
	end

	-- Select random sound
	local randomSound = sounds[math.random(1, #sounds)]

	-- Find the character's HumanoidRootPart for spatial audio
	local rootPart = character:FindFirstChild("HumanoidRootPart") or character:FindFirstChild("Torso")
	if not rootPart then
		warn(`[BlockVFXManager] No HumanoidRootPart found on {character.Name}`)
		return
	end

	-- Clone the sound and parent it to the root part for spatial audio
	local soundClone = randomSound:Clone()
	soundClone.Parent = rootPart

	-- Play the sound
	soundClone:Play()

	-- Clean up after sound finishes
	task.delay(soundClone.TimeLength + 0.1, function()
		if soundClone and soundClone.Parent then
			soundClone:Destroy()
		end
	end)

	print(`[BlockVFXManager] Playing SFX: {randomSound.Name} from {folder.Name}`)
end

return BlockVFXManager
