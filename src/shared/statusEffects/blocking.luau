--!strict
-- Blocking Status Effect
-- Applied while holding block (F key)
-- Reduces movement speed by 50% and prevents certain actions

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local WCS = require(ReplicatedStorage.Packages.wcs)

local Blocking = WCS.RegisterStatusEffect("Blocking")

-- Movement speed reduction
local BLOCK_SPEED_MULTIPLIER = 0.5 -- 50% speed

function Blocking:OnStartServer()
	print("[Blocking] Server: Block active")

	-- Reduce movement speed
	local character = self.Character.Instance
	local humanoid = character:FindFirstChild("Humanoid")
	if humanoid then
		self.originalWalkSpeed = humanoid.WalkSpeed
		humanoid.WalkSpeed = self.originalWalkSpeed * BLOCK_SPEED_MULTIPLIER
		print(`[Blocking] Server: Reduced speed to {humanoid.WalkSpeed}`)
	end
end

function Blocking:OnStartClient()
	print("[Blocking] Client: Block active - Movement slowed")
end

function Blocking:OnEndServer()
	print("[Blocking] Server: Block ended")

	-- Restore movement speed
	local character = self.Character.Instance
	local humanoid = character:FindFirstChild("Humanoid")
	if humanoid and self.originalWalkSpeed then
		humanoid.WalkSpeed = self.originalWalkSpeed
		print(`[Blocking] Server: Restored speed to {humanoid.WalkSpeed}`)
	end
end

function Blocking:OnEndClient()
	print("[Blocking] Client: Block ended")
end

return Blocking
