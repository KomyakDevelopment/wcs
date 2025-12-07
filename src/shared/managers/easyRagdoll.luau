--!strict
-- EasyRagdoll Module
-- Simple wrapper around the trigger-based ragdoll system
-- Usage: EasyRagdoll.SetRagdoll(character, true, true, 100) -- Enable with trip
-- Usage: EasyRagdoll.SetRagdoll(character, false) -- Disable

local EasyRagdoll = {}

-- Apply trip force to knock character over
local function applyTrip(character: Model, force: number)
	local rootPart = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not rootPart then return end

	-- Random fall direction (horizontal)
	local fallDirection = Vector3.new(
		math.random() - 0.5,
		0,
		math.random() - 0.5
	).Unit

	-- Calculate rotation axis (perpendicular to fall direction, horizontal)
	local rotationAxis = Vector3.new(0, 1, 0):Cross(fallDirection).Unit

	-- DIRECTLY TILT the root CFrame to put them off-balance BEFORE physics kicks in
	local currentCFrame = rootPart.CFrame
	local tiltAngle = math.rad(50) -- 50 degree tilt
	local tiltRotation = CFrame.fromAxisAngle(rotationAxis, tiltAngle)
	rootPart.CFrame = CFrame.new(currentCFrame.Position) * tiltRotation * currentCFrame.Rotation

	-- Wait for physics to initialize
	task.wait()

	-- Scale velocity based on force parameter
	local forceMultiplier = force / 100
	rootPart.AssemblyAngularVelocity = rotationAxis * (5 * forceMultiplier)
	rootPart.AssemblyLinearVelocity = fallDirection * (10 * forceMultiplier) + Vector3.new(0, -5, 0)
end

-- Main API function
-- SetRagdoll(character, enabled, tripEnabled?, tripForce?)
-- character: The character model to ragdoll
-- enabled: true to enable ragdoll, false to disable
-- tripEnabled: (optional) true to apply trip force when enabling, default true
-- tripForce: (optional) force multiplier for trip (100 = normal, 200 = double), default 100
function EasyRagdoll.SetRagdoll(character: Model, enabled: boolean, tripEnabled: boolean?, tripForce: number?)
	if not character then
		warn("[EasyRagdoll] No character provided")
		return
	end

	-- Find the RagdollTrigger created by ragdollSystem.server.luau
	local trigger = character:FindFirstChild("RagdollTrigger") :: BoolValue?

	if not trigger then
		-- Wait briefly for trigger to be created (might be loading)
		trigger = character:WaitForChild("RagdollTrigger", 2) :: BoolValue?
	end

	if not trigger then
		warn("[EasyRagdoll] RagdollTrigger not found on character - ragdoll system not initialized")
		return
	end

	if enabled then
		-- Enable ragdoll via trigger
		trigger.Value = true

		-- Apply trip force if enabled
		local shouldTrip = tripEnabled ~= false -- Default to true
		if shouldTrip then
			local force = tripForce or 100
			applyTrip(character, force)
		end
	else
		-- Disable ragdoll via trigger
		trigger.Value = false
	end
end

-- Check if a character is currently ragdolled
function EasyRagdoll.IsRagdolled(character: Model): boolean
	if not character then
		return false
	end

	local trigger = character:FindFirstChild("RagdollTrigger") :: BoolValue?
	if trigger then
		return trigger.Value
	end

	return false
end

return EasyRagdoll
