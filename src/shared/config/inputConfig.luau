--!strict
-- Input configuration for all player actions
-- This file defines the keybinds for all game actions

local InputConfig = {}

-- Combat Actions
InputConfig.Combat = {
	PrimaryAttack = {
		InputType = Enum.UserInputType.MouseButton1,
		KeyCode = nil, -- Not using KeyCode for mouse buttons
		Description = "Primary attack (M1)",
	},
	SecondaryAttack = {
		InputType = Enum.UserInputType.MouseButton2,
		KeyCode = nil,
		Description = "Secondary attack (M2)",
	},
	Block = {
		InputType = Enum.UserInputType.Keyboard,
		KeyCode = Enum.KeyCode.F,
		Description = "Block incoming attacks",
	},
	Dodge = {
		InputType = Enum.UserInputType.Keyboard,
		KeyCode = Enum.KeyCode.Q,
		Description = "Dodge roll",
	},
}

-- Movement Actions
InputConfig.Movement = {
	Sprint = {
		InputType = Enum.UserInputType.Keyboard,
		KeyCode = Enum.KeyCode.LeftShift,
		Description = "Sprint",
	},
}

-- Ability Hotkeys (Skills 1-4)
InputConfig.Abilities = {
	Ability1 = {
		InputType = Enum.UserInputType.Keyboard,
		KeyCode = Enum.KeyCode.One,
		Description = "Ability slot 1",
	},
	Ability2 = {
		InputType = Enum.UserInputType.Keyboard,
		KeyCode = Enum.KeyCode.Two,
		Description = "Ability slot 2",
	},
	Ability3 = {
		InputType = Enum.UserInputType.Keyboard,
		KeyCode = Enum.KeyCode.Three,
		Description = "Ability slot 3",
	},
	Ability4 = {
		InputType = Enum.UserInputType.Keyboard,
		KeyCode = Enum.KeyCode.Four,
		Description = "Ability slot 4",
	},
}

-- UI Actions
InputConfig.UI = {
	ToggleInventory = {
		InputType = Enum.UserInputType.Keyboard,
		KeyCode = Enum.KeyCode.I,
		Description = "Toggle inventory",
	},
	ToggleCharacterSheet = {
		InputType = Enum.UserInputType.Keyboard,
		KeyCode = Enum.KeyCode.C,
		Description = "Toggle character sheet",
	},
	ToggleMap = {
		InputType = Enum.UserInputType.Keyboard,
		KeyCode = Enum.KeyCode.M,
		Description = "Toggle map",
	},
}

return InputConfig
