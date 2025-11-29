--!strict
-- Audio Configuration
-- Central location for audio settings and preferences
-- Edit this file to adjust default audio behavior

local AudioConfig = {}

--============================================================================--
-- MUSIC SETTINGS
--============================================================================--
AudioConfig.Music = {
	-- Default volume (0-1, can be changed by player in settings)
	DefaultVolume = 0.5,

	-- Fade durations
	DefaultFadeTime = 1.5, -- Default crossfade duration
	MenuFadeIn = 2.0, -- Fade in for loading screen music
	MenuCrossfade = 2.0, -- Crossfade from loading to background

	-- Music paths (relative to ReplicatedStorage.Assets.Music)
	Tracks = {
		LoadingScreen = "Main.LoadingScreen",
		Background = "Main.Background",
	},
}

--============================================================================--
-- SFX SETTINGS (for future use)
--============================================================================--
AudioConfig.SFX = {
	-- Default volume (0-1)
	DefaultVolume = 1.0,
}

return AudioConfig
