local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local WCS = require(ReplicatedStorage.Packages.wcs)

local StunIndicatorManager = require(ReplicatedStorage.Shared.managers.stunIndicatorManager)
local EquipmentManager = require(ReplicatedStorage.Shared.managers.equipmentManager)
local PostureManager = require(ReplicatedStorage.Shared.managers.postureManager)

local Server = WCS.CreateServer()

Server:RegisterDirectory(ReplicatedStorage.Shared.movesets)
Server:RegisterDirectory(ReplicatedStorage.Shared.skills)
Server:RegisterDirectory(ReplicatedStorage.Shared.statusEffects)

Server:Start()

-- Initialize stun indicator manager (server-side)
local stunIndicatorManager = StunIndicatorManager.new()

-- Initialize posture manager (handles posture damage, recovery, and guardbreak)
local postureManager = PostureManager.new()

-- Create RemoteEvent for equipment requests
local equipRemote = Instance.new("RemoteEvent")
equipRemote.Name = "EquipWeapon"
equipRemote.Parent = ReplicatedStorage

-- Create RemoteEvent for hit effects (server -> clients)
local hitEffectsRemote = Instance.new("RemoteEvent")
hitEffectsRemote.Name = "PlayHitEffects"
hitEffectsRemote.Parent = ReplicatedStorage

-- Create RemoteEvents for block/parry effects (server -> clients)
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

Players.PlayerAdded:Connect(function(player)
	player.CharacterAdded:Connect(function(character)
		local humanoid = character:WaitForChild("Humanoid")

		-- Create WCS character
		local wcsCharacter = WCS.Character.new(character)

		-- Apply Base moveset by default (gives access to Dodge only)
		-- Punch and Block require a weapon to be equipped
		wcsCharacter:ApplyMoveset("Base")

		-- Attach equipment manager (no weapon equipped by default)
		wcsCharacter.EquipmentManager = EquipmentManager.new(wcsCharacter)

		-- Initialize posture for this character (pass WCS character to avoid lookup)
		PostureManager.initializeCharacter(character, wcsCharacter)

		humanoid.Died:Once(function()
			-- Cleanup equipment manager
			if wcsCharacter.EquipmentManager then
				wcsCharacter.EquipmentManager:destroy()
			end

			wcsCharacter:Destroy()
		end)
	end)
end)
