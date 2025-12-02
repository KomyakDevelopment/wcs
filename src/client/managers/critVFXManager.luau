--!strict
-- Crit VFX Manager
-- Handles visual and sound effects for critical attacks (heavy punch, heavy slash)
-- VFX is synced with animations by listening to Animator.AnimationPlayed on other characters

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Animation IDs for crit detection (must match heavyPunch.luau and heavySlash.luau)
local HEAVY_PUNCH_ANIM_ID = "rbxassetid://105621431802545"
local HEAVY_SLASH_ANIM_ID = "rbxassetid://136860865307002"

local CritVFXManager = {}
CritVFXManager.__index = CritVFXManager

function CritVFXManager.new()
	local self = setmetatable({}, CritVFXManager)

	self.characterConnections = {} :: { [Model]: RBXScriptConnection }

	-- Setup character monitoring
	self:_setupCharacterMonitoring()

	print("[CritVFXManager] Initialized")
	return self
end

-- Setup monitoring for all characters in workspace
function CritVFXManager:_setupCharacterMonitoring()
	-- Monitor existing characters
	for _, character in ipairs(workspace:GetChildren()) do
		if character:IsA("Model") and character:FindFirstChild("Humanoid") then
			self:_monitorCharacter(character)
		end
	end

	-- Monitor new characters
	workspace.ChildAdded:Connect(function(child)
		if child:IsA("Model") then
			-- Wait for humanoid to confirm it's a character
			local humanoid = child:WaitForChild("Humanoid", 5)
			if humanoid then
				self:_monitorCharacter(child)
			end
		end
	end)

	-- Cleanup removed characters
	workspace.ChildRemoved:Connect(function(child)
		if self.characterConnections[child] then
			self.characterConnections[child]:Disconnect()
			self.characterConnections[child] = nil
		end
	end)

	print("[CritVFXManager] Character monitoring setup complete")
end

-- Monitor a character's animator for crit animations
function CritVFXManager:_monitorCharacter(character: Model)
	-- Skip local player - they play VFX immediately in OnStartClient
	local localPlayer = Players.LocalPlayer
	if localPlayer and localPlayer.Character == character then
		return
	end

	-- Skip if already monitoring
	if self.characterConnections[character] then
		return
	end

	local humanoid = character:FindFirstChild("Humanoid") :: Humanoid?
	if not humanoid then
		return
	end

	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		-- Wait for animator to be added
		humanoid.ChildAdded:Connect(function(child)
			if child:IsA("Animator") and not self.characterConnections[character] then
				self:_connectAnimator(character, child :: Animator)
			end
		end)
		return
	end

	self:_connectAnimator(character, animator)
end

-- Connect to animator's AnimationPlayed event
function CritVFXManager:_connectAnimator(character: Model, animator: Animator)
	self.characterConnections[character] = animator.AnimationPlayed:Connect(function(animTrack)
		if not animTrack.Animation then
			return
		end

		local animId = animTrack.Animation.AnimationId

		if animId == HEAVY_PUNCH_ANIM_ID then
			print(`[CritVFXManager] Detected heavy punch animation on {character.Name}`)
			self:_playHeavyPunchVFX(character)
		elseif animId == HEAVY_SLASH_ANIM_ID then
			print(`[CritVFXManager] Detected heavy slash animation on {character.Name}`)
			self:_playHeavySlashVFX(character)
		end
	end)
end

