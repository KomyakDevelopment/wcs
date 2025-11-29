--!nonstrict
-- Music Manager (Client) - Singleton
-- Handles music playback with crossfade transitions
-- Only one song plays at a time - calling playMusic fades out current and fades in new
--
-- Usage from any client module:
--   local MusicManager = require(ReplicatedStorage.Client.managers.musicManager)
--   MusicManager.playMusic("rbxassetid://123456")

local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AudioConfig = require(ReplicatedStorage.Shared.config.audioConfig)

-- Configuration from AudioConfig
local DEFAULT_FADE_TIME = AudioConfig.Music.DefaultFadeTime
local DEFAULT_VOLUME = AudioConfig.Music.DefaultVolume
local MUSIC_SOUND_NAME = "MusicManager_Track" -- Unique name for our managed sounds

-- Singleton state (stored as locals to avoid type inference issues)
local _currentSound = nil
local _currentSoundId = nil
local _targetVolume = DEFAULT_VOLUME
local _musicGroup = nil
local _initialized = false
local _isTransitioning = false -- Lock to prevent race conditions
local _musicEnabled = true -- Master toggle for music

-- Singleton module
local MusicManager = {}

-- Initialize (called automatically on first use)
local function ensureInitialized()
	if _initialized then
		return
	end

	-- Create a dedicated sound group for music (keeps it separate from SFX)
	local group = Instance.new("SoundGroup")
	group.Name = "MusicGroup"
	group.Volume = 1
	group.Parent = SoundService
	_musicGroup = group

	-- Clean up any orphaned music sounds from previous sessions
	for _, child in SoundService:GetChildren() do
		if child:IsA("Sound") and child.Name == MUSIC_SOUND_NAME then
			child:Stop()
			child:Destroy()
			print("[MusicManager] Cleaned up orphaned music sound")
		end
	end

	_initialized = true
	print("[MusicManager] Initialized with volume:", _targetVolume)
end

-- Helper: Get a Sound from a path like "Main.LoadingScreen"
function MusicManager.getSoundFromPath(path)
	local musicFolder = ReplicatedStorage:FindFirstChild("Assets")
		and ReplicatedStorage.Assets:FindFirstChild("Music")

	if not musicFolder then
		warn("[MusicManager] Music folder not found at Assets.Music")
		return nil
	end

	-- Split path by dots and traverse
	local current = musicFolder
	for segment in string.gmatch(path, "[^.]+") do
		current = current:FindFirstChild(segment)
		if not current then
			warn("[MusicManager] Path segment not found:", segment, "in path:", path)
			return nil
		end
	end

	if current:IsA("Sound") then
		return current
	else
		warn("[MusicManager] Path does not point to a Sound:", path)
		return nil
	end
end

-- Play a new song (crossfades from current if playing)
-- soundId: The asset ID of the song (e.g., "rbxassetid://123456")
-- fadeTime: Optional fade duration (defaults to DEFAULT_FADE_TIME)
function MusicManager.playMusic(soundId, fadeTime)
	ensureInitialized()

	-- Check if music is enabled
	if not _musicEnabled then
		print("[MusicManager] Music disabled, not playing:", soundId)
		return
	end

	-- Prevent race conditions from multiple rapid calls
	if _isTransitioning then
		print("[MusicManager] Already transitioning, ignoring request for:", soundId)
		return
	end

	local fade = fadeTime or DEFAULT_FADE_TIME

	-- Don't restart if same song is already playing
	if _currentSoundId == soundId and _currentSound and _currentSound.IsPlaying then
		print("[MusicManager] Song already playing:", soundId)
		return
	end

	_isTransitioning = true
	print("[MusicManager] Playing:", soundId)

	-- Stop and cleanup current sound immediately if exists
	local oldSound = _currentSound
	local oldSoundId = _currentSoundId

	-- Create the new sound
	local newSound = Instance.new("Sound")
	newSound.Name = MUSIC_SOUND_NAME
	newSound.SoundId = soundId
	newSound.Volume = 0 -- Start silent for fade in
	newSound.Looped = true
	newSound.SoundGroup = _musicGroup
	newSound.Parent = SoundService

	-- Update current references immediately (before playing)
	_currentSound = newSound
	_currentSoundId = soundId

	-- Start playing the new sound
	newSound:Play()

	-- Create fade in tween
	local fadeInTween = TweenService:Create(
		newSound,
		TweenInfo.new(fade, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Volume = _targetVolume }
	)

	fadeInTween:Play()
	fadeInTween.Completed:Connect(function()
		_isTransitioning = false
	end)

	-- Fade out and cleanup old sound
	if oldSound then
		local fadeOutTween = TweenService:Create(
			oldSound,
			TweenInfo.new(fade, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ Volume = 0 }
		)

		fadeOutTween:Play()
		fadeOutTween.Completed:Connect(function()
			oldSound:Stop()
			oldSound:Destroy()
			print("[MusicManager] Faded out:", oldSoundId)
		end)
	end

	print("[MusicManager] Crossfade started (fade time:", fade, "s)")
