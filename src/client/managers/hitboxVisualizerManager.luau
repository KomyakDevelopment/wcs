--!strict
-- Hitbox Visualizer Manager (Client)
-- Shows visual representation of weapon hitboxes when equipped
-- Simple sphere visualization matching actual hit detection code

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local CombatConfig = require(ReplicatedStorage.Shared.config.combatConfig)

local HitboxVisualizerManager = {}
HitboxVisualizerManager.__index = HitboxVisualizerManager

-- Visualization settings
local HITBOX_COLOR = Color3.fromRGB(255, 100, 100) -- Light red
local HITBOX_TRANSPARENCY = 0.7 -- Semi-transparent
local UPDATE_RATE = 0.016 -- Update every frame (~60fps)

function HitboxVisualizerManager.new()
	local self = setmetatable({}, HitboxVisualizerManager)

	self._player = Players.LocalPlayer
	self._character = nil :: Model?
	self._hrp = nil :: BasePart?
	self._currentWeapon = nil :: string?
	self._hitboxPart = nil :: Part?
	self._connections = {} :: { RBXScriptConnection }
	self._updateTimer = 0

	self:_setup()

	return self
end

function HitboxVisualizerManager:_setup()
	-- Wait for character
	if self._player.Character then
		self:_onCharacterAdded(self._player.Character)
	end

	local charConn = self._player.CharacterAdded:Connect(function(character)
		self:_onCharacterAdded(character)
	end)
	table.insert(self._connections, charConn)
end

function HitboxVisualizerManager:_onCharacterAdded(character: Model)
	-- Clean up old hitbox
	self:_destroyHitbox()

	self._character = character
	self._hrp = character:WaitForChild("HumanoidRootPart", 5) :: BasePart?

	if not self._hrp then
		warn("[HitboxVisualizer] HumanoidRootPart not found")
		return
	end

	-- Monitor equipped weapon changes (attribute is on character, not HRP)
	local attrConn = self._character:GetAttributeChangedSignal("EquippedWeapon"):Connect(function()
		self:_onWeaponChanged()
	end)
	table.insert(self._connections, attrConn)

	-- Initial check
	self:_onWeaponChanged()

	-- Update loop
	local updateConn = RunService.Heartbeat:Connect(function(deltaTime)
		self._updateTimer = self._updateTimer + deltaTime
		if self._updateTimer >= UPDATE_RATE then
			self._updateTimer = 0
			self:_updateHitbox()
		end
	end)
	table.insert(self._connections, updateConn)
end

function HitboxVisualizerManager:_onWeaponChanged()
	if not self._character then
		return
	end

	local equippedWeapon = self._character:GetAttribute("EquippedWeapon")

	-- Show hitbox for all weapons including fists (for debugging)
	if equippedWeapon then
		self._currentWeapon = equippedWeapon
		self:_createHitbox()
	else
		self._currentWeapon = nil
		self:_destroyHitbox()
	end
end

function HitboxVisualizerManager:_createHitbox()
	-- Destroy old hitbox first
	self:_destroyHitbox()

	if not self._hrp or not self._currentWeapon then
		return
	end

	-- Get weapon config for range
	local weaponConfig = CombatConfig.Weapons[self._currentWeapon]
	if not weaponConfig then
		return
	end

	local range = weaponConfig.Range

	-- Create a simple sphere to match actual hitbox detection
	-- The real hitbox is: Sphere at (Position - LookVector * 2) with radius = range
	local sphere = Instance.new("Part")
	sphere.Name = "HitboxVisualizer"
	sphere.Shape = Enum.PartType.Ball
	sphere.Size = Vector3.new(range * 2, range * 2, range * 2) -- Diameter = range * 2
	sphere.Anchored = true -- No physics
	sphere.CanCollide = false
	sphere.CanQuery = false
	sphere.CanTouch = false
	sphere.Color = HITBOX_COLOR
	sphere.Transparency = HITBOX_TRANSPARENCY
	sphere.Material = Enum.Material.ForceField
	sphere.CastShadow = false
	sphere.Parent = workspace

	self._hitboxPart = sphere

	print(`[HitboxVisualizer] Created sphere hitbox for {self._currentWeapon} with range {range}`)
end

function HitboxVisualizerManager:_updateHitbox()
	if not self._hitboxPart or not self._hrp or not self._currentWeapon then
		return
	end

	-- Get weapon config for range (in case it changed)
	local weaponConfig = CombatConfig.Weapons[self._currentWeapon]
	if not weaponConfig then
		return
	end

	local range = weaponConfig.Range

	-- Update size
	self._hitboxPart.Size = Vector3.new(range * 2, range * 2, range * 2)

	-- Position sphere 2 studs BEHIND the player (matches actual hitbox code)
	-- See punch.luau line 406: origin = humanoidRootPart.Position - (lookDirection * 2)
	local lookDirection = self._hrp.CFrame.LookVector
	local origin = self._hrp.Position - (lookDirection * 2)
	self._hitboxPart.Position = origin
end

function HitboxVisualizerManager:_destroyHitbox()
	if self._hitboxPart then
		self._hitboxPart:Destroy()
		self._hitboxPart = nil
	end
end

function HitboxVisualizerManager:destroy()
	for _, conn in ipairs(self._connections) do
		conn:Disconnect()
	end
	self._connections = {}

	self:_destroyHitbox()
end

return HitboxVisualizerManager
