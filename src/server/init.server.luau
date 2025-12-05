local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local WCS = require(ReplicatedStorage.Packages.wcs)

local StunIndicatorManager = require(ReplicatedStorage.Shared.managers.stunIndicatorManager)
local EquipmentManager = require(ReplicatedStorage.Shared.managers.equipmentManager)
local PostureManager = require(ReplicatedStorage.Shared.managers.postureManager)
local DeathManager = require(script.managers.deathManager)
local CollisionManager = require(script.managers.collisionManager)
local CombatTagManager = require(script.managers.combatTagManager)
local HealthRegenManager = require(script.managers.healthRegenManager)
local AirdashCameraStore = require(script.data.airdashCameraStore)

local Server = WCS.CreateServer()

Server:RegisterDirectory(ReplicatedStorage.Shared.movesets)
Server:RegisterDirectory(ReplicatedStorage.Shared.skills)
Server:RegisterDirectory(ReplicatedStorage.Shared.statusEffects)

Server:Start()

-- Create RemoteEvents FIRST (before managers, so clients can find them immediately)
local equipRemote = Instance.new("RemoteEvent")
equipRemote.Name = "EquipWeapon"
equipRemote.Parent = ReplicatedStorage

local hitEffectsRemote = Instance.new("RemoteEvent")
hitEffectsRemote.Name = "PlayHitEffects"
hitEffectsRemote.Parent = ReplicatedStorage

local parryFlashRemote = Instance.new("RemoteEvent")
parryFlashRemote.Name = "PlayParryFlashVFX"
parryFlashRemote.Parent = ReplicatedStorage

local parryVFXRemote = Instance.new("RemoteEvent")
parryVFXRemote.Name = "PlayParryVFX"
parryVFXRemote.Parent = ReplicatedStorage

local blockHitVFXRemote = Instance.new("RemoteEvent")
blockHitVFXRemote.Name = "PlayBlockHitVFX"
blockHitVFXRemote.Parent = ReplicatedStorage

local blockHitAnimRemote = Instance.new("RemoteEvent")
blockHitAnimRemote.Name = "PlayBlockHitAnimation"
blockHitAnimRemote.Parent = ReplicatedStorage

local parriedAnimRemote = Instance.new("RemoteEvent")
parriedAnimRemote.Name = "PlayParriedAnimation"
parriedAnimRemote.Parent = ReplicatedStorage

local playerDeathRemote = Instance.new("RemoteEvent")
playerDeathRemote.Name = "PlayerDeath"
playerDeathRemote.Parent = ReplicatedStorage

local rollCancelRemote = Instance.new("RemoteEvent")
rollCancelRemote.Name = "PlayRollCancel"
rollCancelRemote.Parent = ReplicatedStorage

local guardbreakRemote = Instance.new("RemoteEvent")
guardbreakRemote.Name = "PlayGuardbreak"
guardbreakRemote.Parent = ReplicatedStorage

local playerExecutedRemote = Instance.new("RemoteEvent")
playerExecutedRemote.Name = "PlayerExecuted"
playerExecutedRemote.Parent = ReplicatedStorage

local airdashCameraRemote = Instance.new("RemoteEvent")
airdashCameraRemote.Name = "SetAirdashCamera"
airdashCameraRemote.Parent = ReplicatedStorage

local toggleWeaponInHandRemote = Instance.new("RemoteEvent")
toggleWeaponInHandRemote.Name = "ToggleWeaponInHand"
toggleWeaponInHandRemote.Parent = ReplicatedStorage

local requestRespawnRemote = Instance.new("RemoteEvent")
requestRespawnRemote.Name = "RequestRespawn"
requestRespawnRemote.Parent = ReplicatedStorage

local confirmExecutionRemote = Instance.new("RemoteEvent")
confirmExecutionRemote.Name = "ConfirmExecution"
confirmExecutionRemote.Parent = ReplicatedStorage

local requestSpawnRemote = Instance.new("RemoteEvent")
requestSpawnRemote.Name = "RequestSpawn"
requestSpawnRemote.Parent = ReplicatedStorage

local sprintStateRemote = Instance.new("RemoteEvent")
sprintStateRemote.Name = "SprintStateChanged"
sprintStateRemote.Parent = ReplicatedStorage

local critVFXRemote = Instance.new("RemoteEvent")
critVFXRemote.Name = "PlayCritVFX"
critVFXRemote.Parent = ReplicatedStorage

-- Expose AirdashCameraStore to dodge skill (shared module needs access)
_G.AirdashCameraStore = AirdashCameraStore

