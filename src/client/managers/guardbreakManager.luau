--!strict
-- Guardbreak Manager
-- Handles visual and sound effects for guardbreak (blockbreak)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GuardbreakManager = {}
GuardbreakManager.__index = GuardbreakManager

function GuardbreakManager.new()
	local self = setmetatable({}, GuardbreakManager)

	-- Setup remote event listeners
	self:_setupRemotes()

	print("[GuardbreakManager] Initialized")
	return self
end

-- Setup remote event listeners
function GuardbreakManager:_setupRemotes()
	-- Wait for remote created by server
	local guardbreakRemote = ReplicatedStorage:WaitForChild("PlayGuardbreak") :: RemoteEvent
	guardbreakRemote.OnClientEvent:Connect(function(targetCharacter: Model)
		self:playGuardbreakEffects(targetCharacter)
	end)
end

-- Play guardbreak VFX and SFX (called when player is guardbroken)
function GuardbreakManager:playGuardbreakEffects(targetCharacter: Model)
	if not targetCharacter or not targetCharacter:IsA("Model") then
		warn("[GuardbreakManager] Invalid target character")
		return
	end

	-- Play VFX and SFX
	self:_playBlockbreakVFX(targetCharacter)
	self:_playGuardbreakSFX(targetCharacter)
end

-- Play blockbreak VFX particle effect
function GuardbreakManager:_playBlockbreakVFX(targetCharacter: Model)
	local rootPart = targetCharacter:FindFirstChild("HumanoidRootPart")
	if not rootPart then
		return
	end

	-- Get blockbreak VFX template
	local blockbreakVFXPart = ReplicatedStorage.Assets.VFX.General_Combat.blockbreak
	if not blockbreakVFXPart then
		warn("[GuardbreakManager] Blockbreak VFX part not found")
		return
	end

	local vfxAttachment = blockbreakVFXPart:FindFirstChild("Attachment")
	if not vfxAttachment then
		warn("[GuardbreakManager] Blockbreak VFX attachment not found")
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

	print(`[GuardbreakManager] Playing blockbreak VFX on {targetCharacter.Name}`)
end

-- Play guardbreak SFX
function GuardbreakManager:_playGuardbreakSFX(targetCharacter: Model)
	local rootPart = targetCharacter:FindFirstChild("HumanoidRootPart")
	if not rootPart then
		return
	end

	-- Get guardbreak SFX folder
	local guardbreakSFXFolder = ReplicatedStorage.Assets.SFX.General_Combat.guardbreak
	if not guardbreakSFXFolder then
		warn("[GuardbreakManager] Guardbreak SFX folder not found")
		return
	end

	-- Get all Sound instances from folder
	local sounds = {}
	for _, child in ipairs(guardbreakSFXFolder:GetChildren()) do
		if child:IsA("Sound") then
			table.insert(sounds, child)
		end
	end

	if #sounds == 0 then
		warn("[GuardbreakManager] No guardbreak sounds found in folder")
		return
	end

	-- Select random sound
	local randomSound = sounds[math.random(1, #sounds)]

	-- Clone and play the sound
	local soundClone = randomSound:Clone()
	soundClone.Parent = rootPart
	soundClone:Play()

	-- Clean up after sound finishes
	task.delay(soundClone.TimeLength + 0.1, function()
		if soundClone and soundClone.Parent then
			soundClone:Destroy()
		end
	end)

	print(`[GuardbreakManager] Playing guardbreak SFX: {randomSound.Name} on {targetCharacter.Name}`)
end

return GuardbreakManager
