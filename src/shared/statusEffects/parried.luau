--!strict
-- Parried Status Effect
-- Applied to attacker for 0.8s when their attack gets parried
-- This is a soft hitstun that locks them out of actions

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local WCS = require(ReplicatedStorage.Packages.wcs)

local Parried = WCS.RegisterStatusEffect("Parried")

-- Parried animation IDs (one plays at random)
local PARRIED_ANIMATIONS = {
	"rbxassetid://74164072649157",
	"rbxassetid://103428958756170",
	"rbxassetid://107330401286311",
}

function Parried:OnStartServer()
	print("[Parried] Server: Attacker got parried - Stunned (0.8s)")
end

function Parried:OnStartClient()
	-- Play parried animation
	self:_playParriedAnimation()
	print("[Parried] Client: You got parried - Punish window active!")
end

function Parried:OnEndServer()
	print("[Parried] Server: Parried stun ended")
end

function Parried:OnEndClient()
	-- Stop the animation
	if self.animTrack then
		self.animTrack:Stop(0.2)
		self.animTrack = nil
	end
	print("[Parried] Client: Parried stun ended - Can act now")
end

-- Play a random parried stagger animation
function Parried:_playParriedAnimation()
	if not RunService:IsClient() then
		return
	end

	local character = self.Character.Instance
	local humanoid = character:FindFirstChild("Humanoid")
	if not humanoid then
		return
	end

	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		return
	end

	-- Stop all Action priority animations first (attack animations)
	for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
		local priority = track.Priority
		if
			priority == Enum.AnimationPriority.Action
			or priority == Enum.AnimationPriority.Action2
			or priority == Enum.AnimationPriority.Action3
			or priority == Enum.AnimationPriority.Action4
		then
			track:Stop(0.1)
		end
	end

	-- Pick a random animation
	local randomAnimId = PARRIED_ANIMATIONS[math.random(1, #PARRIED_ANIMATIONS)]

	-- Create and play parried animation
	local animation = Instance.new("Animation")
	animation.AnimationId = randomAnimId
	self.animTrack = animator:LoadAnimation(animation)

	self.animTrack.Looped = false
	self.animTrack.Priority = Enum.AnimationPriority.Action4
	self.animTrack:Play(0.1)

	print(`[Parried] Playing animation: {randomAnimId}`)
end

return Parried