-- DeathManager will be exposed after initialization (needed by grip skill for executions)

-- Handle airdash camera direction from client
airdashCameraRemote.OnServerEvent:Connect(function(player, cameraDirection)
	if typeof(cameraDirection) == "Vector3" then
		AirdashCameraStore.set(player, cameraDirection)
		print(`[Server] Stored airdash camera for {player.Name}: {cameraDirection}`)
	end
end)

-- Handle sprint state from client (SprintManager sets this attribute)
sprintStateRemote.OnServerEvent:Connect(function(player, isSprinting)
	local character = player.Character
	if character and typeof(isSprinting) == "boolean" then
		character:SetAttribute("IsSprinting", isSprinting)
	end
end)

-- Initialize managers (after remotes are created)
local _stunIndicatorManager = StunIndicatorManager.new()
local _postureManager = PostureManager.new()
local deathManager = DeathManager.new()
local _collisionManager = CollisionManager.new()
local combatTagManager = CombatTagManager.new()
local _healthRegenManager = HealthRegenManager.new()

-- Expose DeathManager for grip skill to use for executions
_G.DeathManager = deathManager

-- Expose CombatTagManager for skills to tag players after damage
_G.CombatTagManager = combatTagManager

-- Handle equip requests from clients
equipRemote.OnServerEvent:Connect(function(player, weaponId)
	local character = player.Character
	if not character then
		return
	end

	local wcsCharacter = WCS.Character.GetCharacterFromInstance(character)
	if not wcsCharacter or not wcsCharacter.EquipmentManager then
		return
	end

	if weaponId then
		-- Equip weapon
		wcsCharacter.EquipmentManager:equip(weaponId)
	else
		-- Unequip weapon
		wcsCharacter.EquipmentManager:unequip()
	end
end)

-- Handle toggle weapon in hand requests from clients
toggleWeaponInHandRemote.OnServerEvent:Connect(function(player)
	local character = player.Character
	if not character then
		return
	end

	local wcsCharacter = WCS.Character.GetCharacterFromInstance(character)
	if not wcsCharacter or not wcsCharacter.EquipmentManager then
		return
	end

	-- Toggle weapon between back and hand
	wcsCharacter.EquipmentManager:toggleWeaponInHand()
end)

-- Handle respawn requests from clients (after execution death)
requestRespawnRemote.OnServerEvent:Connect(function(player)
	-- Only respawn if player doesn't have a character or character is dead
	local character = player.Character
	local humanoid = character and character:FindFirstChild("Humanoid") :: Humanoid?

	if not character or not humanoid or humanoid.Health <= 0 then
		player:LoadCharacter()
		print(`[Server] Respawning {player.Name} by request`)
	end
end)

-- Handle execution confirmation from clients (player clicked continue after being gripped)
confirmExecutionRemote.OnServerEvent:Connect(function(player)
	local character = player.Character
	if not character then
		return
	end

	local humanoid = character:FindFirstChild("Humanoid") :: Humanoid?
	if not humanoid then
		return
	end

	-- Check if player is marked for execution
	if not deathManager:isMarkedForExecution(player) then
		warn(`[Server] {player.Name} tried to confirm execution but is not marked`)
		return
	end

	print(`[Server] {player.Name} confirmed execution - killing and respawning`)

	-- Prepare for execution (clear all protection)
	deathManager:prepareForExecution(player)

	-- Enable BreakJointsOnDeath so death properly breaks the character
	humanoid.BreakJointsOnDeath = true

	-- Kill the player
	humanoid.Health = 0

	-- Respawn after a short delay
	task.delay(0.5, function()
		if player and player.Parent then
			player:LoadCharacter()
			print(`[Server] {player.Name} respawned after execution`)
		end
	end)
end)

-- Create the regular dummy after server has started
local dummy = workspace:WaitForChild("Dummy")
local dummyWcsChar = WCS.Character.new(dummy)

-- Attach equipment manager to dummy (no weapon equipped by default)
dummyWcsChar.EquipmentManager = EquipmentManager.new(dummyWcsChar)

-- Initialize posture for dummy
PostureManager.initializeCharacter(dummy, dummyWcsChar)

-- Note: Test dummies (BlockingDummy, ParryingDummy, MissParryDummy, DodgingDummy)
-- are initialized in testDummies.server.luau

