--!strict
-- Test Dummies Server Script
-- Handles initialization of various test dummies for combat testing

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local WCS = require(ReplicatedStorage.Packages.wcs)

local EquipmentManager = require(ReplicatedStorage.Shared.managers.equipmentManager)

-- Wait for server to be ready
task.wait(1)

print("[TestDummies] Initializing test dummies...")

-- ==================== BLOCKING DUMMY ====================
-- Holds block indefinitely (no parry window after 0.2s)
local blockingDummy = workspace:FindFirstChild("BlockingDummy")
if blockingDummy then
	local blockingDummyWcsChar = WCS.Character.new(blockingDummy)
	blockingDummyWcsChar.EquipmentManager = EquipmentManager.new(blockingDummyWcsChar)

	-- Equip fists (this applies the Unarmed moveset automatically)
	blockingDummyWcsChar.EquipmentManager:equip("fists")

	-- Get and start block skill
	local Block = require(ReplicatedStorage.Shared.skills.block)
	local blockSkill = blockingDummyWcsChar:GetSkillFromConstructor(Block)
	if blockSkill then
		blockSkill:Start()
		print("[TestDummies] ✓ BlockingDummy is now blocking")
	end
end

-- ==================== PARRYING DUMMY ====================
-- Always parries all attacks (permanent Autoparry status)
local parryingDummy = workspace:FindFirstChild("ParryingDummy")
if parryingDummy then
	local parryingDummyWcsChar = WCS.Character.new(parryingDummy)
	parryingDummyWcsChar.EquipmentManager = EquipmentManager.new(parryingDummyWcsChar)

	-- Equip fists (this applies the Unarmed moveset automatically)
	parryingDummyWcsChar.EquipmentManager:equip("fists")

	-- Apply permanent Autoparry status (infinite parry window, no cooldown)
	local Autoparry = require(ReplicatedStorage.Shared.statusEffects.autoparry)
	local autoparryEffect = Autoparry.new(parryingDummyWcsChar)
	if autoparryEffect then
		autoparryEffect:Start(-1) -- Infinite duration
		print("[TestDummies] ✓ ParryingDummy has permanent Autoparry - will parry all attacks")
	end
end

-- ==================== MISS PARRY DUMMY ====================
-- Gets hit, then immediately starts blocking (too late - already took damage)
local missParryDummy = workspace:FindFirstChild("MissParryDummy")
if missParryDummy then
	local missParryDummyWcsChar = WCS.Character.new(missParryDummy)
	missParryDummyWcsChar.EquipmentManager = EquipmentManager.new(missParryDummyWcsChar)

	-- Equip fists (this applies the Unarmed moveset automatically)
	missParryDummyWcsChar.EquipmentManager:equip("fists")

	-- Listen for health changes and apply Blocking status AFTER taking damage
	local humanoid = missParryDummy:FindFirstChild("Humanoid")
	if humanoid then
		humanoid.HealthChanged:Connect(function(_health)
			-- The dummy already took damage, now apply blocking (too late for this hit)
			-- This will block the NEXT hit if it comes soon enough
			local Blocking = require(ReplicatedStorage.Shared.statusEffects.blocking)
			local blockingEffect = Blocking.new(missParryDummyWcsChar)
			if blockingEffect then
				blockingEffect:Start(1.0) -- Block for 1 second after taking damage
				print("[TestDummies] MissParryDummy took damage - now blocking (missed the parry)")

				-- Remove blocking after duration
				task.delay(1.0, function()
					if blockingEffect then
						blockingEffect:End()
					end
				end)
			end
		end)
		print("[TestDummies] ✓ MissParryDummy will block after taking damage (simulates failed parry timing)")
	end
end

-- ==================== DODGING DUMMY ====================
-- Has permanent iframes (simulates continuous dodging)
local dodgingDummy = workspace:FindFirstChild("DodgingDummy")
if dodgingDummy then
	local dodgingDummyWcsChar = WCS.Character.new(dodgingDummy)
	dodgingDummyWcsChar.EquipmentManager = EquipmentManager.new(dodgingDummyWcsChar)

	-- Equip fists (this applies the Unarmed moveset automatically)
	dodgingDummyWcsChar.EquipmentManager:equip("fists")

	-- Apply permanent Iframes (infinite duration)
	-- This makes the dummy invulnerable like during a dodge
	local Iframes = require(ReplicatedStorage.Shared.statusEffects.iframes)
	local iframesEffect = Iframes.new(dodgingDummyWcsChar)
	if iframesEffect then
		iframesEffect:Start(-1) -- Infinite duration
		print("[TestDummies] ✓ DodgingDummy has permanent Iframes - invulnerable to attacks")
	end
end

print("[TestDummies] Test dummies initialization complete")
