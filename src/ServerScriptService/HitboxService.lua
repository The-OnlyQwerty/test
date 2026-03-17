local Players = game:GetService("Players")

local HitboxService = {}
HitboxService.__index = HitboxService

local function getCharacterRoot(character)
	return character and character:FindFirstChild("HumanoidRootPart")
end

local function getHumanoid(character)
	return character and character:FindFirstChildOfClass("Humanoid")
end

local function collectNpcModels()
	local npcs = {}
	local folder = workspace:FindFirstChild("CombatNPCs")
	if not folder then
		return npcs
	end

	for _, child in ipairs(folder:GetChildren()) do
		if child:IsA("Model") and getHumanoid(child) then
			table.insert(npcs, child)
		end
	end

	return npcs
end

function HitboxService.new(remotes)
	local self = setmetatable({}, HitboxService)
	self.Remotes = remotes
	return self
end

function HitboxService:BroadcastDebug(debugInfo)
	if not debugInfo then
		return
	end

	self.Remotes.CombatState:FireAllClients({
		Type = "HitboxDebug",
		CFrame = debugInfo.CFrame,
		Size = debugInfo.Size,
		Color = debugInfo.Color,
		Duration = debugInfo.Duration or 0.15,
		Shape = debugInfo.Shape or "Box",
	})
end

function HitboxService:QueryBox(attacker, cframe, size, debugInfo)
	self:BroadcastDebug(debugInfo or {
		CFrame = cframe,
		Size = size,
	})

	local targets = {}
	local seen = {}
	local overlap = OverlapParams.new()
	overlap.FilterType = Enum.RaycastFilterType.Blacklist
	local filter = {attacker.Character}
	local effectsFolder = workspace:FindFirstChild("CombatEffects")
	if effectsFolder then
		table.insert(filter, effectsFolder)
	end
	overlap.FilterDescendantsInstances = filter

	for _, part in ipairs(workspace:GetPartBoundsInBox(cframe, size, overlap)) do
		local model = part:FindFirstAncestorOfClass("Model")
		local humanoid = model and getHumanoid(model)
		if humanoid and humanoid.Health > 0 and model ~= attacker.Character and not seen[model] then
			seen[model] = true
			table.insert(targets, model)
		end
	end

	return targets
end

function HitboxService:QueryRadius(attacker, position, radius, debugInfo)
	self:BroadcastDebug(debugInfo or {
		CFrame = CFrame.new(position),
		Size = Vector3.new(radius * 2, radius * 2, radius * 2),
		Shape = "Sphere",
	})

	local targets = {}
	local seen = {}

	for _, otherPlayer in ipairs(Players:GetPlayers()) do
		if otherPlayer ~= attacker and otherPlayer.Character then
			local root = getCharacterRoot(otherPlayer.Character)
			local humanoid = getHumanoid(otherPlayer.Character)
			if root and humanoid and humanoid.Health > 0 and (root.Position - position).Magnitude <= radius then
				seen[otherPlayer.Character] = true
				table.insert(targets, otherPlayer.Character)
			end
		end
	end

	for _, npc in ipairs(collectNpcModels()) do
		local root = getCharacterRoot(npc)
		local humanoid = getHumanoid(npc)
		if root and humanoid and humanoid.Health > 0 and not seen[npc] and (root.Position - position).Magnitude <= radius then
			table.insert(targets, npc)
		end
	end

	return targets
end

return HitboxService
