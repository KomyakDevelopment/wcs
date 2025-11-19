local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local WCS = require(ReplicatedStorage.Packages.wcs)

local StunIndicatorManager = require(ReplicatedStorage.Shared.managers.stunIndicatorManager)

local Server = WCS.CreateServer()

Server:RegisterDirectory(ReplicatedStorage.Shared.movesets)
Server:RegisterDirectory(ReplicatedStorage.Shared.skills)
Server:RegisterDirectory(ReplicatedStorage.Shared.statusEffects)

Server:Start()

-- Initialize stun indicator manager (server-side)
local stunIndicatorManager = StunIndicatorManager.new()

-- NOW create the dummy after server has started
local dummy = workspace:WaitForChild("Dummy")
local wcsChar = WCS.Character.new(dummy)
wcsChar:ApplyMoveset("Unarmed")

Players.PlayerAdded:Connect(function(player)
	player.CharacterAdded:Connect(function(character)
		local humanoid = character:WaitForChild("Humanoid")

		local wcsCharacter = WCS.Character.new(character)
		wcsCharacter:ApplyMoveset("Unarmed")

		humanoid.Died:Once(function()
			wcsCharacter:Destroy()
		end)
	end)
end)
