--!strict
-- Block VFX Manager
-- Handles visual and sound effects for blocking, parrying, and block hits

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local BlockVFXManager = {}
BlockVFXManager.__index = BlockVFXManager

function BlockVFXManager.new()
	local self = setmetatable({}, BlockVFXManager)

	-- VFX attachment paths
	self.parryFlashAttachment = ReplicatedStorage.Assets.VFX.General_Combat.parry_flash.Attachment
	self.blockAttachment = ReplicatedStorage.Assets.VFX.General_Combat.block.Attachment
	self.parryAttachment = ReplicatedStorage.Assets.VFX.General_Combat.parry.Attachment

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
	parryFlashRemote.OnClientEvent:Connect(function(targetCharacter)
		self:playParryFlashVFX(targetCharacter)
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

-- Play parry flash VFX (when parry window starts)
function BlockVFXManager:playParryFlashVFX(character: Model)
	if not character then
		return
	end

	print(`[BlockVFXManager] Playing parry flash VFX for {character.Name}`)

	-- Parry flash on right arm's RightGripAttachment
	local rightArm = character:FindFirstChild("Right Arm") or character:FindFirstChild("RightHand")
	if rightArm then
		local rightGripAttachment = rightArm:FindFirstChild("RightGripAttachment")
		if rightGripAttachment and rightGripAttachment:IsA("Attachment") then
			-- Pass the RightGripAttachment as the target so VFX appears at grip position
			self:_emitAttachmentVFXAtAttachment(self.parryFlashAttachment, rightGripAttachment)
		else
			-- Fallback: use the arm itself if no RightGripAttachment found
			self:_emitAttachmentVFX(self.parryFlashAttachment, rightArm)
		end
	else
		warn(`[BlockVFXManager] Right arm not found on {character.Name}`)
	end

	-- Play parry SFX
	self:_playSFXFromFolder(self.parrySFXFolder, character)
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

-- Play block hit VFX (block effect on torso)
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

	-- Play block SFX
	self:_playSFXFromFolder(self.blockSFXFolder, character)
end

-- Emit VFX at a specific attachment's location (parents to attachment's parent with same position)
function BlockVFXManager:_emitAttachmentVFXAtAttachment(templateAttachment: Attachment, targetAttachment: Attachment)
	local targetBodyPart = targetAttachment.Parent
	if not targetBodyPart or not targetBodyPart:IsA("BasePart") then
		warn("[BlockVFXManager] Target attachment's parent is not a BasePart")
		return
	end

	-- Clone the template attachment
	local attachmentClone = templateAttachment:Clone()
	attachmentClone.Parent = targetBodyPart

	-- Copy position and orientation from target attachment
	attachmentClone.CFrame = targetAttachment.CFrame
	attachmentClone.Name = templateAttachment.Name .. "_VFX"

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
