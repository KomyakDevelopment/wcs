--!strict
-- Sprint Skill (Stub)
-- NOTE: Sprint functionality is handled by SprintManager (client manager)
-- This WCS skill exists only for compatibility with other skills that require it
-- DO NOT add input detection or WalkSpeed manipulation here - it conflicts with SprintManager

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local WCS = require(ReplicatedStorage.Packages.wcs)

local Sprint = WCS.RegisterSkill("Sprint")

-- WCS Client Prediction Configuration
Sprint.CheckClientState = false
Sprint.CheckOthersActive = false

function Sprint:OnConstructServer()
	-- No-op: Sprint is managed by client SprintManager
end

function Sprint:OnConstructClient()
	-- No-op: Sprint is managed by client SprintManager
end

function Sprint:OnStartServer()
	-- No-op
end

function Sprint:OnStartClient()
	-- No-op: SprintManager handles sprint activation
end

function Sprint:OnEndServer()
	-- No-op
end

function Sprint:OnEndClient()
	-- No-op: SprintManager handles sprint deactivation
end

return Sprint