-- Play heavy punch VFX
function CritVFXManager:_playHeavyPunchVFX(character: Model)
	local humanoidRootPart = character:FindFirstChild("HumanoidRootPart")
	if not humanoidRootPart then
		return
	end

	-- Get VFX folder from Criticals
	local vfxFolder = ReplicatedStorage:FindFirstChild("Assets")
		and ReplicatedStorage.Assets:FindFirstChild("VFX")
		and ReplicatedStorage.Assets.VFX:FindFirstChild("Weapon_Classes")
		and ReplicatedStorage.Assets.VFX.Weapon_Classes:FindFirstChild("Criticals")
		and ReplicatedStorage.Assets.VFX.Weapon_Classes.Criticals:FindFirstChild("Light_Weapons")
		and ReplicatedStorage.Assets.VFX.Weapon_Classes.Criticals.Light_Weapons:FindFirstChild("heavyPunch")
		and ReplicatedStorage.Assets.VFX.Weapon_Classes.Criticals.Light_Weapons.heavyPunch:FindFirstChild("vfx")

	if not vfxFolder then
		warn("[CritVFXManager] Heavy punch VFX folder not found")
		return
	end

	local animLength = 0.7 -- Default animation length
	local clonedAttachments = {} :: { Attachment }

	-- Process VFX_attachment (particles on HumanoidRootPart)
	local vfxAttachment = vfxFolder:FindFirstChild("VFX_attachment")
	if vfxAttachment and vfxAttachment:IsA("Attachment") then
		local attachmentClone = vfxAttachment:Clone()
		attachmentClone.Parent = humanoidRootPart
		table.insert(clonedAttachments, attachmentClone)

		-- Process all particle emitters - emit based on their attributes
		for _, emitter in ipairs(attachmentClone:GetDescendants()) do
			if emitter:IsA("ParticleEmitter") then
				emitter.Enabled = false
				local emitDelay = emitter:GetAttribute("EmitDelay") or 0
				local emitCount = emitter:GetAttribute("EmitCount") or emitter.Rate

				if emitDelay > 0 then
					task.delay(emitDelay, function()
						if emitter and emitter.Parent then
							emitter:Emit(emitCount)
						end
					end)
				else
					emitter:Emit(emitCount)
				end
			end
		end
	end

	-- Process limb-based folders (e.g., "Left Leg", "Right Arm", etc.)
	for _, child in ipairs(vfxFolder:GetChildren()) do
		if child:IsA("Folder") then
			local limbName = child.Name
			local limbPart = character:FindFirstChild(limbName)

			if limbPart then
				local attachmentTemplate = child:FindFirstChildOfClass("Attachment")
				if attachmentTemplate then
					local attachmentClone = attachmentTemplate:Clone()
					attachmentClone.Parent = limbPart
					table.insert(clonedAttachments, attachmentClone)

					-- Process trails with start/end timing attributes
					for _, trailChild in ipairs(attachmentClone:GetChildren()) do
						if trailChild:IsA("Trail") then
							local startTime = trailChild:GetAttribute("start")
							local endTime = trailChild:GetAttribute("end")

							trailChild.Enabled = false

							if startTime and startTime > 0 then
								task.delay(startTime, function()
									if trailChild and trailChild.Parent then
										trailChild.Enabled = true
									end
								end)
							else
								trailChild.Enabled = true
							end

							if endTime and endTime > 0 then
								task.delay(endTime, function()
									if trailChild and trailChild.Parent then
										trailChild.Enabled = false
									end
								end)
							end
						end
					end
				end
			end
		end
	end

	-- Cleanup all cloned attachments after animation
	task.delay(animLength + 0.5, function()
		for _, attachment in ipairs(clonedAttachments) do
			if attachment and attachment.Parent then
				attachment:Destroy()
			end
		end
	end)
end

-- Play heavy slash VFX
function CritVFXManager:_playHeavySlashVFX(character: Model)
	local humanoidRootPart = character:FindFirstChild("HumanoidRootPart")
	if not humanoidRootPart then
		return
	end

	-- Get VFX folder for heavySlash
	local vfxFolder = ReplicatedStorage:FindFirstChild("Assets")
		and ReplicatedStorage.Assets:FindFirstChild("VFX")
		and ReplicatedStorage.Assets.VFX:FindFirstChild("Weapon_Classes")
		and ReplicatedStorage.Assets.VFX.Weapon_Classes:FindFirstChild("Criticals")
		and ReplicatedStorage.Assets.VFX.Weapon_Classes.Criticals:FindFirstChild("Light_Weapons")
		and ReplicatedStorage.Assets.VFX.Weapon_Classes.Criticals.Light_Weapons:FindFirstChild("heavySlash")
		and ReplicatedStorage.Assets.VFX.Weapon_Classes.Criticals.Light_Weapons.heavySlash:FindFirstChild("vfx")

	if not vfxFolder then
		return
	end

	local animLength = 0.7 -- Default animation length
	local clonedAttachments = {} :: { Attachment }

	-- Clone VFX_attachment directly to HRP
	local vfxAttachment = vfxFolder:FindFirstChild("VFX_attachment")
	if vfxAttachment and vfxAttachment:IsA("Attachment") then
		local attachmentClone = vfxAttachment:Clone()
		attachmentClone.Parent = humanoidRootPart
		table.insert(clonedAttachments, attachmentClone)

		-- Emit particles
		for _, emitter in ipairs(attachmentClone:GetDescendants()) do
			if emitter:IsA("ParticleEmitter") then
				emitter.Enabled = false
				local emitDelay = emitter:GetAttribute("EmitDelay") or 0
				local emitCount = emitter:GetAttribute("EmitCount") or emitter.Rate
				if emitDelay > 0 then
					task.delay(emitDelay, function()
						if emitter and emitter.Parent then
							emitter:Emit(emitCount)
						end
					end)
				else
					emitter:Emit(emitCount)
				end
			end
		end

		-- Handle beams (sync with slash timings)
		for _, beam in ipairs(attachmentClone:GetDescendants()) do
			if beam:IsA("Beam") then
				beam.Enabled = false
				local duration = beam:GetAttribute("Duration") or 0.15

				local timing = nil
				local parent = beam.Parent
				while parent and parent ~= attachmentClone do
					if parent.Name == "slash1" then
						timing = 0.55
						break
					elseif parent.Name == "slash2" then
						timing = 0.8
						break
					end
					parent = parent.Parent
				end

				if timing then
					task.delay(timing, function()
						if beam and beam.Parent then
							beam.Enabled = true
							task.delay(duration, function()
								if beam and beam.Parent then
									beam.Enabled = false
								end
							end)
						end
					end)
				end
			end
		end
	end

	-- Cleanup after animation
	task.delay(animLength + 0.5, function()
		for _, attachment in ipairs(clonedAttachments) do
			if attachment and attachment.Parent then
				attachment:Destroy()
			end
		end
	end)
end

return CritVFXManager