end

-- Play music from a config path (e.g., "Main.LoadingScreen")
function MusicManager.playMusicFromPath(path, fadeTime)
	local sound = MusicManager.getSoundFromPath(path)
	if sound then
		MusicManager.playMusic(tostring(sound.SoundId), fadeTime)
	end
end

-- Stop current music with fade out
function MusicManager.stopMusic(fadeTime)
	if not _currentSound then
		return
	end

	local fade = fadeTime or DEFAULT_FADE_TIME
	local soundToStop = _currentSound
	local soundIdStopped = _currentSoundId

	-- Clear references immediately
	_currentSound = nil
	_currentSoundId = nil

	-- Fade out
	local fadeOutTween = TweenService:Create(
		soundToStop,
		TweenInfo.new(fade, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Volume = 0 }
	)

	fadeOutTween:Play()
	fadeOutTween.Completed:Connect(function()
		soundToStop:Stop()
		soundToStop:Destroy()
	end)

	print("[MusicManager] Stopping music:", soundIdStopped)
end

-- Stop all music immediately (no fade)
function MusicManager.stopAllImmediate()
	-- Stop current tracked sound
	if _currentSound then
		_currentSound:Stop()
		_currentSound:Destroy()
		_currentSound = nil
		_currentSoundId = nil
	end

	-- Also clean up any orphaned sounds
	for _, child in SoundService:GetChildren() do
		if child:IsA("Sound") and child.Name == MUSIC_SOUND_NAME then
			child:Stop()
			child:Destroy()
		end
	end

	_isTransitioning = false
	print("[MusicManager] Stopped all music immediately")
end

--============================================================================--
-- VOLUME PREFERENCE (for settings menu)
--============================================================================--

-- Set target volume for music (0-1)
-- This is the main method for the settings slider
-- Affects current playing song and all future songs
function MusicManager.setVolume(volume)
	_targetVolume = math.clamp(volume, 0, 1)

	-- Update current sound if playing
	if _currentSound then
		TweenService:Create(
			_currentSound,
			TweenInfo.new(0.3, Enum.EasingStyle.Quad),
			{ Volume = _targetVolume }
		):Play()
	end

	print("[MusicManager] Volume set to:", _targetVolume)
end

-- Get current volume setting (for settings menu to display)
function MusicManager.getVolume()
	return _targetVolume
end

-- Enable/disable music entirely (master toggle)
function MusicManager.setEnabled(enabled)
	_musicEnabled = enabled

	if not enabled then
		-- Fade out current music
		MusicManager.stopMusic(0.5)
	end

	print("[MusicManager] Music", enabled and "enabled" or "disabled")
end

-- Check if music is enabled
function MusicManager.isEnabled()
	return _musicEnabled
end

--============================================================================--
-- UTILITY
--============================================================================--

-- Check if music is currently playing
function MusicManager.isPlaying()
	return _currentSound ~= nil and _currentSound.IsPlaying
end

-- Get current song ID
function MusicManager.getCurrentSongId()
	return _currentSoundId
end

-- Pause current music (without destroying)
function MusicManager.pause()
	if _currentSound then
		_currentSound:Pause()
		print("[MusicManager] Music paused")
	end
end

-- Resume paused music
function MusicManager.resume()
	if _currentSound then
		_currentSound:Resume()
		print("[MusicManager] Music resumed")
	end
end

return MusicManager
