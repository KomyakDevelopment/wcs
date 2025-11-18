local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local WCS = require(ReplicatedStorage.Packages.wcs)

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