-- Apply player's avatar hair to their character
local function applyPlayerHair(player: Player, character: Model)
	local success, description = pcall(function()
		return Players:GetHumanoidDescriptionFromUserId(player.UserId)
	end)

	if not success or not description then
		warn(`[Server] Failed to get avatar description for {player.Name}`)
		return
	end

	local humanoid = character:FindFirstChild("Humanoid") :: Humanoid?
	if not humanoid then
		return
	end

	-- Get hair accessory IDs from the description
	local hairAccessories = description.HairAccessory
	if not hairAccessories or hairAccessories == "" then
		print(`[Server] {player.Name} has no hair accessories`)
		return
	end

	-- HairAccessory can be comma-separated list of asset IDs
	local hairIds = string.split(hairAccessories, ",")

	for _, hairIdStr in hairIds do
		local hairId = tonumber(hairIdStr)
		if hairId then
			local assetSuccess, accessory = pcall(function()
				return game:GetService("InsertService"):LoadAsset(hairId)
			end)

			if assetSuccess and accessory then
				-- The loaded asset is a Model containing the accessory
				local actualAccessory = accessory:FindFirstChildOfClass("Accessory")
				if actualAccessory then
					-- Apply custom hair texture by finding SpecialMesh in Handle
					local handle = actualAccessory:FindFirstChild("Handle")
					if handle then
						for _, descendant in handle:GetDescendants() do
							if descendant:IsA("SpecialMesh") then
								descendant.TextureId = "rbxassetid://9780804670"
							end
						end
					end
					actualAccessory.Parent = character
					print(`[Server] Applied hair accessory {hairId} to {player.Name}`)
				end
				accessory:Destroy() -- Clean up the container model
			else
				warn(`[Server] Failed to load hair accessory {hairId} for {player.Name}`)
			end
		end
	end
end

-- Setup character with WCS, moveset, equipment, and posture
local function setupCharacter(player: Player, character: Model)
	local humanoid = character:WaitForChild("Humanoid", 10) :: Humanoid?
	if not humanoid then
		warn(`[Server] Humanoid not found for {player.Name}`)
		return
	end

	-- Create WCS character
	local wcsCharacter = WCS.Character.new(character)

	-- Apply Base moveset by default (gives access to Dodge only)
	-- Punch and Block require a weapon to be equipped
	wcsCharacter:ApplyMoveset("Base")

	-- Attach equipment manager (no weapon equipped by default)
	wcsCharacter.EquipmentManager = EquipmentManager.new(wcsCharacter)

	-- Initialize posture for this character (pass WCS character to avoid lookup)
	PostureManager.initializeCharacter(character, wcsCharacter)

	-- Apply player's avatar hair to their character
	applyPlayerHair(player, character)

	print(`[Server] Character setup complete for {player.Name}`)

	-- Note: Death cleanup is handled by DeathManager
	-- We only need to destroy WCS character when humanoid dies
	humanoid.Died:Once(function()
		-- DeathManager handles equipment, posture, status effects cleanup
		-- We just need to destroy the WCS character wrapper
		task.defer(function()
			if wcsCharacter then
				wcsCharacter:Destroy()
			end
		end)
	end)
end

-- Track players who have done their initial spawn (clicked continue)
local playersReadyToSpawn = {} :: { [Player]: boolean }

-- Setup player for CharacterAdded events
local function setupPlayerCharacterAdded(player: Player)
	player.CharacterAdded:Connect(function(character)
		setupCharacter(player, character)
	end)
end

-- Setup NEW player (CharacterAutoLoads is disabled globally in Players service)
local function setupNewPlayer(player: Player)
	-- Handle future characters (respawns after clicking continue)
	setupPlayerCharacterAdded(player)
end

-- Handle initial spawn request from client (when they click continue)
requestSpawnRemote.OnServerEvent:Connect(function(player)
	-- Only allow initial spawn once
	if playersReadyToSpawn[player] then
		return
	end

	playersReadyToSpawn[player] = true

	-- Re-enable auto loads for future respawns (pcall for Studio compatibility)
	pcall(function()
		player.CharacterAutoLoads = true
	end)

	-- Spawn their character
	player:LoadCharacter()
	print(`[Server] Initial spawn for {player.Name} (clicked continue)`)
end)

-- Clean up when player leaves
Players.PlayerRemoving:Connect(function(player)
	playersReadyToSpawn[player] = nil
end)

-- Handle existing players (rare edge case - server script ran after player joined)
for _, player in ipairs(Players:GetPlayers()) do
	setupPlayerCharacterAdded(player)
end

-- Handle new players (they need to click continue to spawn)
Players.PlayerAdded:Connect(setupNewPlayer)
