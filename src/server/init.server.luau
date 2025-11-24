local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local WCS = require(ReplicatedStorage.Packages.wcs)

local StunIndicatorManager = require(ReplicatedStorage.Shared.managers.stunIndicatorManager)
local EquipmentManager = require(ReplicatedStorage.Shared.managers.equipmentManager)
local PostureManager = require(ReplicatedStorage.Shared.managers.postureManager)
local DeathManager = require(script.managers.deathManager)
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

local airdashCameraRemote = Instance.new("RemoteEvent")
airdashCameraRemote.Name = "SetAirdashCamera"
airdashCameraRemote.Parent = ReplicatedStorage

-- Expose AirdashCameraStore to dodge skill (shared module needs access)
_G.AirdashCameraStore = AirdashCameraStore

-- Handle airdash camera direction from client
airdashCameraRemote.OnServerEvent:Connect(function(player, cameraDirection)
	if typeof(cameraDirection) == "Vector3" then
		AirdashCameraStore.set(player, cameraDirection)
		print(`[Server] Stored airdash camera for {player.Name}: {cameraDirection}`)
	end
end)

-- Initialize managers (after remotes are created)
local stunIndicatorManager = StunIndicatorManager.new()
local postureManager = PostureManager.new()
local deathManager = DeathManager.new()

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

-- Create the regular dummy after server has started
local dummy = workspace:WaitForChild("Dummy")
local dummyWcsChar = WCS.Character.new(dummy)

-- Attach equipment manager to dummy (no weapon equipped by default)
dummyWcsChar.EquipmentManager = EquipmentManager.new(dummyWcsChar)

-- Initialize posture for dummy
PostureManager.initializeCharacter(dummy, dummyWcsChar)

-- Note: Test dummies (BlockingDummy, ParryingDummy, MissParryDummy, DodgingDummy)
-- are initialized in testDummies.server.luau

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

-- Setup player (connect CharacterAdded)
local function setupPlayer(player: Player)
	-- Handle current character if exists
	if player.Character then
		setupCharacter(player, player.Character)
	end

	-- Handle future characters (respawns)
	player.CharacterAdded:Connect(function(character)
		setupCharacter(player, character)
	end)
end

-- Handle existing players (in case script runs after players joined)
for _, player in ipairs(Players:GetPlayers()) do
	setupPlayer(player)
end

-- Handle new players
Players.PlayerAdded:Connect(setupPlayer)
