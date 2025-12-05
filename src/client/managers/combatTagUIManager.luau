--!strict
-- CombatTagUIManager
-- Handles the combat tag UI visibility and countdown display

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer

local CombatTagUIManager = {}
CombatTagUIManager.__index = CombatTagUIManager

export type CombatTagUIManager = typeof(setmetatable({} :: {
	_ctagFrame: Frame?,
	_textLabel: TextLabel?,
	_connection: RBXScriptConnection?,
	_isTagged: boolean,
	_timeRemaining: number,
}, CombatTagUIManager))

function CombatTagUIManager.new(): CombatTagUIManager
	local self = setmetatable({
		_ctagFrame = nil :: Frame?,
		_textLabel = nil :: TextLabel?,
		_connection = nil :: RBXScriptConnection?,
		_isTagged = false,
		_timeRemaining = 0,
	}, CombatTagUIManager)

	self:_setup()

	return self
end

function CombatTagUIManager:_setup()
	-- Find the UI elements
	local playerGui = player:WaitForChild("PlayerGui", 10)
	if not playerGui then
		warn("[CombatTagUIManager] PlayerGui not found")
		return
	end

	local mainGui = playerGui:WaitForChild("Main", 10) :: ScreenGui?
	if not mainGui then
		warn("[CombatTagUIManager] Main ScreenGui not found")
		return
	end

	local ctagFrame = mainGui:FindFirstChild("Ctag") :: Frame?
	if not ctagFrame then
		warn("[CombatTagUIManager] Ctag frame not found in Main")
		return
	end

	local textLabel = ctagFrame:FindFirstChild("TextTemp") :: TextLabel?
	if not textLabel then
		warn("[CombatTagUIManager] TextTemp not found in Ctag")
		return
	end

	self._ctagFrame = ctagFrame
	self._textLabel = textLabel

	-- Start hidden
	ctagFrame.Visible = false

	-- Listen for server updates
	local updateRemote = ReplicatedStorage:WaitForChild("CombatTagUpdate", 10) :: RemoteEvent?
	if updateRemote then
		self._connection = updateRemote.OnClientEvent:Connect(function(isTagged: boolean, timeRemaining: number)
			self:_onTagUpdate(isTagged, timeRemaining)
		end)
	else
		warn("[CombatTagUIManager] CombatTagUpdate remote not found")
	end

	print("[CombatTagUIManager] Initialized")
end

function CombatTagUIManager:_onTagUpdate(isTagged: boolean, timeRemaining: number)
	self._isTagged = isTagged
	self._timeRemaining = timeRemaining

	if self._ctagFrame then
		self._ctagFrame.Visible = isTagged
	end

	if self._textLabel and isTagged then
		self._textLabel.Text = `In combat for {timeRemaining} seconds!`
	end
end

function CombatTagUIManager:destroy()
	if self._connection then
		self._connection:Disconnect()
		self._connection = nil
	end

	if self._ctagFrame then
		self._ctagFrame.Visible = false
	end
end

return CombatTagUIManager
