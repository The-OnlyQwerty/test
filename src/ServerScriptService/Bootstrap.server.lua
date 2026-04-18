local Lighting = game:GetService("Lighting")
local InsertService = game:GetService("InsertService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local sharedFolder = ReplicatedStorage:FindFirstChild("Shared") or Instance.new("Folder")
sharedFolder.Name = "Shared"
sharedFolder.Parent = ReplicatedStorage

local remotesFolder = ReplicatedStorage:FindFirstChild("Remotes") or Instance.new("Folder")
remotesFolder.Name = "Remotes"
remotesFolder.Parent = ReplicatedStorage

local combatRequest = remotesFolder:FindFirstChild("CombatRequest") or Instance.new("RemoteEvent")
combatRequest.Name = "CombatRequest"
combatRequest.Parent = remotesFolder

local combatState = remotesFolder:FindFirstChild("CombatState") or Instance.new("RemoteEvent")
combatState.Name = "CombatState"
combatState.Parent = remotesFolder

local hudAssetResolver = remotesFolder:FindFirstChild("HudAssetResolver") or Instance.new("RemoteFunction")
hudAssetResolver.Name = "HudAssetResolver"
hudAssetResolver.Parent = remotesFolder

local Constants = require(sharedFolder:WaitForChild("Constants"))
local CombatService = require(script.Parent:WaitForChild("CombatService"))

local service = CombatService.new({
	CombatRequest = combatRequest,
	CombatState = combatState,
})

local resolvedHudAssetCache = {}

local function normalizeContentId(contentId)
	if typeof(contentId) ~= "string" or contentId == "" then
		return nil
	end

	local numericId = string.match(contentId, "%d+")
	if numericId then
		return "rbxassetid://" .. numericId
	end

	return contentId
end

local function extractImageContent(instance)
	for _, descendant in ipairs(instance:GetDescendants()) do
		if descendant:IsA("Decal") or descendant:IsA("Texture") then
			local normalized = normalizeContentId(descendant.Texture)
			if normalized then
				return normalized
			end
		elseif descendant:IsA("ImageLabel") or descendant:IsA("ImageButton") then
			local normalized = normalizeContentId(descendant.Image)
			if normalized then
				return normalized
			end
		end
	end

	return nil
end

local function resolveHudAssetImage(assetId)
	if resolvedHudAssetCache[assetId] ~= nil then
		return resolvedHudAssetCache[assetId]
	end

	local resolvedImage = nil
	local ok, container = pcall(function()
		return InsertService:LoadAsset(assetId)
	end)
	if ok and container then
		resolvedImage = extractImageContent(container)
		container:Destroy()
	end

	resolvedHudAssetCache[assetId] = resolvedImage
	return resolvedImage
end

hudAssetResolver.OnServerInvoke = function(_, action, payload)
	if action ~= "ResolveUiAssetTextures" or typeof(payload) ~= "table" then
		return {}
	end

	local resolved = {}
	for key, assetId in pairs(payload) do
		local numericId = typeof(assetId) == "number" and assetId or tonumber(string.match(tostring(assetId), "%d+"))
		if numericId then
			resolved[key] = resolveHudAssetImage(numericId)
		end
	end

	return resolved
end

local DUMMY_RESPAWN_TIME = 3
local DUEL_ARENA_CENTER = Vector3.new(0, 320, 6000)
local DUEL_ARENA_SCALE = 6
local MAIN_MAP_CENTER = Vector3.new(0, 0, -8)
local MAIN_MAP_SIZE = 1400

local function ensureArenaPart(folder, name, size, cframe, color, transparency)
	local part = folder:FindFirstChild(name) or Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.CanCollide = true
	part.Material = Enum.Material.SmoothPlastic
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Color = color
	part.Transparency = transparency or 0
	part.Size = size
	part.CFrame = cframe
	part.Parent = folder
	return part
end

local function ensureLighting()
	Lighting.Ambient = Color3.fromRGB(106, 118, 92)
	Lighting.OutdoorAmbient = Color3.fromRGB(132, 146, 116)
	Lighting.Brightness = 2.2
	Lighting.ClockTime = 14.6
	Lighting.FogColor = Color3.fromRGB(176, 214, 160)
	Lighting.FogStart = 260
	Lighting.FogEnd = 1800

	local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere") or Instance.new("Atmosphere")
	atmosphere.Density = 0.23
	atmosphere.Offset = 0.08
	atmosphere.Color = Color3.fromRGB(189, 223, 176)
	atmosphere.Decay = Color3.fromRGB(108, 136, 102)
	atmosphere.Glare = 0.1
	atmosphere.Haze = 0.8
	atmosphere.Parent = Lighting

	local bloom = Lighting:FindFirstChildOfClass("BloomEffect") or Instance.new("BloomEffect")
	bloom.Intensity = 0.2
	bloom.Size = 18
	bloom.Threshold = 1.3
	bloom.Parent = Lighting

	local colorCorrection = Lighting:FindFirstChildOfClass("ColorCorrectionEffect") or Instance.new("ColorCorrectionEffect")
	colorCorrection.Brightness = 0.02
	colorCorrection.Contrast = 0.04
	colorCorrection.Saturation = 0.02
	colorCorrection.TintColor = Color3.fromRGB(238, 245, 232)
	colorCorrection.Parent = Lighting
end

local function ensureMainMap()
	local folder = workspace:FindFirstChild("MainMap") or Instance.new("Folder")
	folder.Name = "MainMap"
	folder.Parent = workspace

	local halfMap = MAIN_MAP_SIZE * 0.5
	local barrierOffset = halfMap - 3
	local hillOffset = MAIN_MAP_SIZE * 0.33
	local edgeTreeOffset = MAIN_MAP_SIZE * 0.4

	local ground = ensureArenaPart(
		folder,
		"Ground",
		Vector3.new(MAIN_MAP_SIZE, 2, MAIN_MAP_SIZE),
		CFrame.new(MAIN_MAP_CENTER),
		Color3.fromRGB(88, 126, 72)
	)
	ground.Material = Enum.Material.Grass

	local clearing = ensureArenaPart(
		folder,
		"CenterClearing",
		Vector3.new(320, 1, 320),
		CFrame.new(MAIN_MAP_CENTER + Vector3.new(0, 1.52, 0)),
		Color3.fromRGB(136, 119, 88)
	)
	clearing.Material = Enum.Material.Ground

	local spawnPlatform = ensureArenaPart(
		folder,
		"SpawnPlatform",
		Vector3.new(58, 2, 58),
		CFrame.new(MAIN_MAP_CENTER + Vector3.new(0, 2.2, 72)),
		Color3.fromRGB(142, 132, 102)
	)
	spawnPlatform.Material = Enum.Material.Rock

	local spawnTrim = ensureArenaPart(
		folder,
		"SpawnTrim",
		Vector3.new(44, 1, 44),
		CFrame.new(MAIN_MAP_CENTER + Vector3.new(0, 3.25, 72)),
		Color3.fromRGB(206, 230, 186)
	)
	spawnTrim.Material = Enum.Material.Grass

	local wallData = {
		{"NorthBarrier", Vector3.new(MAIN_MAP_SIZE, 26, 6), MAIN_MAP_CENTER + Vector3.new(0, 13, -barrierOffset)},
		{"SouthBarrier", Vector3.new(MAIN_MAP_SIZE, 26, 6), MAIN_MAP_CENTER + Vector3.new(0, 13, barrierOffset)},
		{"EastBarrier", Vector3.new(6, 26, MAIN_MAP_SIZE), MAIN_MAP_CENTER + Vector3.new(barrierOffset, 13, 0)},
		{"WestBarrier", Vector3.new(6, 26, MAIN_MAP_SIZE), MAIN_MAP_CENTER + Vector3.new(-barrierOffset, 13, 0)},
	}

	for _, wallInfo in ipairs(wallData) do
		local wall = ensureArenaPart(folder, wallInfo[1], wallInfo[2], CFrame.new(wallInfo[3]), Color3.fromRGB(88, 112, 80), 0.4)
		wall.Material = Enum.Material.Grass
	end

	local hillData = {
		{"HillNorthWest", Vector3.new(180, 64, 180), MAIN_MAP_CENTER + Vector3.new(-hillOffset, 28, -hillOffset)},
		{"HillNorthEast", Vector3.new(160, 58, 160), MAIN_MAP_CENTER + Vector3.new(hillOffset, 25, -hillOffset + 24)},
		{"HillSouthWest", Vector3.new(188, 62, 188), MAIN_MAP_CENTER + Vector3.new(-hillOffset - 24, 27, hillOffset)},
		{"HillSouthEast", Vector3.new(170, 56, 170), MAIN_MAP_CENTER + Vector3.new(hillOffset, 24, hillOffset + 18)},
	}

	for _, hillInfo in ipairs(hillData) do
		local hill = ensureArenaPart(
			folder,
			hillInfo[1],
			hillInfo[2],
			CFrame.new(hillInfo[3]),
			Color3.fromRGB(92, 132, 76)
		)
		hill.Material = Enum.Material.Grass
		hill.Shape = Enum.PartType.Ball
	end

	local rockData = {
		{"RockA", Vector3.new(-220, 5, -96), Vector3.new(30, 18, 24), 18},
		{"RockB", Vector3.new(260, 4, -140), Vector3.new(24, 16, 20), -22},
		{"RockC", Vector3.new(-280, 4, 110), Vector3.new(36, 20, 28), 11},
		{"RockD", Vector3.new(300, 4, 150), Vector3.new(28, 18, 22), -15},
		{"RockE", Vector3.new(76, 4, -260), Vector3.new(34, 20, 24), 9},
		{"RockF", Vector3.new(-88, 4, 276), Vector3.new(26, 16, 22), -9},
	}

	for _, rockInfo in ipairs(rockData) do
		local rock = ensureArenaPart(
			folder,
			rockInfo[1],
			rockInfo[3],
			CFrame.new(MAIN_MAP_CENTER + rockInfo[2]) * CFrame.Angles(0, math.rad(rockInfo[4]), math.rad(rockInfo[4] * 0.35)),
			Color3.fromRGB(114, 108, 100)
		)
		rock.Material = Enum.Material.Slate
		rock.Shape = Enum.PartType.Ball
	end

	local treeData = {
		{Vector3.new(-edgeTreeOffset, 6, -220), 28, 42},
		{Vector3.new(-edgeTreeOffset - 42, 6, 34), 24, 38},
		{Vector3.new(-edgeTreeOffset + 20, 6, 246), 30, 44},
		{Vector3.new(edgeTreeOffset, 6, -242), 26, 40},
		{Vector3.new(edgeTreeOffset + 36, 6, -12), 28, 44},
		{Vector3.new(edgeTreeOffset - 10, 6, 230), 24, 38},
		{Vector3.new(-140, 6, -edgeTreeOffset), 22, 34},
		{Vector3.new(170, 6, -edgeTreeOffset - 24), 26, 40},
		{Vector3.new(-126, 6, edgeTreeOffset), 24, 38},
		{Vector3.new(152, 6, edgeTreeOffset + 18), 28, 42},
		{Vector3.new(-300, 6, -310), 30, 46},
		{Vector3.new(320, 6, -280), 26, 40},
		{Vector3.new(-316, 6, 304), 28, 42},
		{Vector3.new(306, 6, 320), 30, 46},
	}

	for index, treeInfo in ipairs(treeData) do
		local trunk = ensureArenaPart(
			folder,
			("TreeTrunk%d"):format(index),
			Vector3.new(4, treeInfo[2], 4),
			CFrame.new(MAIN_MAP_CENTER + treeInfo[1] + Vector3.new(0, treeInfo[2] * 0.5, 0)),
			Color3.fromRGB(104, 72, 44)
		)
		trunk.Material = Enum.Material.Wood

		local leaves = ensureArenaPart(
			folder,
			("TreeLeaves%d"):format(index),
			Vector3.new(treeInfo[3], treeInfo[3], treeInfo[3]),
			CFrame.new(MAIN_MAP_CENTER + treeInfo[1] + Vector3.new(0, treeInfo[2] + treeInfo[3] * 0.35, 0)),
			Color3.fromRGB(76, 124, 62),
			0.08
		)
		leaves.Material = Enum.Material.Grass
		leaves.Shape = Enum.PartType.Ball
	end

	local path = ensureArenaPart(
		folder,
		"SpawnPath",
		Vector3.new(20, 1, 84),
		CFrame.new(MAIN_MAP_CENTER + Vector3.new(0, 2.75, 38)),
		Color3.fromRGB(136, 119, 88)
	)
	path.Material = Enum.Material.Ground

	local leaderboardBase = ensureArenaPart(
		folder,
		"RankedLeaderboardBase",
		Vector3.new(34, 2, 10),
		CFrame.new(MAIN_MAP_CENTER + Vector3.new(120, 6, 84)),
		Color3.fromRGB(126, 112, 86)
	)
	leaderboardBase.Material = Enum.Material.WoodPlanks

	local leaderboardBoard = ensureArenaPart(
		folder,
		"RankedLeaderboard",
		Vector3.new(30, 18, 1),
		CFrame.new(MAIN_MAP_CENTER + Vector3.new(120, 16, 79)),
		Color3.fromRGB(42, 28, 24)
	)
	leaderboardBoard.Material = Enum.Material.Slate
	leaderboardBoard.Name = "RankedLeaderboard"

	local leftPost = ensureArenaPart(
		folder,
		"RankedLeaderboardPostLeft",
		Vector3.new(2, 12, 2),
		CFrame.new(MAIN_MAP_CENTER + Vector3.new(108, 8, 83)),
		Color3.fromRGB(96, 74, 52)
	)
	leftPost.Material = Enum.Material.Wood

	local rightPost = ensureArenaPart(
		folder,
		"RankedLeaderboardPostRight",
		Vector3.new(2, 12, 2),
		CFrame.new(MAIN_MAP_CENTER + Vector3.new(132, 8, 83)),
		Color3.fromRGB(96, 74, 52)
	)
	rightPost.Material = Enum.Material.Wood

	return folder
end

local function ensureDuelArena()
	local folder = workspace:FindFirstChild("DuelArena") or Instance.new("Folder")
	folder.Name = "DuelArena"
	folder.Parent = workspace

	local arenaWidth = 110 * DUEL_ARENA_SCALE
	local arenaHeight = 30 * DUEL_ARENA_SCALE
	local halfArena = arenaWidth * 0.5
	local wallOffset = halfArena - 1
	local wallHeightOffset = arenaHeight * 0.5 - 1
	local ceilingHeight = arenaHeight - 1

	ensureArenaPart(
		folder,
		"Floor",
		Vector3.new(arenaWidth, 2, arenaWidth),
		CFrame.new(DUEL_ARENA_CENTER),
		Color3.fromRGB(48, 22, 24)
	)
	ensureArenaPart(
		folder,
		"NorthWall",
		Vector3.new(arenaWidth, arenaHeight, 2),
		CFrame.new(DUEL_ARENA_CENTER + Vector3.new(0, wallHeightOffset, -wallOffset)),
		Color3.fromRGB(82, 24, 24),
		0.1
	)
	ensureArenaPart(
		folder,
		"SouthWall",
		Vector3.new(arenaWidth, arenaHeight, 2),
		CFrame.new(DUEL_ARENA_CENTER + Vector3.new(0, wallHeightOffset, wallOffset)),
		Color3.fromRGB(82, 24, 24),
		0.1
	)
	ensureArenaPart(
		folder,
		"EastWall",
		Vector3.new(2, arenaHeight, arenaWidth),
		CFrame.new(DUEL_ARENA_CENTER + Vector3.new(wallOffset, wallHeightOffset, 0)),
		Color3.fromRGB(82, 24, 24),
		0.1
	)
	ensureArenaPart(
		folder,
		"WestWall",
		Vector3.new(2, arenaHeight, arenaWidth),
		CFrame.new(DUEL_ARENA_CENTER + Vector3.new(-wallOffset, wallHeightOffset, 0)),
		Color3.fromRGB(82, 24, 24),
		0.1
	)
	ensureArenaPart(
		folder,
		"Ceiling",
		Vector3.new(arenaWidth, 2, arenaWidth),
		CFrame.new(DUEL_ARENA_CENTER + Vector3.new(0, ceilingHeight, 0)),
		Color3.fromRGB(38, 16, 18),
		0.6
	)

	return folder
end

local function ensureDuelSpawns()
	local folder = workspace:FindFirstChild("DuelSpawns") or Instance.new("Folder")
	folder.Name = "DuelSpawns"
	folder.Parent = workspace

	local function ensureSpawn(name, position, lookAt)
		local spawn = folder:FindFirstChild(name) or Instance.new("Part")
		spawn.Name = name
		spawn.Anchored = true
		spawn.CanCollide = false
		spawn.Transparency = 1
		spawn.Size = Vector3.new(6, 1, 6)
		spawn.CFrame = CFrame.lookAt(position, lookAt)
		spawn.Parent = folder
		return spawn
	end

	ensureSpawn("SpawnA", DUEL_ARENA_CENTER + Vector3.new(-108, 4, 0), DUEL_ARENA_CENTER + Vector3.new(108, 4, 0))
	ensureSpawn("SpawnB", DUEL_ARENA_CENTER + Vector3.new(108, 4, 0), DUEL_ARENA_CENTER + Vector3.new(-108, 4, 0))
end

local function styleDummyRig(dummy)
	local bodyColors = dummy:FindFirstChildOfClass("BodyColors") or Instance.new("BodyColors")
	bodyColors.HeadColor3 = Color3.fromRGB(200, 200, 200)
	bodyColors.TorsoColor3 = Color3.fromRGB(145, 145, 145)
	bodyColors.LeftArmColor3 = Color3.fromRGB(125, 125, 125)
	bodyColors.RightArmColor3 = Color3.fromRGB(125, 125, 125)
	bodyColors.LeftLegColor3 = Color3.fromRGB(100, 100, 100)
	bodyColors.RightLegColor3 = Color3.fromRGB(100, 100, 100)
	bodyColors.Parent = dummy

	for _, descendant in ipairs(dummy:GetDescendants()) do
		if descendant:IsA("BasePart") then
			descendant.Material = Enum.Material.SmoothPlastic
			descendant.TopSurface = Enum.SurfaceType.Smooth
			descendant.BottomSurface = Enum.SurfaceType.Smooth
			if descendant.Name == "HumanoidRootPart" then
				descendant.Transparency = 1
				descendant.CanCollide = false
			end
		end
	end
end

local function createDummy(folder, config)
	local existing = folder:FindFirstChild(config.Name)
	if existing then
		if existing:GetAttribute("DummyRigVersion") == 2 then
			return existing
		end
		existing:Destroy()
	end

	local description = Instance.new("HumanoidDescription")
	local dummy = Players:CreateHumanoidModelFromDescription(description, Enum.HumanoidRigType.R6)
	dummy.Name = config.Name
	dummy.Parent = folder

	local humanoid = dummy:FindFirstChildOfClass("Humanoid") or Instance.new("Humanoid")
	humanoid.MaxHealth = config.Health
	humanoid.Health = config.Health
	humanoid.WalkSpeed = 0
	humanoid.AutoRotate = false
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	humanoid.Parent = dummy
	local animate = dummy:FindFirstChild("Animate")
	if animate then
		animate:Destroy()
	end
	if not humanoid:FindFirstChildOfClass("Animator") then
		Instance.new("Animator", humanoid)
	end

	local root = dummy:FindFirstChild("HumanoidRootPart")
	if root then
		dummy:PivotTo(CFrame.new(config.Position))
	end
	styleDummyRig(dummy)

	dummy.PrimaryPart = root
	dummy:SetAttribute("IsTargetDummy", true)
	dummy:SetAttribute("DisplayName", config.DisplayName)
	dummy:SetAttribute("Blocking", config.Blocking or false)
	dummy:SetAttribute("DummyBehavior", config.Behavior or "Idle")
	dummy:SetAttribute("DummyDamage", config.Damage or 0)
	dummy:SetAttribute("DummyKnockback", config.Knockback or 0)
	dummy:SetAttribute("DummyStun", config.Stun or 0)
	dummy:SetAttribute("DummyReactiveKnockback", config.ReactiveKnockback or 0)
	dummy:SetAttribute("DummyReactiveLaunch", config.ReactiveLaunch == true)
	dummy:SetAttribute("DummyReactiveStun", config.ReactiveStun or 0)
	dummy:SetAttribute("Stunned", false)
	dummy:SetAttribute("Respawning", false)
	dummy:SetAttribute("DummyRigVersion", 3)

	return dummy
end

local DUMMY_CONFIGS = {
	{
		Name = "TargetDummy",
		DisplayName = "Target Dummy",
		Health = 400,
		Position = Vector3.new(0, 4, -18),
	},
	{
		Name = "BlockDummy",
		DisplayName = "Blocking Dummy",
		Health = 400,
		Position = Vector3.new(8, 4, -18),
		Blocking = true,
		Behavior = "Blocking",
	},
	{
		Name = "AttackDummy",
		DisplayName = "Attacking Dummy",
		Health = 400,
		Position = Vector3.new(-8, 4, -18),
		Behavior = "Attacking",
		Damage = 12,
		Knockback = 18,
		Stun = Constants.M1_STUN_TIME,
	},
	{
		Name = "PerfectBlockDummy",
		DisplayName = "Perfect Block Dummy",
		Health = 400,
		Position = Vector3.new(16, 4, -18),
		Blocking = true,
		Behavior = "PerfectBlocking",
	},
	{
		Name = "KnockbackDummy",
		DisplayName = "Knockback Dummy",
		Health = 400,
		Position = Vector3.new(24, 4, -18),
		Behavior = "KnockbackOnHit",
		ReactiveKnockback = 46,
		ReactiveLaunch = true,
	},
}

local function attachDummyRespawn(folder, config, dummy)
	local humanoid = dummy:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end

	humanoid.Died:Connect(function()
		if dummy:GetAttribute("Respawning") then
			return
		end

		dummy:SetAttribute("Respawning", true)
		task.delay(DUMMY_RESPAWN_TIME, function()
			if dummy.Parent then
				dummy:Destroy()
			end
			createDummy(folder, config)
			local replacement = folder:FindFirstChild(config.Name)
			if replacement then
				attachDummyRespawn(folder, config, replacement)
			end
		end)
	end)
end

local function ensureDummies()
	local folder = workspace:FindFirstChild("CombatNPCs") or Instance.new("Folder")
	folder.Name = "CombatNPCs"
	folder.Parent = workspace

	for _, config in ipairs(DUMMY_CONFIGS) do
		local dummy = createDummy(folder, config)
		attachDummyRespawn(folder, config, dummy)
	end

	return folder
end

local function runAttackDummy(folder)
	task.spawn(function()
		while true do
			task.wait(1.5)

			local dummy = folder:FindFirstChild("AttackDummy")
			if not dummy then
				continue
			end

			local humanoid = dummy:FindFirstChildOfClass("Humanoid")
			local root = dummy:FindFirstChild("HumanoidRootPart")
			if not humanoid or humanoid.Health <= 0 or not root then
				continue
			end

			local hitboxCFrame = root.CFrame * CFrame.new(0, 1.5, -4)
			local hitboxSize = Vector3.new(7, 6, 7)
			service.Hitboxes:BroadcastDebug({
				CFrame = hitboxCFrame,
				Size = hitboxSize,
				Color = Color3.fromRGB(255, 120, 120),
				Duration = 0.22,
			})

			local overlap = OverlapParams.new()
			overlap.FilterType = Enum.RaycastFilterType.Blacklist
			overlap.FilterDescendantsInstances = {dummy, workspace:FindFirstChild("CombatEffects")}

			local seen = {}
			for _, part in ipairs(workspace:GetPartBoundsInBox(hitboxCFrame, hitboxSize, overlap)) do
				local model = part:FindFirstAncestorOfClass("Model")
				local targetHumanoid = model and model:FindFirstChildOfClass("Humanoid")
				if model and model ~= dummy and targetHumanoid and targetHumanoid.Health > 0 and not seen[model] then
					seen[model] = true
					local targetPlayer = Players:GetPlayerFromCharacter(model)
					if targetPlayer and service.GetKit and Constants.SANS_DODGE_DEBUG then
						local targetKit = service:GetKit(targetPlayer)
						if targetKit and targetKit.DisplayName == "Sans" then
							service:SendDodgeDebug(targetPlayer, "DUMMY HIT DETECTED")
						end
					end
					service:DamageTarget(dummy, model, dummy:GetAttribute("DummyDamage") or 12, dummy:GetAttribute("DummyKnockback") or 0, dummy:GetAttribute("DummyStun") or 0, {
						AllowTrainingDamage = true,
						NoKR = true,
						HitType = "M1Melee",
					})
				end
			end
		end
	end)
end

local dummyFolder = ensureDummies()
ensureLighting()
ensureMainMap()
ensureDuelArena()
ensureDuelSpawns()
service:Init()
runAttackDummy(dummyFolder)
