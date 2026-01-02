--!strict
-- Daze VFX Manager (Client)
-- Handles Daze VFX for ALL characters so everyone can see the effect
-- Listens to DazeVFX RemoteEvent from server

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DazeVFXManager = {}
DazeVFXManager.__index = DazeVFXManager

function DazeVFXManager.new()
	local self = setmetatable({}, DazeVFXManager)

	self._connections = {} :: { RBXScriptConnection }
	self._activeVFX = {} :: { [Model]: { vfxPart: BasePart?, welds: { Weld | Motor6D } } }

	self:_setup()

	print("[DazeVFXManager] Initialized")
	return self
end

function DazeVFXManager:_setup()
	-- Wait for and connect to the DazeVFX remote
	local dazeVFXRemote = ReplicatedStorage:WaitForChild("DazeVFX", 10) :: RemoteEvent?
	if not dazeVFXRemote then
		warn("[DazeVFXManager] DazeVFX remote not found")
		return
	end

	table.insert(
		self._connections,
		dazeVFXRemote.OnClientEvent:Connect(function(characterModel: Model, isStarting: boolean)
			if isStarting then
				self:_onDazeStarted(characterModel)
			else
				self:_onDazeEnded(characterModel)
			end
		end)
	)
end

function DazeVFXManager:_onDazeStarted(characterModel: Model)
	if not characterModel or not characterModel:IsA("Model") then
		warn("[DazeVFXManager] Invalid character model for Daze VFX")
		return
	end

	print(`[DazeVFXManager] Daze started on {characterModel.Name}`)

	-- Cleanup any existing VFX first
	self:_cleanupVFX(characterModel, true)

	-- Get the status effect VFX folder
	local statusVFXFolder = ReplicatedStorage:FindFirstChild("Assets")
		and ReplicatedStorage.Assets:FindFirstChild("VFX")
		and ReplicatedStorage.Assets.VFX:FindFirstChild("Status_Effects")
		and ReplicatedStorage.Assets.VFX.Status_Effects:FindFirstChild("daze")

	if not statusVFXFolder then
		warn("[DazeVFXManager] VFX folder not found at ReplicatedStorage.Assets.VFX.Status_Effects.daze")
		return
	end

	-- Get the welds folder and VFX part
	local weldsFolder = statusVFXFolder:FindFirstChild("welds")
	local vfxPart = statusVFXFolder:FindFirstChild("daze")

	if not weldsFolder then
		warn("[DazeVFXManager] Welds folder not found")
		return
	end

	if not vfxPart then
		warn("[DazeVFXManager] VFX part (daze) not found")
		return
	end

	-- Get the target body part from the "parent" attribute
	local targetPartName = weldsFolder:GetAttribute("parent")
	if not targetPartName or typeof(targetPartName) ~= "string" then
		warn("[DazeVFXManager] Welds folder missing 'parent' attribute")
		return
	end

	local targetPart = characterModel:FindFirstChild(targetPartName)
	if not targetPart then
		warn(`[DazeVFXManager] Target body part '{targetPartName}' not found on character`)
		return
	end

	-- Clone and attach welds
	local clonedWelds = {}
	for _, weld in ipairs(weldsFolder:GetChildren()) do
		if weld:IsA("Weld") or weld:IsA("Motor6D") then
			local weldClone = weld:Clone()
			weldClone.Part0 = targetPart
			weldClone.Parent = targetPart
			table.insert(clonedWelds, weldClone)
		end
	end

	-- Clone and attach VFX part
	local clonedVFXPart = vfxPart:Clone()
	clonedVFXPart.Parent = targetPart

	-- Enable all particle emitters in the VFX part
	for _, child in ipairs(clonedVFXPart:GetDescendants()) do
		if child:IsA("ParticleEmitter") then
			child.Enabled = true
		end
	end

	-- Update weld Part1 references to point to the cloned VFX part
	for _, weldClone in ipairs(clonedWelds) do
		weldClone.Part1 = clonedVFXPart
	end

	-- Store references for cleanup (keyed by character model)
	self._activeVFX[characterModel] = {
		vfxPart = clonedVFXPart,
		welds = clonedWelds,
	}

	print(`[DazeVFXManager] VFX attached to {characterModel.Name}`)
end

function DazeVFXManager:_onDazeEnded(characterModel: Model)
	print(`[DazeVFXManager] Daze ended on {characterModel and characterModel.Name or "unknown"}`)

	self:_cleanupVFX(characterModel, false)
end

function DazeVFXManager:_cleanupVFX(characterModel: Model, immediate: boolean)
	local vfxData = self._activeVFX[characterModel]
	if not vfxData then
		return
	end

	local vfxPart = vfxData.vfxPart
	local welds = vfxData.welds

	if immediate then
		-- Immediate cleanup (character destroyed or new daze applied)
		if vfxPart and vfxPart.Parent then
			vfxPart:Destroy()
		end
		for _, weld in ipairs(welds) do
			if weld and weld.Parent then
				weld:Destroy()
			end
		end
	else
		-- Graceful cleanup (let particles fade out)
		if vfxPart then
			-- Disable emitters
			for _, child in ipairs(vfxPart:GetDescendants()) do
				if child:IsA("ParticleEmitter") then
					child.Enabled = false
				end
			end

			-- Calculate max particle lifetime
			local maxLifetime = 0
			for _, child in ipairs(vfxPart:GetDescendants()) do
				if child:IsA("ParticleEmitter") then
					local lifetime = child.Lifetime.Max
					if lifetime > maxLifetime then
						maxLifetime = lifetime
					end
				end
			end

			-- Delay destruction
			local vfxPartRef = vfxPart
			local weldsRef = welds

			task.delay(maxLifetime + 0.1, function()
				if vfxPartRef and vfxPartRef.Parent then
					vfxPartRef:Destroy()
				end
				for _, weld in ipairs(weldsRef) do
					if weld and weld.Parent then
						weld:Destroy()
					end
				end
			end)
		end
	end

	self._activeVFX[characterModel] = nil
end

function DazeVFXManager:destroy()
	-- Cleanup all VFX
	for characterModel, _ in pairs(self._activeVFX) do
		self:_cleanupVFX(characterModel, true)
	end

	-- Disconnect connections
	for _, connection in ipairs(self._connections) do
		connection:Disconnect()
	end
	self._connections = {}
end

return DazeVFXManager
