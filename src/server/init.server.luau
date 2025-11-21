local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local WCS = require(ReplicatedStorage.Packages.wcs)

local StunIndicatorManager = require(ReplicatedStorage.Shared.managers.stunIndicatorManager)
local EquipmentManager = require(ReplicatedStorage.Shared.managers.equipmentManager)

local Server = WCS.CreateServer()

Server:RegisterDirectory(ReplicatedStorage.Shared.movesets)
Server:RegisterDirectory(ReplicatedStorage.Shared.skills)
Server:RegisterDirectory(ReplicatedStorage.Shared.statusEffects)

Server:Start()

-- Initialize stun indicator manager (server-side)
local stunIndicatorManager = StunIndicatorManager.new()

-- Create RemoteEvent for equipment requests
local equipRemote = Instance.new("RemoteEvent")
equipRemote.Name = "EquipWeapon"
equipRemote.Parent = ReplicatedStorage

-- Create RemoteEvent for hit effects (server -> clients)
local hitEffectsRemote = Instance.new("RemoteEvent")
hitEffectsRemote.Name = "PlayHitEffects"
hitEffectsRemote.Parent = ReplicatedStorage

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

-- Create the dummy after server has started
local dummy = workspace:WaitForChild("Dummy")
local dummyWcsChar = WCS.Character.new(dummy)

-- Attach equipment manager to dummy (no weapon equipped by default)
dummyWcsChar.EquipmentManager = EquipmentManager.new(dummyWcsChar)

Players.PlayerAdded:Connect(function(player)
	player.CharacterAdded:Connect(function(character)
		local humanoid = character:WaitForChild("Humanoid")

		-- Create WCS character
		local wcsCharacter = WCS.Character.new(character)

		-- Apply Unarmed moveset by default (gives access to Dodge)
		wcsCharacter:ApplyMoveset("Unarmed")

		-- Attach equipment manager (no weapon equipped by default)
		wcsCharacter.EquipmentManager = EquipmentManager.new(wcsCharacter)

		humanoid.Died:Once(function()
			-- Cleanup equipment manager
			if wcsCharacter.EquipmentManager then
				wcsCharacter.EquipmentManager:destroy()
			end

			wcsCharacter:Destroy()
		end)
	end)
end)
