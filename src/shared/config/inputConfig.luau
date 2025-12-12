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
	CriticalAttack = {
		InputType = Enum.UserInputType.Keyboard,
		KeyCode = Enum.KeyCode.R,
		Description = "Critical attack (R)",
	},
}

-- Movement Actions
InputConfig.Movement = {
	Sprint = {
		InputType = Enum.UserInputType.Keyboard,
		KeyCode = Enum.KeyCode.LeftShift,
		Description = "Sprint",
	},
	Slide = {
		InputType = Enum.UserInputType.Keyboard,
		KeyCode = Enum.KeyCode.LeftControl,
		Description = "Slide",
	},
}

-- Ability Hotkeys (removed - hotbar handles 1-9, 0 internally)
InputConfig.Abilities = {}

-- Equipment Actions (reserved for future use)
InputConfig.Equipment = {}

-- Interaction Actions (for knocked players)
InputConfig.Interaction = {
	Grip = {
		InputType = Enum.UserInputType.Keyboard,
		KeyCode = Enum.KeyCode.B,
		Description = "Grip/Execute knocked player",
	},
	Carry = {
		InputType = Enum.UserInputType.Keyboard,
		KeyCode = Enum.KeyCode.V,
		Description = "Carry knocked player",
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
