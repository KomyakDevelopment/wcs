--!strict
-- Stun Indicator Manager
-- Shows visual indicators welded to players' heads for debugging hitstun states
-- GREEN = No stun, YELLOW = Soft hitstun, RED = True hitstun

local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local StunIndicatorManager = {}
StunIndicatorManager.__index = StunIndicatorManager

-- Configuration
local ENABLED = true -- Set to false to disable indicators
local INDICATOR_OFFSET = Vector3.new(0, 2, 0) -- 2 studs above head
local UPDATE_RATE = 0.1 -- Update color every 0.1 seconds

-- Colors for different states
local COLORS = {
	None = Color3.fromRGB(0, 255, 0), -- Green
	SoftHitstun = Color3.fromRGB(255, 255, 0), -- Yellow
	TrueHitstun = Color3.fromRGB(255, 0, 0), -- Red
}

function StunIndicatorManager.new()
	local self = setmetatable({}, StunIndicatorManager)

	self.indicators = {} -- [character] = indicator part
	self.lastUpdate = 0

	if ENABLED then
		self:_startUpdating()
	end

	return self
end

-- Create indicator welded to character's head
function StunIndicatorManager:_createIndicator(character: Model): Part?
	-- Check if template exists
	local template = ReplicatedStorage.Assets.Testing:FindFirstChild("StunIndicator")
	if not template or not template:IsA("BasePart") then
		warn("[StunIndicator] StunIndicator template not found in ReplicatedStorage.Assets.Testing")
		return nil
	end

	-- Get the head
	local head = character:FindFirstChild("Head")
	if not head or not head:IsA("BasePart") then
		warn(`[StunIndicator] Head not found for {character.Name}`)
		return nil
	end

	-- Clone the indicator
	local indicator = template:Clone()
	indicator.Name = `StunIndicator_{character.Name}`
	indicator.Anchored = false -- Must be unanchored for welding
	indicator.CanCollide = false
	indicator.Massless = true -- Don't affect physics

	-- Position it above the head initially
	indicator.CFrame = head.CFrame + INDICATOR_OFFSET
	indicator.Parent = character -- Parent to character, not workspace

	-- Create weld to attach it to head
	local weld = Instance.new("WeldConstraint")
	weld.Name = "StunIndicatorWeld"
	weld.Part0 = head
	weld.Part1 = indicator
	weld.Parent = indicator

	-- Create attachment on head at offset position
	local attachment0 = Instance.new("Attachment")
	attachment0.Name = "StunIndicatorAttachment"
	attachment0.Position = INDICATOR_OFFSET
	attachment0.Parent = head

	-- Create attachment on indicator at its center
	local attachment1 = Instance.new("Attachment")
	attachment1.Name = "StunIndicatorAttachment"
	attachment1.Parent = indicator

	-- Use AlignPosition to maintain offset (more stable than just weld)
	local alignPosition = Instance.new("AlignPosition")
	alignPosition.Attachment0 = attachment1
	alignPosition.Attachment1 = attachment0
	alignPosition.MaxForce = 10000
	alignPosition.Responsiveness = 200
	alignPosition.RigidityEnabled = true
	alignPosition.Parent = indicator

	return indicator
end

-- Get hitstun state from status effect metadata (replicated from server)
function StunIndicatorManager:_getHitstunState(wcsCharacter): string
	if not wcsCharacter then
		return "None"
	end

	-- Try to get status effects and check their metadata
	local SoftHitstun = require(ReplicatedStorage.Shared.statusEffects.softHitstun)
	local TrueHitstun = require(ReplicatedStorage.Shared.statusEffects.trueHitstun)
	
	-- Check for soft hitstun via metadata
	local softHitstunInstances = {}
	local trueHitstunInstances = {}
	
	-- Get all instances of status effects from character
	-- We'll check by looking at the character's children for status effect instances
	for _, child in pairs(wcsCharacter.Instance:GetDescendants()) do
		if child:IsA("ObjectValue") and child.Name:find("StatusEffect") then
			local effect = child.Value
			if effect then
				local metadata = effect:GetMetadata and effect:GetMetadata()
				if metadata and metadata.Active then
					if metadata.Type == "SoftHitstun" then
						return "SoftHitstun"
					elseif metadata.Type == "TrueHitstun" then
						return "TrueHitstun"
					end
				end
			end
		end
	end
	
	-- Fallback: Check humanoid speed (less reliable but works)
	local humanoid = wcsCharacter.Instance:FindFirstChild("Humanoid")
	if humanoid then
		local speed = humanoid.WalkSpeed
		
		-- If speed is significantly reduced, they're in hitstun
		if speed < 6 then -- Normal is 16
			-- True hitstun = 15% speed (around 2.4)
			-- Soft hitstun = 20% speed (around 3.2)
			if speed < 3 then
				return "TrueHitstun"
			else
				return "SoftHitstun"
			end
		end
	end

	return "None"
end

-- Update indicator color for a character
function StunIndicatorManager:_updateIndicator(character: Model, wcsCharacter)
	if not ENABLED then
		return
	end

	local indicator = self.indicators[character]

	-- Create indicator if it doesn't exist
	if not indicator then
		indicator = self:_createIndicator(character)
		if not indicator then
			return
		end
		self.indicators[character] = indicator
	end

	-- Check if indicator still exists (might have been destroyed)
	if not indicator.Parent then
		self.indicators[character] = nil
		return
	end

	-- Update color based on state
	local state = self:_getHitstunState(wcsCharacter)
	indicator.Color = COLORS[state]
end

-- Start the update loop
function StunIndicatorManager:_startUpdating()
	RunService.Heartbeat:Connect(function()
		if not ENABLED then
			return
		end

		local currentTime = tick()
		if currentTime - self.lastUpdate < UPDATE_RATE then
			return
		end
		self.lastUpdate = currentTime

		-- Update all character indicators
		local WCS = require(ReplicatedStorage.Packages.wcs)

		for _, character in pairs(Workspace:GetChildren()) do
			if character:IsA("Model") and character:FindFirstChild("Humanoid") then
				local wcsCharacter = WCS.Character.GetCharacterFromInstance(character)
				self:_updateIndicator(character, wcsCharacter)
			end
		end
	end)
end

-- Clean up indicator for a character
function StunIndicatorManager:removeIndicator(character: Model)
	local indicator = self.indicators[character]
	if indicator then
		indicator:Destroy()
		self.indicators[character] = nil
	end
end

-- Clean up all indicators
function StunIndicatorManager:destroy()
	for character, indicator in pairs(self.indicators) do
		indicator:Destroy()
	end
	self.indicators = {}
end

return StunIndicatorManager
