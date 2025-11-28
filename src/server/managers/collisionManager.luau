--!strict
-- Collision Manager (Server)
-- Handles player collision groups so players don't collide with each other

local PhysicsService = game:GetService("PhysicsService")
local Players = game:GetService("Players")

local CollisionManager = {}
CollisionManager.__index = CollisionManager

-- Collision group name for players
local PLAYER_COLLISION_GROUP = "Players"

function CollisionManager.new()
	local self = setmetatable({}, CollisionManager)

	self:_setupCollisionGroups()
	self:_setupPlayerHandlers()

	print("[CollisionManager] Initialized - Player collisions disabled")
	return self
end

function CollisionManager:_setupCollisionGroups()
	-- Create the Players collision group if it doesn't exist
	local success, err = pcall(function()
		PhysicsService:RegisterCollisionGroup(PLAYER_COLLISION_GROUP)
	end)

	if not success and not string.find(err or "", "already exists") then
		warn(`[CollisionManager] Failed to create collision group: {err}`)
	end

	-- Make players not collide with each other
	PhysicsService:CollisionGroupSetCollidable(PLAYER_COLLISION_GROUP, PLAYER_COLLISION_GROUP, false)
end

function CollisionManager:_setupPlayerHandlers()
	-- Handle existing players
	for _, player in ipairs(Players:GetPlayers()) do
		self:_handlePlayer(player)
	end

	-- Handle new players
	Players.PlayerAdded:Connect(function(player)
		self:_handlePlayer(player)
	end)
end

function CollisionManager:_handlePlayer(player: Player)
	-- Handle current character
	if player.Character then
		self:_setCharacterCollisionGroup(player.Character)
	end

	-- Handle future characters (respawns)
	player.CharacterAdded:Connect(function(character)
		self:_setCharacterCollisionGroup(character)
	end)
end

function CollisionManager:_setCharacterCollisionGroup(character: Model)
	-- Set all existing parts to the Players collision group
	for _, part in ipairs(character:GetDescendants()) do
		if part:IsA("BasePart") then
			part.CollisionGroup = PLAYER_COLLISION_GROUP
		end
	end

	-- Handle parts added later (accessories, tools, etc.)
	character.DescendantAdded:Connect(function(descendant)
		if descendant:IsA("BasePart") then
			descendant.CollisionGroup = PLAYER_COLLISION_GROUP
		end
	end)
end

return CollisionManager
