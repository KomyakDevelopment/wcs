-- Daze Status Effect
-- Disables rolling and slows walkspeed by 50%
-- VFX is broadcast to all clients via RemoteEvent

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local WCS = require(ReplicatedStorage.Packages.wcs)

local Daze = WCS.RegisterStatusEffect("Daze")

-- Movement reduction: player moves at 50% speed
local SPEED_MULTIPLIER = 0.5

-- Get the remote for VFX (only exists on server after init)
local function getDazeVFXRemote(): RemoteEvent?
	if RunService:IsServer() then
		return ReplicatedStorage:FindFirstChild("DazeVFX") :: RemoteEvent?
	end
	return nil
end

function Daze:OnConstructServer()
	-- Store reference to track active daze
	if self.Character._ActiveDaze then
		self.Character._ActiveDaze:Stop()
	end
	self.Character._ActiveDaze = self
end

function Daze:OnStartServer()
	local character = self.Character
	local humanoid = character.Instance:FindFirstChild("Humanoid")

	if not humanoid then
		return
	end

	-- Get current walkspeed and calculate daze speed
	local originalSpeed = humanoid.WalkSpeed
	local dazeSpeed = originalSpeed * SPEED_MULTIPLIER

	-- Apply movement reduction using WCS SetHumanoidData
	self:SetHumanoidData({
		WalkSpeed = { dazeSpeed, "Set" },
	})

	-- Broadcast VFX to all clients
	local remote = getDazeVFXRemote()
	if remote then
		remote:FireAllClients(character.Instance, true) -- true = daze started
	end

	print(`[Daze] Applied to {character.Instance.Name} - Speed: {dazeSpeed}`)
end

function Daze:OnEndServer()
	-- Only clear if this is the active daze
	if self.Character._ActiveDaze == self then
		self.Character._ActiveDaze = nil
	end

	-- Broadcast VFX end to all clients
	local remote = getDazeVFXRemote()
	if remote then
		remote:FireAllClients(self.Character.Instance, false) -- false = daze ended
	end

	print(`[Daze] Ended on {self.Character.Instance.Name}`)
end

-- VFX is handled by dazeVFXManager.luau so all players can see it

return Daze
