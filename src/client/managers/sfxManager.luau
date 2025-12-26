--!strict
-- SFX Manager (Client) - Singleton
-- Manages sound effect volume through a SoundGroup
-- All SFX should be routed through the SFX SoundGroup for volume control
--
-- Usage from any client module:
--   local SFXManager = require(ReplicatedStorage.Client.managers.sfxManager)
--   SFXManager.setVolume(0.5) -- Set SFX volume to 50%
--   local group = SFXManager.getSoundGroup() -- Get the SoundGroup to assign to sounds

local SoundService = game:GetService("SoundService")

-- Singleton state
local _sfxGroup: SoundGroup? = nil
local _targetVolume = 1.0
local _masterVolume = 1.0
local _initialized = false

local SFXManager = {}

-- Initialize (called automatically on first use)
local function ensureInitialized()
	if _initialized then
		return
	end

	-- Create a dedicated sound group for SFX
	local group = Instance.new("SoundGroup")
	group.Name = "SFXGroup"
	group.Volume = _targetVolume * _masterVolume
	group.Parent = SoundService
	_sfxGroup = group

	_initialized = true
	print("[SFXManager] Initialized with volume:", _targetVolume)
end

-- Get the SFX SoundGroup (for assigning to sounds)
function SFXManager.getSoundGroup(): SoundGroup
	ensureInitialized()
	return _sfxGroup :: SoundGroup
end

-- Set SFX volume (0-1)
-- This is the main method for the settings slider
function SFXManager.setVolume(volume: number)
	ensureInitialized()
	_targetVolume = math.clamp(volume, 0, 1)

	-- Update sound group
	if _sfxGroup then
		_sfxGroup.Volume = _targetVolume * _masterVolume
	end

	print("[SFXManager] Volume set to:", _targetVolume, "effective:", _targetVolume * _masterVolume)
end

-- Set master volume multiplier (0-1)
-- Called when master volume changes
function SFXManager.setMasterVolume(volume: number)
	ensureInitialized()
	_masterVolume = math.clamp(volume, 0, 1)

	-- Update sound group with combined volume
	if _sfxGroup then
		_sfxGroup.Volume = _targetVolume * _masterVolume
	end

	print("[SFXManager] Master volume set to:", _masterVolume, "effective:", _targetVolume * _masterVolume)
end

-- Get current SFX volume setting (for settings menu to display)
function SFXManager.getVolume(): number
	return _targetVolume
end

-- Get effective volume (sfx * master)
function SFXManager.getEffectiveVolume(): number
	return _targetVolume * _masterVolume
end

return SFXManager
