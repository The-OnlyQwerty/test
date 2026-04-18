local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local MemoryStoreService = game:GetService("MemoryStoreService")
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Debris = game:GetService("Debris")
local TeleportService = game:GetService("TeleportService")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared:WaitForChild("Constants"))
local CharacterKits = require(Shared:WaitForChild("CharacterKits"))
local SkinCatalog = require(Shared:WaitForChild("SkinCatalog"))

local EffectService = require(script.Parent:WaitForChild("EffectService"))
local HitboxService = require(script.Parent:WaitForChild("HitboxService"))

local CombatService = {}
CombatService.__index = CombatService

local profileStore = DataStoreService:GetDataStore("JudgementDividedProfiles_v1")
local ratingLeaderboardStore = DataStoreService:GetOrderedDataStore("JudgementDividedRankedLeaderboard_v1")
local rankedQueueStore = MemoryStoreService:GetSortedMap("JudgementDividedRankedQueue_v1")
local rankedAssignmentStore = MemoryStoreService:GetSortedMap("JudgementDividedRankedAssignments_v1")
local rankedLockStore = MemoryStoreService:GetSortedMap("JudgementDividedRankedLock_v1")

local FATAL_ERROR_BLUE = Color3.fromRGB(48, 170, 255)
local FATAL_ERROR_RED = Color3.fromRGB(255, 72, 72)
local FATAL_ERROR_WHITE = Color3.fromRGB(245, 245, 255)
local DEFAULT_SANS_PALETTE = {
	Beam = Color3.fromRGB(120, 205, 255),
	Block = Color3.fromRGB(145, 205, 255),
	Bone = Color3.fromRGB(100, 175, 255),
	BoneBright = Color3.fromRGB(210, 240, 255),
	BonePale = Color3.fromRGB(180, 205, 255),
	White = Color3.fromRGB(245, 245, 255),
	Zone = Color3.fromRGB(200, 210, 255),
	ZoneBright = Color3.fromRGB(140, 180, 255),
	Counter = Color3.fromRGB(255, 70, 70),
}
local FATAL_ERROR_SANS_PALETTE = {
	Beam = FATAL_ERROR_BLUE,
	Block = FATAL_ERROR_BLUE,
	Bone = FATAL_ERROR_BLUE,
	BoneBright = FATAL_ERROR_WHITE,
	BonePale = FATAL_ERROR_WHITE,
	White = FATAL_ERROR_WHITE,
	Zone = FATAL_ERROR_RED,
	ZoneBright = FATAL_ERROR_BLUE,
	Counter = FATAL_ERROR_RED,
}
local BLACK_SILENCE_MASK_NAME = "BlackSilenceMask"
local BLACK_SILENCE_PHASE_ATTRIBUTE = "BlackSilencePhase"
local THEME_SOUND_ATTRIBUTE = "ThemeSoundId"

local function now()
	return os.clock()
end

local function getCharacterRoot(character)
	return character and character:FindFirstChild("HumanoidRootPart")
end

local function getHumanoid(character)
	return character and character:FindFirstChildOfClass("Humanoid")
end

local function shouldPreserveAirMomentum(humanoid, root)
	if not humanoid or not root then
		return false
	end

	if humanoid.FloorMaterial == Enum.Material.Air then
		return true
	end

	local state = humanoid:GetState()
	if state == Enum.HumanoidStateType.Jumping
		or state == Enum.HumanoidStateType.Freefall
		or state == Enum.HumanoidStateType.FallingDown
	then
		return true
	end

	return math.abs(root.AssemblyLinearVelocity.Y) > 1.5
end

local function forceCharacterStand(character)
	local humanoid = getHumanoid(character)
	if not humanoid then
		return false
	end

	local seatPart = humanoid.SeatPart
	local wasSeated = humanoid.Sit or seatPart ~= nil

	if humanoid.Sit then
		humanoid.Sit = false
	end
	humanoid.Jump = false
	humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)

	local seatWeld = character:FindFirstChild("SeatWeld", true)
	if seatWeld then
		seatWeld:Destroy()
	end

	if seatPart then
		local seatPartWeld = seatPart:FindFirstChild("SeatWeld")
		if seatPartWeld then
			seatPartWeld:Destroy()
		end
	end

	return wasSeated
end

local function playActionAnimation(character, animationId, options)
	options = options or {}
	local humanoid = getHumanoid(character)
	if not humanoid or not animationId or animationId == 0 then
		return nil
	end

	local animator = humanoid:FindFirstChildOfClass("Animator") or Instance.new("Animator", humanoid)
	local animation = Instance.new("Animation")
	animation.AnimationId = "rbxassetid://" .. tostring(animationId)

	local track = animator:LoadAnimation(animation)
	track.Priority = options.Priority or Enum.AnimationPriority.Action
	track.Looped = options.Looped == true
	if options.Speed then
		track:AdjustSpeed(options.Speed)
	end
	track:Play(options.FadeTime or 0.05)
	track.Stopped:Connect(function()
		track:Destroy()
		animation:Destroy()
	end)
	return track
end

local function createActionTrack(character, animationId, options)
	options = options or {}
	local humanoid = getHumanoid(character)
	if not humanoid or not animationId or animationId == 0 then
		return nil, nil
	end

	local animator = humanoid:FindFirstChildOfClass("Animator") or Instance.new("Animator", humanoid)
	local animation = Instance.new("Animation")
	animation.AnimationId = "rbxassetid://" .. tostring(animationId)

	local track = animator:LoadAnimation(animation)
	track.Priority = options.Priority or Enum.AnimationPriority.Action
	track.Looped = options.Looped == true
	if options.Speed then
		track:AdjustSpeed(options.Speed)
	end

	return track, animation
end

local function getTargetCharacter(target)
	if typeof(target) ~= "Instance" then
		return nil
	end
	if target:IsA("Player") then
		return target.Character
	end
	if target:IsA("Model") then
		return target
	end
	return nil
end

local function getTargetPlayer(target)
	if typeof(target) ~= "Instance" then
		return nil
	end
	if target:IsA("Player") then
		return target
	end
	if target:IsA("Model") then
		return Players:GetPlayerFromCharacter(target)
	end
	return nil
end

local function getQuoteAdorneePart(character)
	if not character then
		return nil
	end

	return character:FindFirstChild("Head") or getCharacterRoot(character)
end

local function getTelekinesisTargetKey(target)
	local targetPlayer = getTargetPlayer(target)
	if targetPlayer then
		return "player:" .. tostring(targetPlayer.UserId)
	end

	local character = getTargetCharacter(target)
	if character then
		return "model:" .. character.Name
	end

	return nil
end

local function getNpcFolder()
	local folder = workspace:FindFirstChild("CombatNPCs")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "CombatNPCs"
		folder.Parent = workspace
	end
	return folder
end

local function getDuelSpawnFolder()
	return workspace:FindFirstChild("DuelSpawns")
end

local function setCharacterAttribute(player, name, value)
	if player.Character then
		player.Character:SetAttribute(name, value)
	end
end

local function clampVector(vector, maxMagnitude)
	if vector.Magnitude > maxMagnitude then
		return vector.Unit * maxMagnitude
	end
	return vector
end

local function appendUniqueTarget(targetsByCharacter, target)
	local character = getTargetCharacter(target)
	if character and not targetsByCharacter[character] then
		targetsByCharacter[character] = target
	end
end

local function isAdminUserId(userId)
	for _, adminId in ipairs(Constants.ADMIN_USER_IDS) do
		if adminId == userId then
			return true
		end
	end
	return false
end

local function isTrainingPlaceId(placeId)
	for _, trainingPlaceId in ipairs(Constants.TRAINING_SERVER_PLACE_IDS) do
		if trainingPlaceId == placeId then
			return true
		end
	end
	return false
end

local function isRankedQueuePlaceId(placeId)
	return Constants.RANKED_QUEUE_PLACE_ID ~= 0 and placeId == Constants.RANKED_QUEUE_PLACE_ID
end

local function getTesterGroupId()
	if Constants.TESTER_GROUP_ID and Constants.TESTER_GROUP_ID ~= 0 then
		return Constants.TESTER_GROUP_ID
	end

	if game.CreatorType == Enum.CreatorType.Group then
		return game.CreatorId
	end

	return 0
end

local function makeUrl(baseUrl, path)
	if string.sub(baseUrl, -1) == "/" then
		baseUrl = string.sub(baseUrl, 1, -2)
	end
	return baseUrl .. path
end

local function normalizeLookupText(text)
	if type(text) ~= "string" then
		return ""
	end

	return string.lower((text:gsub("[%W_]+", "")))
end

function CombatService.new(remotes)
	local self = setmetatable({}, CombatService)
	self.Remotes = remotes
	self.PlayerState = {}
	self.PlayerProfiles = {}
	self.NaoyaFrameMarks = {}
	self.SamuraiBleedMarks = {}
	self.ActiveSamuraiBleeds = {}
	self.CharacterAppearanceCache = {}
	self.PendingDuelRequests = {}
	self.ActiveDuels = {}
	self.RankedQueue = {}
	self.RankedMatchData = nil
	self.GlobalMusicOverride = nil
	self.BridgeStatus = "unknown"
	self.LeaderboardNameCache = {}
	self.ActiveKnockbackAnimations = {}
	self.Effects = EffectService.new()
	self.Hitboxes = HitboxService.new(remotes)
	return self
end

function CombatService:IsTrainingServer()
	return workspace:GetAttribute(Constants.TRAINING_SERVER_ATTRIBUTE) == true or isTrainingPlaceId(game.PlaceId)
end

function CombatService:IsRankedQueueServer()
	return isRankedQueuePlaceId(game.PlaceId)
end

function CombatService:IsRankedMatchServer()
	return self.RankedMatchData ~= nil
end

function CombatService:GetServerRole()
	if self:IsTrainingServer() then
		return "training"
	end

	return "main"
end

function CombatService:IsBridgeConfigured()
	return Constants.BRIDGE_BASE_URL ~= "" and Constants.BRIDGE_SHARED_SECRET ~= ""
end

function CombatService:RequestBridge(method, path, body)
	if not self:IsBridgeConfigured() then
		return false, "bridge not configured"
	end

	local success, response = pcall(function()
		return HttpService:RequestAsync({
			Url = makeUrl(Constants.BRIDGE_BASE_URL, path),
			Method = method,
			Headers = {
				["Content-Type"] = "application/json",
				["x-bridge-secret"] = Constants.BRIDGE_SHARED_SECRET,
			},
			Body = body and HttpService:JSONEncode(body) or nil,
		})
	end)

	if not success then
		return false, tostring(response)
	end

	if not response.Success then
		local statusCode = tostring(response.StatusCode or "?")
		local statusMessage = tostring(response.StatusMessage or "request failed")
		return false, string.format("%s (%s)", statusMessage, statusCode)
	end

	if response.Body and response.Body ~= "" then
		local ok, decoded = pcall(function()
			return HttpService:JSONDecode(response.Body)
		end)
		if ok then
			return true, decoded
		end
	end

	return true, {}
end

function CombatService:BuildBridgePresence()
	local players = {}
	for _, player in ipairs(Players:GetPlayers()) do
		table.insert(players, {
			userId = player.UserId,
			name = player.Name,
			displayName = player.DisplayName,
		})
	end

	return {
		jobId = game.JobId,
		placeId = game.PlaceId,
		role = self:GetServerRole(),
		players = players,
		updatedAt = os.time(),
	}
end

function CombatService:SetBridgeStatus(status, detail)
	if self.BridgeStatus == status then
		return
	end

	self.BridgeStatus = status
	local message
	if status == "connected" then
		message = "Discord bridge connected."
	elseif status == "error" then
		message = "Discord bridge polling failed."
		if type(detail) == "string" and detail ~= "" then
			message ..= " " .. string.sub(detail, 1, 120)
		end
	elseif status == "disabled" then
		message = "Discord bridge is not configured."
	end

	if message then
		self.Remotes.CombatState:FireAllClients({
			Type = "SystemMessage",
			Text = message,
		})
	end
end

function CombatService:Init()
	Players.CharacterAutoLoads = false

	Players.PlayerAdded:Connect(function(player)
		self:OnPlayerAdded(player)
	end)

	Players.PlayerRemoving:Connect(function(player)
		self:HandleRankedLeavePenalty(player)
		self:SaveProfile(player)
		self:CleanupDuelState(player)
		self.PlayerState[player] = nil
		self.PlayerProfiles[player] = nil
	end)

	for _, player in ipairs(Players:GetPlayers()) do
		self:OnPlayerAdded(player)
	end

	self.Remotes.CombatRequest.OnServerEvent:Connect(function(player, payload)
		self:HandleRequest(player, payload)
	end)

	task.spawn(function()
		self:RunResourceRegen()
	end)

	task.spawn(function()
		self:RunBridgeLoop()
	end)

	task.spawn(function()
		self:RunBridgeHeartbeatLoop()
	end)

	task.spawn(function()
		self:RunRatingLeaderboardLoop()
	end)

	task.spawn(function()
		while true do
			task.wait(Constants.RANKED_MATCHMAKING_INTERVAL)
			self:TryStartRankedMatch()
		end
	end)

	task.spawn(function()
		while true do
			task.wait(Constants.RANKED_ASSIGNMENT_POLL_INTERVAL)
			self:CheckRankedAssignments()
			self:TryStartPendingRankedMatch()
		end
	end)
end

function CombatService:GetDefaultState()
	return {
		KitId = "Sans",
		LastM1At = 0,
		ComboStep = 0,
		M1CooldownUntil = 0,
		RankedQueueKey = nil,
		Cooldowns = {},
		AbilityBurstCounts = {},
		AbilityHoldStates = {},
		AbilityCastToken = 0,
		CastLockUntil = 0,
		IsBlocking = false,
		IsStunnedUntil = 0,
		LastDashAt = 0,
		Mode = "Bones",
		CounterUntil = 0,
		IFrameUntil = 0,
		ActiveBlasters = 0,
		BlasterEffects = {},
		PendingBlasterShots = 0,
		PendingBlasterTargetKey = nil,
		HeldTargetUserId = nil,
		PendingTeleTargetKey = nil,
		TelekinesisAttemptId = 0,
		TelekinesisMarker = nil,
		IsRunning = false,
		LastBlockEndedAt = 0,
		PerfectBlockUntil = 0,
		BlockAura = nil,
		Buffs = {},
		CombatTagId = 0,
		CombatSessionId = 0,
		NaoyaEngageQuoteSessionId = 0,
		BlackSilencePhase = 0,
		BlackSilenceFinalIntroPlayed = false,
	}
end

local SANS_BLASTER_SLOT_OFFSETS = {
	Vector3.new(3.35, 2.85, 0.1),
	Vector3.new(1.4, 3.05, 2.7),
	Vector3.new(-3.35, 2.85, 0.1),
	Vector3.new(-1.4, 3.05, 2.7),
}

function CombatService:CleanupActiveBlasterList(state)
	if not state then
		return {}
	end

	state.BlasterEffects = state.BlasterEffects or {}
	local kept = {}
	for _, blaster in ipairs(state.BlasterEffects) do
		if typeof(blaster) == "Instance" and blaster.Parent then
			table.insert(kept, blaster)
		end
	end

	table.clear(state.BlasterEffects)
	for _, blaster in ipairs(kept) do
		table.insert(state.BlasterEffects, blaster)
	end

	state.ActiveBlasters = #state.BlasterEffects
	return state.BlasterEffects
end

function CombatService:GetSansPersistentBlasterOffset(slotIndex)
	return SANS_BLASTER_SLOT_OFFSETS[slotIndex] or Vector3.new(
		((slotIndex % 2 == 0) and -1.6 or 1.6),
		3,
		2.9 + (math.floor((slotIndex - 1) / 2) * 0.75)
	)
end

function CombatService:GetOpenSansBlasterSlot(state, maxCount)
	self:CleanupActiveBlasterList(state)
	local occupied = {}
	for _, blaster in ipairs(state.BlasterEffects or {}) do
		local slotIndex = blaster:GetAttribute("BlasterSlotIndex")
		if typeof(slotIndex) == "number" then
			occupied[slotIndex] = true
		end
	end

	for slotIndex = 1, maxCount do
		if not occupied[slotIndex] then
			return slotIndex
		end
	end

	return maxCount
end

function CombatService:DestroyActiveBlasters(player, state)
	state = state or self:GetState(player)
	if not state then
		return
	end

	self:CleanupActiveBlasterList(state)
	for _, blaster in ipairs(state.BlasterEffects) do
		self.Effects:DestroyPersistentBlaster(blaster)
	end

	table.clear(state.BlasterEffects)
	state.ActiveBlasters = 0
	state.PendingBlasterShots = 0
	state.PendingBlasterTargetKey = nil

	if player then
		setCharacterAttribute(player, "ActiveBlasters", 0)
		setCharacterAttribute(player, "PendingBlasterShots", 0)
	end
end

function CombatService:ConsumeActiveBlasters(player, state, count)
	state = state or self:GetState(player)
	if not state then
		return 0
	end

	self:CleanupActiveBlasterList(state)
	table.sort(state.BlasterEffects, function(a, b)
		local aSlot = a:GetAttribute("BlasterSlotIndex") or 0
		local bSlot = b:GetAttribute("BlasterSlotIndex") or 0
		return aSlot < bSlot
	end)
	local consumed = 0
	for _ = 1, count do
		local blaster = table.remove(state.BlasterEffects, 1)
		if not blaster then
			break
		end
		self.Effects:DestroyPersistentBlaster(blaster)
		consumed += 1
	end

	state.ActiveBlasters = #state.BlasterEffects
	if player then
		setCharacterAttribute(player, "ActiveBlasters", state.ActiveBlasters)
	end

	return consumed
end

function CombatService:ResetTelekinesisState(state)
	if not state then
		return
	end

	if state.TelekinesisMarker then
		self.Effects:DestroyTelekinesisMarker(state.TelekinesisMarker)
		state.TelekinesisMarker = nil
	end

	state.HeldTargetUserId = nil
	state.PendingTeleTargetKey = nil
	state.TelekinesisAttemptId = (state.TelekinesisAttemptId or 0) + 1
end

function CombatService:FindTelekinesisTargetByKey(player, targetKey)
	if not targetKey then
		return nil
	end

	for _, target in ipairs(self:GetAllPotentialTargets(player)) do
		if getTelekinesisTargetKey(target) == targetKey then
			return target
		end
	end

	return nil
end

function CombatService:TryEscapeTelekinesis(player)
	local targetKey = getTelekinesisTargetKey(player)
	if not targetKey then
		return false
	end

	for sourcePlayer, sourceState in pairs(self.PlayerState) do
		if sourceState.PendingTeleTargetKey == targetKey then
			sourceState.PendingTeleTargetKey = nil
			sourceState.TelekinesisAttemptId = (sourceState.TelekinesisAttemptId or 0) + 1
			return true
		end
	end

	return false
end

function CombatService:MarkInCombat(target)
	local targetPlayer = getTargetPlayer(target)
	local character = getTargetCharacter(target)
	if not targetPlayer or not character then
		return
	end

	local state = self:GetState(targetPlayer)
	if not state then
		return
	end

	local enteringCombat = character:GetAttribute("InCombat") ~= true
	if enteringCombat then
		state.CombatSessionId = (state.CombatSessionId or 0) + 1
	end

	state.CombatTagId += 1
	local tagId = state.CombatTagId
	character:SetAttribute("InCombat", true)

	task.delay(Constants.COMBAT_IDLE_TIMEOUT, function()
		if not self.PlayerState[targetPlayer] or not targetPlayer.Character then
			return
		end
		if self.PlayerState[targetPlayer].CombatTagId ~= tagId then
			return
		end
		targetPlayer.Character:SetAttribute("InCombat", false)
	end)
end

function CombatService:GetDefaultProfile()
	return {
		Kills = 0,
		Deaths = 0,
		RankedRating = Constants.RANKED_START_RATING,
		RankedWins = 0,
		RankedLosses = 0,
		SelectedSkins = {
			Sans = "Default",
			Magnus = "Default",
			Samurai = "Default",
		},
	}
end

function CombatService:GetSkinDefinition(kitId, skinId)
	local skins = SkinCatalog[kitId]
	if not skins then
		return nil
	end

	for _, skin in ipairs(skins) do
		if skin.Id == skinId then
			return skin
		end
	end

	return nil
end

function CombatService:NormalizeSelectedSkins(profile)
	if not profile then
		return false
	end

	local changed = false
	for kitId, skins in pairs(SkinCatalog) do
		local selectedSkinId = profile.SelectedSkins[kitId]
		if not self:GetSkinDefinition(kitId, selectedSkinId) then
			local fallbackSkin = skins[1]
			profile.SelectedSkins[kitId] = fallbackSkin and fallbackSkin.Id or "Default"
			changed = true
		end
	end

	return changed
end

function CombatService:CaptureCharacterAppearance(character)
	if not character then
		return nil
	end

	local cached = self.CharacterAppearanceCache[character]
	if cached then
		return cached
	end

	local snapshot = {
		Parts = {},
	}

	for _, descendant in ipairs(character:GetDescendants()) do
		if descendant:IsA("BasePart") and descendant.Name ~= "HumanoidRootPart" then
			snapshot.Parts[descendant] = {
				Color = descendant.Color,
				Material = descendant.Material,
			}
		end
	end

	self.CharacterAppearanceCache[character] = snapshot
	return snapshot
end

function CombatService:RestoreCharacterAppearance(character)
	if not character then
		return
	end

	local snapshot = self.CharacterAppearanceCache[character]
	if snapshot then
		for part, values in pairs(snapshot.Parts) do
			if part and part.Parent then
				part.Color = values.Color
				part.Material = values.Material
			end
		end
	end

	local highlight = character:FindFirstChild("FatalErrorSkinHighlight")
	if highlight then
		highlight:Destroy()
	end

	self:RemoveBlackSilenceMask(character)
end

function CombatService:GetFatalErrorVisuals(part, root)
	local name = string.lower(part.Name)
	if name == "head" or string.find(name, "torso", 1, true) then
		return FATAL_ERROR_WHITE, Enum.Material.SmoothPlastic
	end

	if string.find(name, "left", 1, true) then
		return FATAL_ERROR_RED, Enum.Material.Neon
	end

	if string.find(name, "right", 1, true) then
		return FATAL_ERROR_BLUE, Enum.Material.Neon
	end

	if root then
		local relative = root.CFrame:PointToObjectSpace(part.Position)
		if relative.X < -0.25 then
			return FATAL_ERROR_RED, Enum.Material.Neon
		elseif relative.X > 0.25 then
			return FATAL_ERROR_BLUE, Enum.Material.Neon
		end
	end

	return FATAL_ERROR_WHITE, Enum.Material.SmoothPlastic
end

function CombatService:GetSelectedSkinId(player, kitId)
	local profile = self:GetProfile(player)
	if not profile then
		return "Default"
	end

	return profile.SelectedSkins[kitId] or "Default"
end

function CombatService:IsBlackSilenceSkinEquipped(player)
	local state = self:GetState(player)
	return state and state.KitId == "Magnus" and self:GetSelectedSkinId(player, "Magnus") == "BlackSilence"
end

function CombatService:GetBlackSilencePhaseForHealth(health)
	local numericHealth = tonumber(health) or 0
	if numericHealth <= (Constants.BLACK_SILENCE_PHASE_THREE_HEALTH or 88) then
		return 3
	end
	if numericHealth <= (Constants.BLACK_SILENCE_PHASE_TWO_HEALTH or 144) then
		return 2
	end
	return 1
end

function CombatService:GetBlackSilenceThemeSoundId(phase)
	local skinThemes = (((Constants.SKIN_THEME_IDS or {}).Magnus or {}).BlackSilence or {})
	if phase == 3 then
		return tonumber(skinThemes.Phase3) or 0
	elseif phase == 2 then
		return tonumber(skinThemes.Phase2) or 0
	end
	return tonumber(skinThemes.Phase1) or 0
end

function CombatService:RemoveBlackSilenceMask(character)
	if not character then
		return
	end

	local existingMask = character:FindFirstChild(BLACK_SILENCE_MASK_NAME)
	if existingMask then
		existingMask:Destroy()
	end

	local accent = character:FindFirstChild("MaskAccent")
	if accent then
		accent:Destroy()
	end
end

function CombatService:ApplyBlackSilenceMask(character)
	if not character then
		return
	end

	local head = character:FindFirstChild("Head")
	if not head then
		return
	end

	self:RemoveBlackSilenceMask(character)

	local mask = Instance.new("Part")
	mask.Name = BLACK_SILENCE_MASK_NAME
	mask.Size = Vector3.new(1.15, 0.95, 0.16)
	mask.Color = Color3.fromRGB(10, 10, 12)
	mask.Material = Enum.Material.SmoothPlastic
	mask.CanCollide = false
	mask.CanQuery = false
	mask.CanTouch = false
	mask.Massless = true
	mask.Locked = true
	mask.CastShadow = false
	mask.Parent = character
	mask.CFrame = head.CFrame * CFrame.new(0, -0.02, -0.53)

	local weld = Instance.new("WeldConstraint")
	weld.Part0 = head
	weld.Part1 = mask
	weld.Parent = mask

	local accent = Instance.new("Part")
	accent.Name = "MaskAccent"
	accent.Size = Vector3.new(0.72, 0.1, 0.04)
	accent.Color = Color3.fromRGB(215, 215, 220)
	accent.Material = Enum.Material.Neon
	accent.CanCollide = false
	accent.CanQuery = false
	accent.CanTouch = false
	accent.Massless = true
	accent.Locked = true
	accent.CastShadow = false
	accent.Parent = character
	accent.CFrame = head.CFrame * CFrame.new(0, 0.08, -0.62)

	local accentWeld = Instance.new("WeldConstraint")
	accentWeld.Part0 = head
	accentWeld.Part1 = accent
	accentWeld.Parent = accent
end

function CombatService:TriggerBlackSilenceFinalPhase(player, character, humanoid)
	local state = self:GetState(player)
	local root = getCharacterRoot(character)
	if not state or not character or not humanoid or not root or state.BlackSilenceFinalIntroPlayed then
		return
	end

	state.BlackSilenceFinalIntroPlayed = true
	state.IFrameUntil = math.max(state.IFrameUntil or 0, now() + (Constants.BLACK_SILENCE_FINAL_PHASE_IFRAME_TIME or 1.35))
	state.CastLockUntil = math.max(state.CastLockUntil or 0, now() + (Constants.BLACK_SILENCE_FINAL_PHASE_LOCK_TIME or 1.1))
	self:SetBlocking(player, false)
	self:RefreshMovementState(player)
	playActionAnimation(character, Constants.BLACK_SILENCE_FINAL_PHASE_ANIMATION_ID or 0)

	local retreatVelocity = Instance.new("BodyVelocity")
	retreatVelocity.Name = "BlackSilenceRetreat"
	retreatVelocity.MaxForce = Vector3.new(1, 1, 1) * (Constants.KNOCKBACK_FORCE or 70000)
	retreatVelocity.Velocity = (-root.CFrame.LookVector * (Constants.BLACK_SILENCE_FINAL_PHASE_DASH_SPEED or 52)) + Vector3.new(0, 6, 0)
	retreatVelocity.Parent = root
	Debris:AddItem(retreatVelocity, 0.18)

	self.Effects:SpawnSlash(root.CFrame * CFrame.new(0, 1.45, 2.2), Vector3.new(2.4, 3.6, 5.4), Color3.fromRGB(18, 18, 20), 0.18)
	task.delay(0.42, function()
		if player.Character ~= character or humanoid.Health <= 0 then
			return
		end
		self:ApplyBlackSilenceMask(character)
	end)

	task.delay(Constants.BLACK_SILENCE_FINAL_PHASE_LOCK_TIME or 1.1, function()
		if self.PlayerState[player] and player.Character == character then
			self:RefreshMovementState(player)
		end
	end)
end

function CombatService:UpdateBlackSilencePhaseState(player, character, humanoid)
	local state = self:GetState(player)
	if not state or not character or not humanoid then
		return
	end

	if not self:IsBlackSilenceSkinEquipped(player) then
		character:SetAttribute(BLACK_SILENCE_PHASE_ATTRIBUTE, 0)
		character:SetAttribute(THEME_SOUND_ATTRIBUTE, 0)
		self:RemoveBlackSilenceMask(character)
		state.BlackSilencePhase = 0
		state.BlackSilenceFinalIntroPlayed = false
		return
	end

	local phase = state.BlackSilenceFinalIntroPlayed and 3 or self:GetBlackSilencePhaseForHealth(humanoid.Health)
	character:SetAttribute(BLACK_SILENCE_PHASE_ATTRIBUTE, phase)
	character:SetAttribute(THEME_SOUND_ATTRIBUTE, self:GetBlackSilenceThemeSoundId(phase))

	if phase == 3 then
		if not state.BlackSilenceFinalIntroPlayed then
			self:TriggerBlackSilenceFinalPhase(player, character, humanoid)
			phase = 3
		else
			self:ApplyBlackSilenceMask(character)
		end
	else
		self:RemoveBlackSilenceMask(character)
	end

	state.BlackSilencePhase = phase
	character:SetAttribute(BLACK_SILENCE_PHASE_ATTRIBUTE, phase)
	character:SetAttribute(THEME_SOUND_ATTRIBUTE, self:GetBlackSilenceThemeSoundId(phase))
end

function CombatService:ApplySelectedSkinAppearance(player, character)
	local state = self:GetState(player)
	local profile = self:GetProfile(player)
	if not character or not state or not profile then
		return
	end

	self:CaptureCharacterAppearance(character)
	self:RestoreCharacterAppearance(character)

	local selectedSkinId = profile.SelectedSkins[state.KitId] or "Default"
	character:SetAttribute("SelectedSkin", selectedSkinId)
	character:SetAttribute(THEME_SOUND_ATTRIBUTE, 0)
	character:SetAttribute(BLACK_SILENCE_PHASE_ATTRIBUTE, 0)

	if state.KitId == "Magnus" and selectedSkinId == "BlackSilence" then
		local humanoid = getHumanoid(character)
		if humanoid then
			self:UpdateBlackSilencePhaseState(player, character, humanoid)
		end
		return
	end

	if state.KitId ~= "Sans" or selectedSkinId ~= "FatalError" then
		return
	end

	local root = getCharacterRoot(character)
	for _, descendant in ipairs(character:GetDescendants()) do
		if descendant:IsA("BasePart") and descendant.Name ~= "HumanoidRootPart" then
			local color, material = self:GetFatalErrorVisuals(descendant, root)
			descendant.Color = color
			descendant.Material = material
		end
	end

	local highlight = Instance.new("Highlight")
	highlight.Name = "FatalErrorSkinHighlight"
	highlight.DepthMode = Enum.HighlightDepthMode.Occluded
	highlight.FillColor = FATAL_ERROR_BLUE
	highlight.FillTransparency = 0.82
	highlight.OutlineColor = FATAL_ERROR_RED
	highlight.OutlineTransparency = 0.12
	highlight.Parent = character
end

function CombatService:GetSansEffectPalette(player)
	local state = self:GetState(player)
	local profile = self:GetProfile(player)
	if state and profile and state.KitId == "Sans" and profile.SelectedSkins.Sans == "FatalError" then
		return FATAL_ERROR_SANS_PALETTE
	end

	return DEFAULT_SANS_PALETTE
end

function CombatService:GetSansBlasterTemplateNames(player)
	local state = self:GetState(player)
	local profile = self:GetProfile(player)
	if state and profile and state.KitId == "Sans" and profile.SelectedSkins.Sans == "FatalError" then
		return {
			"Fatal Gaster Blaster",
			"FatalGasterBlaster",
		}
	end

	return nil
end

function CombatService:LoadProfile(player)
	local success, data = pcall(function()
		return profileStore:GetAsync(tostring(player.UserId))
	end)

	local profile = self:GetDefaultProfile()
	if success and type(data) == "table" then
		profile.Kills = tonumber(data.Kills) or 0
		profile.Deaths = tonumber(data.Deaths) or 0
		profile.RankedRating = tonumber(data.RankedRating) or Constants.RANKED_START_RATING
		profile.RankedWins = tonumber(data.RankedWins) or 0
		profile.RankedLosses = tonumber(data.RankedLosses) or 0
		if type(data.SelectedSkins) == "table" then
			for kitId, skinId in pairs(data.SelectedSkins) do
				profile.SelectedSkins[kitId] = skinId
			end
		end
	end

	self:NormalizeSelectedSkins(profile)
	if not self:HasTesterAccess(player) then
		for kitId, skins in pairs(SkinCatalog) do
			local selectedSkin = self:GetSkinDefinition(kitId, profile.SelectedSkins[kitId])
			if selectedSkin and selectedSkin.RequiresTester then
				local fallbackSkin = skins[1]
				profile.SelectedSkins[kitId] = fallbackSkin and fallbackSkin.Id or "Default"
			end
		end
	end

	self.PlayerProfiles[player] = profile
end

function CombatService:SaveProfile(player)
	local profile = self.PlayerProfiles[player]
	if not profile then
		return
	end

	pcall(function()
		profileStore:SetAsync(tostring(player.UserId), {
			Kills = profile.Kills,
			Deaths = profile.Deaths,
			RankedRating = profile.RankedRating,
			RankedWins = profile.RankedWins,
			RankedLosses = profile.RankedLosses,
			SelectedSkins = profile.SelectedSkins,
		})
	end)

	pcall(function()
		ratingLeaderboardStore:SetAsync(tostring(player.UserId), math.max(0, math.floor(profile.RankedRating or Constants.RANKED_START_RATING)))
	end)

	task.defer(function()
		self:RefreshRatingLeaderboardBoard()
	end)
end

function CombatService:GetProfile(player)
	return self.PlayerProfiles[player]
end

function CombatService:EnsureLeaderstats(player)
	local leaderstats = player:FindFirstChild("leaderstats")
	if not leaderstats then
		leaderstats = Instance.new("Folder")
		leaderstats.Name = "leaderstats"
		leaderstats.Parent = player
	end

	local function ensureValue(name, className)
		local valueObject = leaderstats:FindFirstChild(name)
		if not valueObject then
			valueObject = Instance.new(className)
			valueObject.Name = name
			valueObject.Parent = leaderstats
		end
		return valueObject
	end

	ensureValue("Kills", "IntValue")
	ensureValue("Deaths", "IntValue")
	ensureValue("KDR", "NumberValue")
	ensureValue("Rating", "IntValue")
end

function CombatService:UpdateLeaderstats(player)
	local profile = self:GetProfile(player)
	local leaderstats = player and player:FindFirstChild("leaderstats")
	if not profile or not leaderstats then
		return
	end

	local kills = leaderstats:FindFirstChild("Kills")
	local deaths = leaderstats:FindFirstChild("Deaths")
	local kdr = leaderstats:FindFirstChild("KDR")
	local rating = leaderstats:FindFirstChild("Rating")

	if kills then
		kills.Value = profile.Kills or 0
	end
	if deaths then
		deaths.Value = profile.Deaths or 0
	end
	if kdr then
		kdr.Value = self:GetKDR(player)
	end
	if rating then
		rating.Value = profile.RankedRating or Constants.RANKED_START_RATING
	end
end

function CombatService:IsSkinUnlocked(player, kitId, skinId)
	local profile = self:GetProfile(player)
	local skin = self:GetSkinDefinition(kitId, skinId)
	if not profile or not skin then
		return false
	end

	if skin.RequiresTester and not self:HasTesterAccess(player) then
		return false
	end

	return profile.Kills >= (skin.UnlockKills or 0)
end

function CombatService:SetSelectedSkin(player, kitId, skinId)
	local profile = self:GetProfile(player)
	if not profile or not self:IsSkinUnlocked(player, kitId, skinId) then
		return false
	end

	profile.SelectedSkins[kitId] = skinId
	local state = self:GetState(player)
	if state and state.KitId == kitId and player.Character then
		self:ApplySelectedSkinAppearance(player, player.Character)
	end
	self:SaveProfile(player)
	self:SendProfile(player)
	return true
end

function CombatService:SendProfile(player)
	local profile = self:GetProfile(player)
	if not profile then
		return
	end

	self:NormalizeSelectedSkins(profile)

	self:UpdateLeaderstats(player)

	self.Remotes.CombatState:FireClient(player, {
		Type = "Profile",
		Kills = profile.Kills,
		Deaths = profile.Deaths,
		KDR = self:GetKDR(player),
		RankedRating = profile.RankedRating,
		RankedWins = profile.RankedWins,
		RankedLosses = profile.RankedLosses,
		SelectedSkins = profile.SelectedSkins,
	})
end

function CombatService:GetLeaderboardBoard()
	local mainMap = workspace:FindFirstChild("MainMap")
	return mainMap and mainMap:FindFirstChild("RankedLeaderboard")
end

function CombatService:GetCachedNameForUserId(userId)
	if self.LeaderboardNameCache[userId] then
		return self.LeaderboardNameCache[userId]
	end

	local ok, name = pcall(function()
		return Players:GetNameFromUserIdAsync(userId)
	end)

	if ok and type(name) == "string" and name ~= "" then
		self.LeaderboardNameCache[userId] = name
		return name
	end

	return "Unknown"
end

function CombatService:RefreshRatingLeaderboardBoard()
	local board = self:GetLeaderboardBoard()
	if not board then
		return
	end

	local ok, pages = pcall(function()
		return ratingLeaderboardStore:GetSortedAsync(false, 10)
	end)
	if not ok or not pages then
		return
	end

	local entries = pages:GetCurrentPage()
	if #entries > 10 then
		while #entries > 10 do
			table.remove(entries)
		end
	end
	local surfaceGui = board:FindFirstChild("LeaderboardGui")
	if not surfaceGui then
		surfaceGui = Instance.new("SurfaceGui")
		surfaceGui.Name = "LeaderboardGui"
		surfaceGui.Face = Enum.NormalId.Front
		surfaceGui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		surfaceGui.PixelsPerStud = 18
		surfaceGui.Parent = board
	end
	surfaceGui.AlwaysOnTop = false

	local root = surfaceGui:FindFirstChild("Root")
	if not root then
		root = Instance.new("Frame")
		root.Name = "Root"
		root.Size = UDim2.fromScale(1, 1)
		root.BackgroundColor3 = Color3.fromRGB(24, 18, 20)
		root.BorderSizePixel = 0
		root.Parent = surfaceGui

		local rootCorner = Instance.new("UICorner")
		rootCorner.CornerRadius = UDim.new(0, 14)
		rootCorner.Parent = root

		local topBand = Instance.new("Frame")
		topBand.Name = "TopBand"
		topBand.BackgroundColor3 = Color3.fromRGB(72, 24, 20)
		topBand.BorderSizePixel = 0
		topBand.Size = UDim2.new(1, 0, 0, 58)
		topBand.Parent = root

		local topBandCorner = Instance.new("UICorner")
		topBandCorner.CornerRadius = UDim.new(0, 14)
		topBandCorner.Parent = topBand

		local topMask = Instance.new("Frame")
		topMask.BackgroundColor3 = Color3.fromRGB(72, 24, 20)
		topMask.BorderSizePixel = 0
		topMask.Position = UDim2.new(0, 0, 0, 28)
		topMask.Size = UDim2.new(1, 0, 0, 30)
		topMask.Parent = topBand

		local divider = Instance.new("Frame")
		divider.Name = "Divider"
		divider.BackgroundColor3 = Color3.fromRGB(223, 195, 133)
		divider.BackgroundTransparency = 0.2
		divider.BorderSizePixel = 0
		divider.Position = UDim2.new(0, 14, 0, 68)
		divider.Size = UDim2.new(1, -28, 0, 2)
		divider.Parent = root

		local title = Instance.new("TextLabel")
		title.Name = "Title"
		title.BackgroundTransparency = 1
		title.Position = UDim2.new(0, 14, 0, 8)
		title.Size = UDim2.new(1, -28, 0, 24)
		title.Font = Enum.Font.Arcade
		title.Text = "Top Rating"
		title.TextColor3 = Color3.fromRGB(245, 244, 240)
		title.TextSize = 30
		title.Parent = root

		local subtitle = Instance.new("TextLabel")
		subtitle.Name = "Subtitle"
		subtitle.BackgroundTransparency = 1
		subtitle.Position = UDim2.new(0, 14, 0, 30)
		subtitle.Size = UDim2.new(1, -28, 0, 18)
		subtitle.Font = Enum.Font.Arcade
		subtitle.Text = "Judgement Divided Ranked"
		subtitle.TextColor3 = Color3.fromRGB(223, 195, 133)
		subtitle.TextSize = 14
		subtitle.Parent = root

		local columns = Instance.new("TextLabel")
		columns.Name = "Columns"
		columns.BackgroundTransparency = 1
		columns.Position = UDim2.new(0, 16, 0, 74)
		columns.Size = UDim2.new(1, -32, 0, 14)
		columns.Font = Enum.Font.Arcade
		columns.Text = "#      PLAYER           TIER     RATING"
		columns.TextColor3 = Color3.fromRGB(198, 185, 170)
		columns.TextSize = 13
		columns.TextXAlignment = Enum.TextXAlignment.Left
		columns.Parent = root
	end

	for _, child in ipairs(root:GetChildren()) do
		if string.sub(child.Name, 1, 4) == "Row_" then
			child:Destroy()
		end
	end

	if #entries == 0 then
		local empty = Instance.new("TextLabel")
		empty.Name = "Row_Empty"
		empty.BackgroundTransparency = 1
		empty.Position = UDim2.new(0, 16, 0, 102)
		empty.Size = UDim2.new(1, -32, 0, 24)
		empty.Font = Enum.Font.Arcade
		empty.Text = "No rated players yet"
		empty.TextColor3 = Color3.fromRGB(210, 210, 210)
		empty.TextSize = 20
		empty.Parent = root
		return
	end

	for index, entry in ipairs(entries) do
		local userId = tonumber(entry.key)
		local rating = math.floor(tonumber(entry.value) or 0)
		local playerName = userId and self:GetCachedNameForUserId(userId) or "Unknown"
		local tierName = Constants.GetRankTierName(rating)

		local row = Instance.new("Frame")
		row.Name = "Row_" .. tostring(index)
		row.BackgroundColor3 = index == 1 and Color3.fromRGB(78, 54, 22) or (index % 2 == 0 and Color3.fromRGB(34, 24, 24) or Color3.fromRGB(42, 30, 30))
		row.BackgroundTransparency = 0.04
		row.BorderSizePixel = 0
		row.Position = UDim2.new(0, 12, 0, 96 + (index - 1) * 28)
		row.Size = UDim2.new(1, -24, 0, 22)
		row.Parent = root

		local rowCorner = Instance.new("UICorner")
		rowCorner.CornerRadius = UDim.new(0, 8)
		rowCorner.Parent = row

		local rowStroke = Instance.new("UIStroke")
		rowStroke.Color = index == 1 and Color3.fromRGB(223, 195, 133) or Color3.fromRGB(80, 58, 54)
		rowStroke.Transparency = index == 1 and 0.2 or 0.55
		rowStroke.Thickness = 1
		rowStroke.Parent = row

		local place = Instance.new("TextLabel")
		place.BackgroundTransparency = 1
		place.Position = UDim2.new(0, 8, 0, 0)
		place.Size = UDim2.new(0, 22, 1, 0)
		place.Font = Enum.Font.Arcade
		place.Text = "#" .. tostring(index)
		place.TextColor3 = index == 1 and Color3.fromRGB(255, 220, 112) or Color3.fromRGB(245, 244, 240)
		place.TextSize = 18
		place.Parent = row

		local nameLabel = Instance.new("TextLabel")
		nameLabel.BackgroundTransparency = 1
		nameLabel.Position = UDim2.new(0, 32, 0, 0)
		nameLabel.Size = UDim2.new(0.44, 0, 1, 0)
		nameLabel.Font = Enum.Font.Arcade
		nameLabel.Text = playerName
		nameLabel.TextColor3 = Color3.fromRGB(245, 244, 240)
		nameLabel.TextSize = 17
		nameLabel.TextXAlignment = Enum.TextXAlignment.Left
		nameLabel.Parent = row

		local tierLabel = Instance.new("TextLabel")
		tierLabel.BackgroundTransparency = 1
		tierLabel.Position = UDim2.new(0.54, 0, 0, 0)
		tierLabel.Size = UDim2.new(0.18, 0, 1, 0)
		tierLabel.Font = Enum.Font.Arcade
		tierLabel.Text = tierName
		tierLabel.TextColor3 = Color3.fromRGB(223, 195, 133)
		tierLabel.TextSize = 15
		tierLabel.Parent = row

		local ratingLabel = Instance.new("TextLabel")
		ratingLabel.BackgroundTransparency = 1
		ratingLabel.Position = UDim2.new(0.74, 0, 0, 0)
		ratingLabel.Size = UDim2.new(0.24, -8, 1, 0)
		ratingLabel.Font = Enum.Font.Arcade
		ratingLabel.Text = tostring(rating)
		ratingLabel.TextColor3 = Color3.fromRGB(245, 244, 240)
		ratingLabel.TextSize = 17
		ratingLabel.TextXAlignment = Enum.TextXAlignment.Right
		ratingLabel.Parent = row
	end
end

function CombatService:RunRatingLeaderboardLoop()
	while true do
		self:RefreshRatingLeaderboardBoard()
		task.wait(Constants.RANKED_LEADERBOARD_REFRESH_INTERVAL)
	end
end

function CombatService:GetKDR(player)
	local profile = self:GetProfile(player)
	if not profile then
		return 0
	end

	local kills = tonumber(profile.Kills) or 0
	local deaths = tonumber(profile.Deaths) or 0
	if deaths <= 0 then
		return kills
	end

	return math.floor((kills / deaths) * 100) / 100
end

function CombatService:AddKill(player, amount)
	local profile = self:GetProfile(player)
	if not profile then
		return
	end

	profile.Kills = math.max(0, (profile.Kills or 0) + (amount or 1))
	self:SaveProfile(player)
	self:SendProfile(player)
end

function CombatService:AddDeath(player, amount)
	local profile = self:GetProfile(player)
	if not profile then
		return
	end

	profile.Deaths = math.max(0, (profile.Deaths or 0) + (amount or 1))
	self:SaveProfile(player)
	self:SendProfile(player)
end

function CombatService:GetPlayerJoinTeleportData(player)
	local joinData = player:GetJoinData()
	if type(joinData) == "table" and type(joinData.TeleportData) == "table" then
		return joinData.TeleportData
	end
	return nil
end

function CombatService:UpdateRankedMatchDataFromPlayer(player)
	if self.RankedMatchData then
		return
	end

	local teleportData = self:GetPlayerJoinTeleportData(player)
	if type(teleportData) == "table" and teleportData.RankedMatch == true then
		self.RankedMatchData = teleportData
	end
end

function CombatService:GetRankedStats(player)
	local profile = self:GetProfile(player)
	if not profile then
		return Constants.RANKED_START_RATING, 0, 0
	end

	return profile.RankedRating or Constants.RANKED_START_RATING, profile.RankedWins or 0, profile.RankedLosses or 0
end

function CombatService:SendRankedQueueStatus(player, inQueue)
	if not player or not player.Parent then
		return
	end

	self.Remotes.CombatState:FireClient(player, {
		Type = "RankedQueueStatus",
		InQueue = inQueue == true,
	})
end

function CombatService:IsQueuedForRanked(player)
	local state = self:GetState(player)
	return state ~= nil and state.RankedQueueKey ~= nil
end

function CombatService:MakeRankedQueueKey(player)
	return string.format("%010d_%d", os.time(), player.UserId)
end

function CombatService:SetRankedAssignmentForPlayers(players, assignment)
	for _, player in ipairs(players) do
		pcall(function()
			rankedAssignmentStore:SetAsync(tostring(player.UserId), assignment, Constants.RANKED_ASSIGNMENT_TTL)
		end)
	end
end

function CombatService:TryClaimMatchmakingLock()
	local acquired = false
	pcall(function()
		rankedLockStore:UpdateAsync("matchmaker", function(current)
			if type(current) == "table" and current.JobId ~= game.JobId and (current.ExpiresAt or 0) > os.time() then
				return nil
			end
			acquired = true
			return {
				JobId = game.JobId,
				ExpiresAt = os.time() + Constants.RANKED_MATCH_LOCK_SECONDS,
			}
		end, Constants.RANKED_MATCH_LOCK_SECONDS)
	end)
	return acquired
end

function CombatService:LeaveRankedQueue(player, silent)
	local state = self:GetState(player)
	if state and state.RankedQueueKey then
		pcall(function()
			rankedQueueStore:RemoveAsync(state.RankedQueueKey)
		end)
		state.RankedQueueKey = nil
		self:SendRankedQueueStatus(player, false)
		if not silent then
			self:SendMessage(player, "You left the ranked queue.")
		end
	elseif not silent then
		self:SendMessage(player, "You are not in the ranked queue.")
	end
end

function CombatService:ApplyRankedResult(winnerPlayer, loserPlayer)
	local winnerProfile = self:GetProfile(winnerPlayer)
	local loserProfile = self:GetProfile(loserPlayer)
	if not winnerProfile or not loserProfile then
		return
	end

	local winnerRating = tonumber(winnerProfile.RankedRating) or Constants.RANKED_START_RATING
	local loserRating = tonumber(loserProfile.RankedRating) or Constants.RANKED_START_RATING
	local winnerExpected = 1 / (1 + 10 ^ ((loserRating - winnerRating) / 400))
	local loserExpected = 1 / (1 + 10 ^ ((winnerRating - loserRating) / 400))
	local kFactor = Constants.RANKED_K_FACTOR

	local winnerGain = math.max(1, math.floor(kFactor * (1 - winnerExpected) + 0.5))
	local loserLoss = math.max(1, math.floor(kFactor * (0 - loserExpected) * -1 + 0.5))

	winnerProfile.RankedRating = winnerRating + winnerGain
	winnerProfile.RankedWins = (winnerProfile.RankedWins or 0) + 1
	loserProfile.RankedRating = math.max(0, loserRating - loserLoss)
	loserProfile.RankedLosses = (loserProfile.RankedLosses or 0) + 1

	self:SaveProfile(winnerPlayer)
	self:SaveProfile(loserPlayer)
	self:SendProfile(winnerPlayer)
	self:SendProfile(loserPlayer)
	self:SendMessage(winnerPlayer, string.format("Ranked win: +%d rating (%d, %s).", winnerGain, winnerProfile.RankedRating, Constants.GetRankTierName(winnerProfile.RankedRating)))
	self:SendMessage(loserPlayer, string.format("Ranked loss: -%d rating (%d, %s).", loserLoss, loserProfile.RankedRating, Constants.GetRankTierName(loserProfile.RankedRating)))
end

function CombatService:HandleRankedLeavePenalty(player)
	local duel = self.ActiveDuels[player]
	if duel and duel.IsRanked and not duel.Resolved then
		local opponent = duel.A == player and duel.B or duel.A
		local opponentPlayer = getTargetPlayer(opponent)
		if opponentPlayer and opponentPlayer.Parent then
			self:SendMessage(opponentPlayer, string.format("%s left the ranked match. Forfeit win awarded.", player.DisplayName))
			self:ResolveDuel(opponentPlayer, player)
		end
		return
	end

	if not self:IsRankedMatchServer() or not self.RankedMatchData or self.RankedMatchData.ForfeitResolved then
		return
	end

	local participantSet = {}
	for _, userId in ipairs(self.RankedMatchData.Participants or {}) do
		participantSet[tonumber(userId)] = true
	end

	if not participantSet[player.UserId] then
		return
	end

	if self.RankedMatchData.Started then
		return
	end

	local remainingPlayer
	for _, otherPlayer in ipairs(Players:GetPlayers()) do
		if otherPlayer ~= player and participantSet[otherPlayer.UserId] then
			remainingPlayer = otherPlayer
			break
		end
	end

	self.RankedMatchData.ForfeitResolved = true

	if not remainingPlayer then
		return
	end

	self:AddKill(remainingPlayer, 1)
	self:AddDeath(player, 1)
	self:ApplyRankedResult(remainingPlayer, player)
	self:SendMessage(remainingPlayer, string.format("%s left before the ranked match started. Win awarded.", player.DisplayName))

	task.delay(Constants.DUEL_RETURN_DELAY, function()
		if remainingPlayer.Parent then
			self:SendMessage(remainingPlayer, "Returning to main server...")
			pcall(function()
				TeleportService:TeleportAsync(Constants.MAIN_GAME_PLACE_ID, {remainingPlayer})
			end)
		end
	end)
end

function CombatService:TryStartRankedMatch()
	if self:IsTrainingServer() or self:IsRankedMatchServer() then
		return
	end

	if not RunService:IsStudio() and not self:IsRankedQueueServer() then
		return
	end

	if not self:TryClaimMatchmakingLock() then
		return
	end

	local success, entries = pcall(function()
		return rankedQueueStore:GetRangeAsync(Enum.SortDirection.Ascending, 10)
	end)
	if not success or type(entries) ~= "table" or #entries < 2 then
		return
	end

	local chosen = {}
	local chosenCount = 0
	for _, entry in ipairs(entries) do
		if type(entry) == "table" and type(entry.key) == "string" and type(entry.value) == "table" then
			local value = entry.value
			if value.UserId and value.JobId and value.PlaceId == game.PlaceId and not chosen[value.UserId] then
				chosen[value.UserId] = {
					Key = entry.key,
					Value = value,
				}
				chosenCount += 1
				if chosenCount >= 2 then
					break
				end
			end
		end
	end

	local matched = {}
	for _, item in pairs(chosen) do
		table.insert(matched, item)
	end
	if #matched < 2 then
		return
	end

	if RunService:IsStudio() then
		local playerA = Players:GetPlayerByUserId(matched[1].Value.UserId)
		local playerB = Players:GetPlayerByUserId(matched[2].Value.UserId)
		if playerA and playerB then
			for _, item in ipairs(matched) do
				pcall(function()
					rankedQueueStore:RemoveAsync(item.Key)
				end)
			end
			local stateA = self:GetState(playerA)
			local stateB = self:GetState(playerB)
			if stateA then
				stateA.RankedQueueKey = nil
			end
			if stateB then
				stateB.RankedQueueKey = nil
			end
			self:SendRankedQueueStatus(playerA, false)
			self:SendRankedQueueStatus(playerB, false)
			self:StartOneVOne(playerA, playerB, {
				IsRanked = true,
				ModeName = "Ranked",
			})
		end
		return
	end

	for _, item in ipairs(matched) do
		pcall(function()
			rankedQueueStore:RemoveAsync(item.Key)
		end)
	end

	local rankedPlaceId = game.PlaceId
	local reserveSuccess, reservedServerCode = pcall(function()
		return TeleportService:ReserveServer(rankedPlaceId)
	end)
	if not reserveSuccess or not reservedServerCode then
		return
	end

	local matchId = HttpService:GenerateGUID(false)
	local assignment = {
		MatchId = matchId,
		PlaceId = rankedPlaceId,
		ReservedServerCode = reservedServerCode,
		RankedMatch = true,
		ModeName = "Ranked",
		Participants = {
			matched[1].Value.UserId,
			matched[2].Value.UserId,
		},
	}

	self:SetRankedAssignmentForPlayers({
		{UserId = matched[1].Value.UserId},
		{UserId = matched[2].Value.UserId},
	}, assignment)
end

function CombatService:CheckRankedAssignments()
	if self:IsTrainingServer() then
		return
	end

	for _, player in ipairs(Players:GetPlayers()) do
		local state = self:GetState(player)
		local ok, assignment = pcall(function()
			return rankedAssignmentStore:GetAsync(tostring(player.UserId))
		end)
		if ok and type(assignment) == "table" and assignment.ReservedServerCode then
			if state then
				state.RankedQueueKey = nil
			end
			self:SendRankedQueueStatus(player, false)
			pcall(function()
				rankedAssignmentStore:RemoveAsync(tostring(player.UserId))
			end)
			self:SendMessage(player, "Ranked match found. Teleporting...")
			pcall(function()
				TeleportService:TeleportToPrivateServer(
					assignment.PlaceId or game.PlaceId,
					assignment.ReservedServerCode,
					{player},
					nil,
					assignment
				)
			end)
		end
	end
end

function CombatService:TryStartPendingRankedMatch()
	if not self:IsRankedMatchServer() or not self.RankedMatchData or self.RankedMatchData.Started then
		return
	end

	local participants = {}
	local participantSet = {}
	for _, userId in ipairs(self.RankedMatchData.Participants or {}) do
		participantSet[tonumber(userId)] = true
	end

	for _, player in ipairs(Players:GetPlayers()) do
		if participantSet[player.UserId] then
			table.insert(participants, player)
		end
	end

	if #participants < 2 then
		return
	end

	self.RankedMatchData.Started = true
	self:StartOneVOne(participants[1], participants[2], {
		IsRanked = true,
		ModeName = "Ranked",
	})
end

function CombatService:QueueForRanked(player)
	if self:IsTrainingServer() then
		self:SendMessage(player, "Ranked is disabled in the training server.")
		return
	end

	if not RunService:IsStudio() and not self:IsRankedQueueServer() then
		self:SendMessage(player, "Use the ranked queue server from the main menu.")
		return
	end

	if self:IsRankedMatchServer() then
		self:SendMessage(player, "You are already in a ranked match server.")
		return
	end

	local character = player.Character
	local humanoid = getHumanoid(character)
	if not character or not humanoid or humanoid.Health <= 0 then
		self:SendMessage(player, "You need to be alive to queue ranked.")
		return
	end

	if self.ActiveDuels[player] then
		self:SendMessage(player, "You cannot queue ranked while in a duel.")
		return
	end

	if self:IsQueuedForRanked(player) then
		self:SendMessage(player, "You are already in the ranked queue.")
		return
	end

	local state = self:GetState(player)
	if not state then
		return
	end

	local queueKey = self:MakeRankedQueueKey(player)
	local rating = self:GetRankedStats(player)
	local queued = pcall(function()
		rankedQueueStore:SetAsync(queueKey, {
			UserId = player.UserId,
			JobId = game.JobId,
			PlaceId = game.PlaceId,
			DisplayName = player.DisplayName,
			Name = player.Name,
			Rating = rating,
		}, Constants.RANKED_QUEUE_ENTRY_TTL)
	end)
	if not queued then
		self:SendMessage(player, "Failed to join the ranked queue.")
		return
	end

state.RankedQueueKey = queueKey
self:SendRankedQueueStatus(player, true)
self:SendMessage(player, string.format("Joined ranked queue. Rating: %d", rating))
end

function CombatService:TeleportPlayerToMenuDestination(player, destination)
	local targetPlaceId
	if destination == "MainGame" then
		targetPlaceId = Constants.MAIN_GAME_PLACE_ID
	elseif destination == "Training" then
		targetPlaceId = Constants.TRAINING_SERVER_PLACE_IDS[1]
	elseif destination == "RankedQueue" then
		targetPlaceId = Constants.RANKED_QUEUE_PLACE_ID
	end

	if not targetPlaceId or targetPlaceId == 0 then
		self:SendMessage(player, "That destination is not configured.")
		return
	end

	local ok, result = pcall(function()
		return TeleportService:TeleportAsync(targetPlaceId, {player})
	end)

	if not ok then
		self:SendMessage(player, string.format("Teleport failed: %s", tostring(result)))
	end
end

function CombatService:FindPlayerByUserId(userId)
	for _, player in ipairs(Players:GetPlayers()) do
		if player.UserId == userId then
			return player
		end
	end
	return nil
end

function CombatService:FindPlayerByBridgeTarget(target)
	if type(target) == "number" then
		return self:FindPlayerByUserId(target)
	end

	if type(target) == "string" then
		local asNumber = tonumber(target)
		if asNumber then
			return self:FindPlayerByUserId(asNumber)
		end
		return self:FindPlayerByText(nil, target)
	end

	return nil
end

function CombatService:ResolveCharacterTheme(themeText)
	local normalizedTarget = normalizeLookupText(themeText)
	if normalizedTarget == "" then
		return nil
	end

	local characterThemeIds = Constants.CHARACTER_THEME_IDS or {}
	local characterThemeMetadata = Constants.CHARACTER_THEME_METADATA or {}
	for kitId, kit in pairs(CharacterKits) do
		local displayName = (kit and kit.DisplayName) or kitId
		if normalizeLookupText(kitId) == normalizedTarget or normalizeLookupText(displayName) == normalizedTarget then
			local metadata = characterThemeMetadata[kitId] or {}
			return {
				KitId = kitId,
				DisplayName = displayName,
				SoundId = tonumber(characterThemeIds[kitId]) or 0,
				SongName = metadata.SongName or displayName .. " Theme",
				CreatorName = metadata.CreatorName or "Unknown",
			}
		end
	end

	return nil
end

function CombatService:BroadcastGlobalMusicOverride()
	local payload = {
		Type = "GlobalMusicOverride",
		Active = self.GlobalMusicOverride ~= nil,
	}
	if self.GlobalMusicOverride then
		payload.ThemeKey = self.GlobalMusicOverride.ThemeKey
		payload.ThemeName = self.GlobalMusicOverride.ThemeName
		payload.SoundId = self.GlobalMusicOverride.SoundId
		payload.SongName = self.GlobalMusicOverride.SongName
		payload.CreatorName = self.GlobalMusicOverride.CreatorName
	end

	self.Remotes.CombatState:FireAllClients(payload)
end

function CombatService:SendGlobalMusicOverride(player)
	if not player then
		return
	end

	local payload = {
		Type = "GlobalMusicOverride",
		Active = self.GlobalMusicOverride ~= nil,
	}
	if self.GlobalMusicOverride then
		payload.ThemeKey = self.GlobalMusicOverride.ThemeKey
		payload.ThemeName = self.GlobalMusicOverride.ThemeName
		payload.SoundId = self.GlobalMusicOverride.SoundId
		payload.SongName = self.GlobalMusicOverride.SongName
		payload.CreatorName = self.GlobalMusicOverride.CreatorName
	end

	self.Remotes.CombatState:FireClient(player, payload)
end

function CombatService:HandleBridgeJob(job)
	if type(job) ~= "table" or type(job.type) ~= "string" then
		return false, "invalid job"
	end

	if job.type == "announce" then
		local text = job.message or (job.payload and job.payload.message)
		if type(text) ~= "string" or text == "" then
			return false, "missing message"
		end
		self.Remotes.CombatState:FireAllClients({
			Type = "SystemMessage",
			Text = text,
		})
		return true, "announcement sent"
	elseif job.type == "setkills" then
		local payload = job.payload or {}
		local target = self:FindPlayerByBridgeTarget(payload.targetUsername or payload.targetUserId)
		local amount = tonumber(payload.amount)
		if not target or not amount then
			return false, "target player not online or amount invalid"
		end
		local profile = self:GetProfile(target)
		if not profile then
			return false, "profile missing"
		end
		profile.Kills = math.max(0, math.floor(amount))
		self:SaveProfile(target)
		self:SendProfile(target)
		self:SendMessage(target, string.format("Your kills were set to %d by Discord admin.", profile.Kills))
		return true, "kills updated"
	elseif job.type == "setdeaths" then
		local payload = job.payload or {}
		local target = self:FindPlayerByBridgeTarget(payload.targetUsername or payload.targetUserId)
		local amount = tonumber(payload.amount)
		if not target or not amount then
			return false, "target player not online or amount invalid"
		end
		local profile = self:GetProfile(target)
		if not profile then
			return false, "profile missing"
		end
		profile.Deaths = math.max(0, math.floor(amount))
		self:SaveProfile(target)
		self:SendProfile(target)
		self:SendMessage(target, string.format("Your deaths were set to %d by Discord admin.", profile.Deaths))
		return true, "deaths updated"
	elseif job.type == "setrating" then
		local payload = job.payload or {}
		local target = self:FindPlayerByBridgeTarget(payload.targetUsername or payload.targetUserId)
		local amount = tonumber(payload.amount)
		if not target or not amount then
			return false, "target player not online or amount invalid"
		end
		local profile = self:GetProfile(target)
		if not profile then
			return false, "profile missing"
		end
		profile.RankedRating = math.max(0, math.floor(amount))
		self:SaveProfile(target)
		self:SendProfile(target)
		self:SendMessage(target, string.format("Your ranked rating was set to %d by Discord admin.", profile.RankedRating))
		return true, "rating updated"
	elseif job.type == "buff" then
		local payload = job.payload or {}
		local target = self:FindPlayerByBridgeTarget(payload.targetUsername or payload.targetUserId)
		local statName = payload.stat
		local amount = tonumber(payload.amount)
		local allowed = {Attack = true, Defense = true, Health = true, Mana = true, Stamina = true}
		if not target or not statName or not amount or not allowed[statName] then
			return false, "invalid buff payload"
		end

		local targetState = self:GetState(target)
		local character = target.Character
		local humanoid = character and getHumanoid(character)
		if not targetState or not character then
			return false, "target player not ready"
		end

		targetState.Buffs = targetState.Buffs or {}
		targetState.Buffs[statName] = math.max(0, math.floor(amount))
		if statName == "Health" and humanoid then
			humanoid.MaxHealth = math.max(1, math.floor(amount))
			humanoid.Health = humanoid.MaxHealth
		else
			character:SetAttribute(statName, math.max(0, math.floor(amount)))
		end
		self:SendMessage(target, string.format("%s set to %d by Discord admin.", statName, amount))
		return true, "buff applied"
	elseif job.type == "heal" then
		local payload = job.payload or {}
		local target = self:FindPlayerByBridgeTarget(payload.targetUsername or payload.targetUserId)
		local character = target and target.Character
		local humanoid = character and getHumanoid(character)
		local amount = tonumber(payload.amount)
		if not target or not humanoid then
			return false, "target player not ready"
		end

		if amount and amount > 0 then
			humanoid.Health = math.min(humanoid.MaxHealth, humanoid.Health + amount)
		else
			humanoid.Health = humanoid.MaxHealth
		end
		self:SendMessage(target, "You were healed by Discord admin.")
		return true, "heal applied"
	elseif job.type == "kick" then
		local payload = job.payload or {}
		local target = self:FindPlayerByBridgeTarget(payload.targetUsername or payload.targetUserId)
		if not target then
			return false, "target player not online"
		end
		local reason = type(payload.reason) == "string" and payload.reason or "Removed by Discord admin."
		target:Kick(reason)
		return true, "player kicked"
	elseif job.type == "return_to_main" then
		local payload = job.payload or {}
		local target = self:FindPlayerByBridgeTarget(payload.targetUsername or payload.targetUserId)
		if not target or not target.Character then
			return false, "target player not ready"
		end
		self:ResetCombatState(target)
		self:ReturnToMainMap(target)
		self:SendMessage(target, "You were returned to the main map by Discord admin.")
		return true, "player returned"
	elseif job.type == "duel" then
		local payload = job.payload or {}
		local challenger = self:FindPlayerByBridgeTarget(payload.challengerUsername or payload.challengerUserId)
		if not challenger then
			return false, "challenger not online"
		end

		local opponent
		if payload.opponent == "dummy" then
			opponent = self:FindDuelDummy()
			if not opponent then
				return false, "no dummy available"
			end
		else
			opponent = self:FindPlayerByBridgeTarget(payload.opponentUsername or payload.opponentUserId)
			if not opponent then
				return false, "opponent not online"
			end
		end

		self:StartOneVOne(challenger, opponent)
		return true, "duel started"
	elseif job.type == "shutdownserver" then
		local payload = job.payload or {}
		local reason = type(payload.reason) == "string" and payload.reason or "Server shutdown requested by Discord admin."
		self.Remotes.CombatState:FireAllClients({
			Type = "SystemMessage",
			Text = reason,
		})
		task.delay(1, function()
			for _, player in ipairs(Players:GetPlayers()) do
				player:Kick(reason)
			end
		end)
		return true, "server shutdown initiated"
	end

	return false, "unsupported job"
end

function CombatService:RunBridgeLoop()
	while true do
		task.wait(Constants.BRIDGE_POLL_INTERVAL)

		if not self:IsBridgeConfigured() then
			self:SetBridgeStatus("disabled")
			continue
		end

		local ok, response = self:RequestBridge("GET", string.format("/api/roblox/jobs?placeId=%s&jobId=%s&role=%s", tostring(game.PlaceId), HttpService:UrlEncode(game.JobId), HttpService:UrlEncode(self:GetServerRole())))
		if not ok or type(response) ~= "table" or type(response.jobs) ~= "table" then
			self:SetBridgeStatus("error", type(response) == "string" and response or nil)
			continue
		end

		self:SetBridgeStatus("connected")

		for _, job in ipairs(response.jobs) do
			local success, result = self:HandleBridgeJob(job)
			self:RequestBridge("POST", string.format("/api/roblox/jobs/%s/complete", HttpService:UrlEncode(tostring(job.id))), {
				success = success,
				result = result,
				serverJobId = game.JobId,
				placeId = game.PlaceId,
			})
		end
	end
end

function CombatService:RunBridgeHeartbeatLoop()
	while true do
		if not self:IsBridgeConfigured() then
			task.wait(Constants.BRIDGE_HEARTBEAT_INTERVAL)
			continue
		end

		self:RequestBridge("POST", "/api/roblox/heartbeat", self:BuildBridgePresence())
		task.wait(Constants.BRIDGE_HEARTBEAT_INTERVAL)
	end
end

function CombatService:OnPlayerAdded(player)
	self:UpdateRankedMatchDataFromPlayer(player)
	self:LoadProfile(player)
	self:EnsureLeaderstats(player)
	self:UpdateTesterAccess(player)
	local state = self:GetDefaultState()
	self.PlayerState[player] = state
	player:SetAttribute(Constants.AWAITING_CHARACTER_ATTRIBUTE, not self:IsRankedMatchServer())

	player.CharacterAdded:Connect(function(character)
		self:OnCharacterAdded(player, character)
	end)

	player.Chatted:Connect(function(message)
		self:HandleChatCommand(player, message)
	end)

	if player.Character then
		self:OnCharacterAdded(player, player.Character)
	elseif self:IsRankedMatchServer() then
		task.defer(function()
			if player.Parent and not player.Character then
				player:LoadCharacter()
			end
		end)
	end

	self:SendProfile(player)
	self:SendGlobalMusicOverride(player)
	if self:IsTrainingServer() then
		self:SendMessage(player, "Training server: PvP is disabled. Dummies can still be attacked.")
	elseif self:IsRankedMatchServer() then
		self:SendMessage(player, "Ranked match server: preparing your isolated 1v1.")
		task.delay(2, function()
			self:TryStartPendingRankedMatch()
		end)
	end
end

function CombatService:OnCharacterAdded(player, character)
	local state = self.PlayerState[player]
	local humanoid = getHumanoid(character)
	local kit = self:GetKit(player)
	if not humanoid or not state or not kit then
		return
	end

	for _, scriptName in ipairs({"Health", "HealthScript"}) do
		local healthScript = character:FindFirstChild(scriptName)
		if healthScript and healthScript:IsA("Script") then
			healthScript:Destroy()
		end
	end

	self:DestroyActiveBlasters(player, state)
	self:InvalidatePendingAbilityCasts(state)
	state.LastM1At = 0
	state.ComboStep = 0
	state.M1CooldownUntil = 0
	state.AbilityBurstCounts = {}
	state.AbilityHoldStates = {}
	state.CastLockUntil = 0
	state.IsBlocking = false
	state.IsStunnedUntil = 0
	state.LastDashAt = 0
	state.CounterUntil = 0
	state.IFrameUntil = 0
	state.BlackSilencePhase = 0
	state.BlackSilenceFinalIntroPlayed = false
	self:ResetTelekinesisState(state)
	state.LastBlockEndedAt = 0
	state.PerfectBlockUntil = 0
	if state.BlockAura then
		self.Effects:DestroyBlockAura(state.BlockAura)
		state.BlockAura = nil
	end
	state.Mode = kit.Modes and kit.Modes[1] or "Base"
	local buffs = state.Buffs or {}

	local maxHealth = buffs.Health or kit.Stats.Health
	if kit.DisplayName == "Sans" then
		maxHealth = self:GetSansDodgeCapacity(player, kit)
	end
	humanoid.MaxHealth = maxHealth
	humanoid.Health = maxHealth
	humanoid.WalkSpeed = tonumber(kit.Stats and kit.Stats.WalkSpeed) or Constants.DEFAULT_WALKSPEED
	humanoid.Jump = true
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	humanoid.NameDisplayDistance = 0
	humanoid.HealthDisplayDistance = 0
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, true)

	character:SetAttribute("KitId", state.KitId)
	character:SetAttribute("Mode", state.Mode)
	character:SetAttribute("Blocking", false)
	character:SetAttribute("Stunned", false)
	character:SetAttribute("InCombat", false)
	character:SetAttribute("Mana", buffs.Mana or kit.Stats.Mana or 0)
	character:SetAttribute("Stamina", buffs.Stamina or kit.Stats.Stamina or 0)
	character:SetAttribute("Attack", buffs.Attack or kit.Stats.Attack or 0)
	character:SetAttribute("Defense", buffs.Defense or kit.Stats.Defense or 0)
	character:SetAttribute("MaxDodge", kit.DisplayName == "Sans" and maxHealth or 0)
	character:SetAttribute("Dodge", kit.DisplayName == "Sans" and maxHealth or 0)
	character:SetAttribute("Dodging", false)
	character:SetAttribute("DodgeDirection", "")
	character:SetAttribute("DodgeNonce", 0)
	character:SetAttribute("ActiveBlasters", 0)
	character:SetAttribute("PendingBlasterShots", 0)
	character:SetAttribute("NaoyaFrameMarks", 0)
	character:SetAttribute("NaoyaFrozen", false)
	character:SetAttribute("SamuraiBleedMarks", 0)
	character:SetAttribute("SamuraiBleeding", false)
	character:SetAttribute(THEME_SOUND_ATTRIBUTE, 0)
	character:SetAttribute(BLACK_SILENCE_PHASE_ATTRIBUTE, 0)
	local profile = self:GetProfile(player)
	if profile then
		self:NormalizeSelectedSkins(profile)
	end
	self:ApplySelectedSkinAppearance(player, character)

	humanoid.Died:Connect(function()
		self:HandleCharacterDeath(player)
	end)
	humanoid.HealthChanged:Connect(function()
		if player.Character == character then
			self:UpdateBlackSilencePhaseState(player, character, humanoid)
		end
	end)

	character.AncestryChanged:Connect(function(_, parent)
		if not parent then
			self:ClearKnockbackAnimationState(character)
			self.CharacterAppearanceCache[character] = nil
			self.NaoyaFrameMarks[character] = nil
			self.SamuraiBleedMarks[character] = nil
			self.ActiveSamuraiBleeds[character] = nil
		end
	end)
end

function CombatService:GetState(player)
	return self.PlayerState[player]
end

function CombatService:GetKit(player)
	local state = self:GetState(player)
	return state and CharacterKits[state.KitId]
end

function CombatService:GetKitById(kitId)
	return CharacterKits[kitId]
end

function CombatService:HasTesterAccess(player)
	if not player then
		return false
	end

	if isAdminUserId(player.UserId) then
		return true
	end

	local groupId = getTesterGroupId()
	if groupId == 0 then
		return false
	end

	local ok, roleName = pcall(function()
		return player:GetRoleInGroup(groupId)
	end)
	if not ok then
		return false
	end

	return string.lower(roleName or "") == string.lower(Constants.TESTER_GROUP_ROLE_NAME or "Tester")
end

function CombatService:UpdateTesterAccess(player)
	local hasAccess = self:HasTesterAccess(player)
	player:SetAttribute(Constants.TESTER_ACCESS_ATTRIBUTE, hasAccess)
	return hasAccess
end

function CombatService:GetModeAbilities(player)
	local state = self:GetState(player)
	local kit = self:GetKit(player)
	if not state or not kit then
		return nil
	end

	if kit.Modes then
		return kit.Abilities[state.Mode]
	end

	return kit.Abilities.Base or kit.Abilities
end

function CombatService:GetCooldownKey(player, slot)
	local state = self:GetState(player)
	local kit = self:GetKit(player)
	if not state or not kit then
		return slot
	end

	local modeKey = kit.Modes and state.Mode or "Base"
	return string.format("%s:%s:%s", state.KitId, modeKey, slot)
end

function CombatService:InvalidatePendingAbilityCasts(state)
	if not state then
		return
	end

	state.AbilityCastToken = (state.AbilityCastToken or 0) + 1
end

function CombatService:IsAbilityCastTokenValid(player, token)
	local state = self:GetState(player)
	return state ~= nil and (state.AbilityCastToken or 0) == token
end

function CombatService:GetAbilityStartupDuration(ability)
	return ability and (tonumber(ability.Startup) or 0) or 0
end

function CombatService:GetAbilityEndLagDuration(ability)
	return ability and (tonumber(ability.EndLag) or 0) or 0
end

function CombatService:PerformAbilityByKit(player, slot, ability, payload)
	local state = self:GetState(player)
	local kit = self:GetKit(player)
	if not state or not kit or not ability then
		return false
	end

	if kit.DisplayName == "Sans" then
		if state.Mode == "Bones" then
			return self:PerformSansBonesAbility(player, slot, ability, payload)
		elseif state.Mode == "Telekinesis" then
			return self:PerformSansTelekinesisAbility(player, slot, ability, payload)
		elseif state.Mode == "Blasters" then
			return self:PerformSansBlasterAbility(player, slot, ability, payload)
		end
	elseif kit.DisplayName == "Magnus" then
		return self:PerformMagnusAbility(player, slot, ability, payload)
	elseif self:GetState(player) and self:GetState(player).KitId == "Samurai" then
		return self:PerformSamuraiAbility(player, slot, ability, payload)
	elseif kit.DisplayName == "Naoya" then
		return self:PerformNaoyaAbility(player, slot, ability, payload)
	end

	return false
end

function CombatService:GetAppliedAbilityCooldown(player, slot, ability)
	local state = self:GetState(player)
	local cooldownKey = self:GetCooldownKey(player, slot)
	if not state or not ability or not cooldownKey then
		return ability and ability.Cooldown or 0
	end

	local holdCastCooldown = tonumber(ability.HoldCastCooldown) or 0
	local maxHoldDuration = tonumber(ability.MaxHoldDuration) or 0
	if ability.Holdable and holdCastCooldown > 0 and maxHoldDuration > 0 then
		state.AbilityHoldStates = state.AbilityHoldStates or {}
		local holdState = state.AbilityHoldStates[cooldownKey]
		local currentTime = now()
		local resetWindow = math.max(holdCastCooldown * 2, 0.18)

		if not holdState or currentTime - (holdState.LastCastAt or 0) > resetWindow then
			holdState = {
				StartAt = currentTime,
			}
			state.AbilityHoldStates[cooldownKey] = holdState
		end

		holdState.LastCastAt = currentTime
		if currentTime - holdState.StartAt >= maxHoldDuration then
			state.AbilityHoldStates[cooldownKey] = nil
			if state.AbilityBurstCounts then
				state.AbilityBurstCounts[cooldownKey] = nil
			end
			return ability.Cooldown or 0
		end

		if state.AbilityBurstCounts then
			state.AbilityBurstCounts[cooldownKey] = nil
		end
		return holdCastCooldown
	end

	local burstUses = tonumber(ability.BurstUses) or 0
	local burstCooldown = tonumber(ability.BurstCooldown) or 0
	if burstUses <= 0 or burstCooldown <= 0 then
		if state.AbilityBurstCounts then
			state.AbilityBurstCounts[cooldownKey] = nil
		end
		if state.AbilityHoldStates then
			state.AbilityHoldStates[cooldownKey] = nil
		end
		return ability.Cooldown or 0
	end

	if state.AbilityHoldStates then
		state.AbilityHoldStates[cooldownKey] = nil
	end
	state.AbilityBurstCounts = state.AbilityBurstCounts or {}
	local burstCount = (state.AbilityBurstCounts[cooldownKey] or 0) + 1
	if burstCount <= burstUses then
		state.AbilityBurstCounts[cooldownKey] = burstCount
		return burstCooldown
	end

	state.AbilityBurstCounts[cooldownKey] = nil
	return ability.Cooldown or 0
end

function CombatService:FinalizeHeldAbility(player, slot)
	local state = self:GetState(player)
	local abilities = self:GetModeAbilities(player)
	local ability = abilities and abilities[slot]
	if not state or not ability or not ability.Holdable then
		return
	end

	local cooldownKey = self:GetCooldownKey(player, slot)
	local holdState = state.AbilityHoldStates and state.AbilityHoldStates[cooldownKey]
	if not holdState then
		return
	end

	state.AbilityHoldStates[cooldownKey] = nil
	if state.AbilityBurstCounts then
		state.AbilityBurstCounts[cooldownKey] = nil
	end
	state.CastLockUntil = 0
	self:RefreshMovementState(player)

	local appliedCooldown = ability.Cooldown or 0
	state.Cooldowns[cooldownKey] = math.max(state.Cooldowns[cooldownKey] or 0, now() + appliedCooldown)
	self.Remotes.CombatState:FireAllClients({
		Type = "CooldownSet",
		Player = player.UserId,
		Slot = slot,
		Cooldown = appliedCooldown,
		CooldownKey = cooldownKey,
		KitId = state.KitId,
		Mode = state.Mode,
	})
end

function CombatService:IsActionLocked(player)
	local state = self:GetState(player)
	return not state or state.IsStunnedUntil > now()
end

function CombatService:IsMovementLocked(player)
	local state = self:GetState(player)
	return not state or state.IsBlocking or state.IsStunnedUntil > now() or (state.CastLockUntil or 0) > now()
end

function CombatService:RefreshMovementState(player, options)
	options = options or {}
	local targetPlayer = getTargetPlayer(player)
	local character = getTargetCharacter(player)
	local humanoid = getHumanoid(character)
	if not targetPlayer or not character or not humanoid then
		return
	end

	local state = self:GetState(targetPlayer)
	if not state then
		return
	end

	local kit = self:GetKit(targetPlayer)
	local movementLocked = state.IsBlocking or state.IsStunnedUntil > now() or (state.CastLockUntil or 0) > now()
	local baseWalkSpeed = tonumber(kit.Stats and kit.Stats.WalkSpeed) or Constants.DEFAULT_WALKSPEED
	local runWalkSpeed = tonumber(kit.Stats and kit.Stats.RunWalkSpeed) or Constants.RUN_WALKSPEED or baseWalkSpeed
	local walkSpeed = baseWalkSpeed
	if state.IsRunning and not movementLocked then
		walkSpeed = runWalkSpeed
	end
	humanoid.WalkSpeed = movementLocked and 0 or walkSpeed
	humanoid.Jump = false
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, not movementLocked)

	if movementLocked and not options.PreserveMomentum then
		local root = getCharacterRoot(character)
		if root then
			local preserveVerticalMomentum = state.IsBlocking and shouldPreserveAirMomentum(humanoid, root)
			root.AssemblyLinearVelocity = preserveVerticalMomentum
				and Vector3.new(0, root.AssemblyLinearVelocity.Y, 0)
				or Vector3.zero
			root.AssemblyAngularVelocity = Vector3.zero
		end
	end
end

function CombatService:ApplyCastLock(player, duration)
	local state = self:GetState(player)
	if not state or duration <= 0 or not player.Character then
		return
	end

	state.CastLockUntil = math.max(state.CastLockUntil or 0, now() + duration)
	self:RefreshMovementState(player)

	task.delay(duration, function()
		if self.PlayerState[player] and player.Character and (self.PlayerState[player].CastLockUntil or 0) <= now() then
			self:RefreshMovementState(player)
		end
	end)
end

function CombatService:GetAbilityCastLockDuration(player, slot, ability)
	local kit = self:GetKit(player)
	local state = self:GetState(player)
	if not kit or not state or not ability then
		return 0
	end

	if ability.Holdable then
		return tonumber(ability.MaxHoldDuration) or 0
	end

	local startup = self:GetAbilityStartupDuration(ability)
	local windup = tonumber(ability.Windup) or 0
	local activeDuration = tonumber(ability.ActiveDuration) or 0
	local endLag = self:GetAbilityEndLagDuration(ability)
	if kit.DisplayName == "Sans" and state.Mode == "Telekinesis" and slot == "Z" then
		return (tonumber(ability.EscapeWindow) or 0) + endLag
	end

	if startup > 0 or windup > 0 or activeDuration > 0 or endLag > 0 then
		return startup + windup + activeDuration + endLag
	end

	if kit.DisplayName == "Sans" then
		if state.Mode == "Bones" then
			local durations = {
				X = 0.9,
				C = 0.35,
				V = 0.4,
				G = 0.25,
			}
			return durations[slot] or 0.25
		elseif state.Mode == "Telekinesis" then
			return slot == "Z" and (tonumber(ability.EscapeWindow) or 0) or 0
		elseif state.Mode == "Blasters" then
			local durations = {
				Z = 0.2,
				X = 0.25,
			}
			return durations[slot] or 0.2
		end
	elseif kit.DisplayName == "Magnus" then
		local durations = {
			Z = 0.45,
			X = 0.35,
			C = 0.45,
			V = 0.4,
			G = 0.55,
		}
		return durations[slot] or 0.35
	elseif state.KitId == "Samurai" then
		local durations = {
			Z = 0.3,
			X = 0.38,
			C = 0.34,
			V = 0.4,
			G = 0.55,
		}
		return durations[slot] or 0.34
	elseif kit.DisplayName == "Naoya" then
		local durations = {
			Z = 0.28,
			X = 0.38,
			C = 0.34,
			V = 0.42,
			G = 0.5,
		}
		return durations[slot] or 0.3
	end

	return 0.3
end

function CombatService:SendMessage(player, text)
	self.Remotes.CombatState:FireClient(player, {
		Type = "SystemMessage",
		Text = text,
	})
end

function CombatService:SendDodgeDebug(player, text)
	if not Constants.SANS_DODGE_DEBUG or not player or type(text) ~= "string" then
		return
	end

	self.Remotes.CombatState:FireClient(player, {
		Type = "DodgeDebug",
		Text = text,
	})
end

function CombatService:SayCharacterQuote(character, text, color)
	if type(text) ~= "string" or text == "" then
		return
	end

	local adorneePart = getQuoteAdorneePart(character)
	if not adorneePart then
		return
	end

	local existing = character:FindFirstChild("CharacterQuote")
	if existing then
		existing:Destroy()
	end

	local textColor = typeof(color) == "Color3" and color or Color3.fromRGB(245, 245, 245)

	local bubble = Instance.new("BillboardGui")
	bubble.Name = "CharacterQuote"
	bubble.Adornee = adorneePart
	bubble.Size = UDim2.fromOffset(290, 88)
	bubble.StudsOffsetWorldSpace = Vector3.new(0, 4.35, 0)
	bubble.AlwaysOnTop = true
	bubble.LightInfluence = 0
	bubble.Parent = character

	local frame = Instance.new("Frame")
	frame.Size = UDim2.fromScale(1, 1)
	frame.BackgroundColor3 = Color3.fromRGB(20, 18, 22)
	frame.BackgroundTransparency = 0.16
	frame.BorderSizePixel = 0
	frame.Parent = bubble

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 12)
	corner.Parent = frame

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(255, 210, 210)
	stroke.Transparency = 0.24
	stroke.Thickness = 1.2
	stroke.Parent = frame

	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 8)
	padding.PaddingBottom = UDim.new(0, 8)
	padding.PaddingLeft = UDim.new(0, 10)
	padding.PaddingRight = UDim.new(0, 10)
	padding.Parent = frame

	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.Arcade
	label.Text = text
	label.TextWrapped = true
	label.TextScaled = false
	label.TextSize = 15
	label.TextColor3 = textColor
	label.TextStrokeColor3 = Color3.fromRGB(8, 8, 10)
	label.TextStrokeTransparency = 0.35
	label.TextXAlignment = Enum.TextXAlignment.Center
	label.TextYAlignment = Enum.TextYAlignment.Center
	label.Parent = frame

	Debris:AddItem(bubble, 3)
end

function CombatService:MaybeTriggerNaoyaEngageQuote(defender, attacker)
	local defenderPlayer = getTargetPlayer(defender)
	local attackerPlayer = getTargetPlayer(attacker)
	local attackerCharacter = getTargetCharacter(attacker)
	local defenderCharacter = getTargetCharacter(defender)
	if not defenderPlayer or not attackerCharacter or defenderPlayer == attackerPlayer or not defenderCharacter then
		return
	end

	local defenderState = self:GetState(defenderPlayer)
	if not defenderState or defenderState.KitId ~= "Naoya" then
		return
	end

	local combatSessionId = defenderState.CombatSessionId or 0
	if defenderCharacter:GetAttribute("InCombat") ~= true then
		combatSessionId += 1
	end

	if defenderState.NaoyaEngageQuoteSessionId == combatSessionId then
		return
	end

	local attackerName
	if attackerPlayer then
		local attackerKit = self:GetKit(attackerPlayer)
		attackerName = (attackerKit and attackerKit.DisplayName) or attackerPlayer.DisplayName or attackerPlayer.Name
	else
		attackerName = attackerCharacter:GetAttribute("DisplayName") or attackerCharacter.Name
	end
	defenderState.NaoyaEngageQuoteSessionId = combatSessionId
	self:SayCharacterQuote(defenderCharacter, string.format("A %s should walk 3 steps behind me.", attackerName), Enum.ChatColor.White)
end

function CombatService:GetResource(player, resourceName)
	local character = player.Character
	return character and (character:GetAttribute(resourceName) or 0) or 0
end

function CombatService:SetResource(player, resourceName, value)
	setCharacterAttribute(player, resourceName, math.max(0, math.floor(value)))
end

function CombatService:GetSansDodgeCapacity(player, kit)
	kit = kit or self:GetKit(player)
	if not player or not kit or kit.DisplayName ~= "Sans" then
		return 0
	end

	local passive = kit.Passive or {}
	local state = self:GetState(player)
	local buffs = state and state.Buffs or {}
	local maxDodge = buffs.Dodge or passive.MaxDodge or 600
	return math.max(1, math.floor(maxDodge))
end

function CombatService:SetSansDodgePoints(player, value, kit)
	local character = player and player.Character
	local humanoid = getHumanoid(character)
	kit = kit or self:GetKit(player)
	if not player or not character or not humanoid or not kit or kit.DisplayName ~= "Sans" then
		return 0
	end

	local maxDodge = self:GetSansDodgeCapacity(player, kit)
	local clampedValue = math.clamp(math.floor((value or 0) + 0.5), 0, maxDodge)
	character:SetAttribute("MaxDodge", maxDodge)
	character:SetAttribute("Dodge", clampedValue)
	humanoid.MaxHealth = maxDodge
	humanoid.Health = clampedValue
	return clampedValue
end

function CombatService:SpendResource(player, resourceName, amount)
	if amount <= 0 then
		return true
	end

	local current = self:GetResource(player, resourceName)
	if current < amount then
		return false
	end

	self:SetResource(player, resourceName, current - amount)
	return true
end

function CombatService:GetAimPosition(player, payload, fallbackDistance)
	local root = getCharacterRoot(player.Character)
	if not root then
		return Vector3.zero
	end

	if payload and typeof(payload.MousePosition) == "Vector3" then
		local offset = clampVector(payload.MousePosition - root.Position, fallbackDistance or 60)
		return root.Position + offset
	end

	return root.Position + root.CFrame.LookVector * (fallbackDistance or 12)
end

function CombatService:RunResourceRegen()
	while true do
		task.wait(0.25)

		for _, player in ipairs(Players:GetPlayers()) do
			local state = self:GetState(player)
			local kit = self:GetKit(player)
			local character = player.Character
			local humanoid = getHumanoid(character)
			if state and kit and character and humanoid then
				local manaMax = kit.Stats.Mana or 0
				if manaMax > 0 then
					local manaGain = Constants.MANA_REGEN_PER_SECOND * 0.25
					self:SetResource(player, "Mana", math.min(manaMax, self:GetResource(player, "Mana") + manaGain))
				end

				local staminaMax = kit.Stats.Stamina or 0
				if staminaMax > 0 then
					local isMovementLocked = state.IsBlocking or state.IsStunnedUntil > now() or (state.CastLockUntil or 0) > now()
					local isActuallyRunning = state.IsRunning and not isMovementLocked and humanoid.MoveDirection.Magnitude > 0.05 and humanoid.Health > 0
					if isActuallyRunning then
						local staminaDrain = Constants.RUN_STAMINA_DRAIN_PER_SECOND * 0.25
						local newStamina = math.max(0, self:GetResource(player, "Stamina") - staminaDrain)
						self:SetResource(player, "Stamina", newStamina)
						if newStamina <= 0 then
							state.IsRunning = false
							self:RefreshMovementState(player)
						end
					else
						local staminaGain = Constants.STAMINA_REGEN_PER_SECOND * 0.25
						self:SetResource(player, "Stamina", math.min(staminaMax, self:GetResource(player, "Stamina") + staminaGain))
					end
				end
			end
		end
	end
end

function CombatService:GetAllPotentialTargets(attacker)
	local targets = {}
	if not self:IsTrainingServer() then
		for _, otherPlayer in ipairs(Players:GetPlayers()) do
			if otherPlayer ~= attacker and otherPlayer.Character then
				local humanoid = getHumanoid(otherPlayer.Character)
				if humanoid and humanoid.Health > 0 then
					table.insert(targets, otherPlayer.Character)
				end
			end
		end
	end

	for _, npc in ipairs(getNpcFolder():GetChildren()) do
		if npc:IsA("Model") then
			local humanoid = getHumanoid(npc)
			if humanoid and humanoid.Health > 0 then
				table.insert(targets, npc)
			end
		end
	end

	return targets
end

function CombatService:FindClosestTargetToPosition(player, position, maxDistance)
	local closestTarget
	local closestDistance = maxDistance

	for _, target in ipairs(self:GetAllPotentialTargets(player)) do
		local root = getCharacterRoot(target)
		local humanoid = getHumanoid(target)
		if root and humanoid and humanoid.Health > 0 then
			local distance = (root.Position - position).Magnitude
			if distance <= closestDistance then
				closestTarget = target
				closestDistance = distance
			end
		end
	end

	return closestTarget
end

function CombatService:GetLockedTargetFromPayload(player, payload, maxDistance)
	if typeof(payload) ~= "table" then
		return nil
	end

	local sourceRoot = getCharacterRoot(player.Character)
	if not sourceRoot then
		return nil
	end

	local targetUserId = tonumber(payload.LockedTargetUserId)
	local targetName = type(payload.LockedTargetName) == "string" and payload.LockedTargetName or nil
	if not targetUserId and not targetName then
		return nil
	end

	for _, target in ipairs(self:GetAllPotentialTargets(player)) do
		local targetPlayer = getTargetPlayer(target)
		local targetCharacter = getTargetCharacter(target)
		local targetRoot = getCharacterRoot(targetCharacter)
		if targetCharacter and targetRoot then
			local matches = false
			if targetPlayer and targetUserId and targetPlayer.UserId == targetUserId then
				matches = true
			elseif not targetPlayer and targetName and targetCharacter.Name == targetName then
				matches = true
			end

			if matches and (targetRoot.Position - sourceRoot.Position).Magnitude <= maxDistance then
				return target
			end
		end
	end

	return nil
end

function CombatService:ResolveSansTargetFromPayload(player, payload, maxDistance)
	return self:GetLockedTargetFromPayload(player, payload, maxDistance)
		or self:FindClosestTargetToPosition(player, self:GetAimPosition(player, payload, maxDistance), maxDistance)
end

function CombatService:FireSansBlasterBeam(player, origin, endPos, ability, color, options)
	if not origin or not endPos or not ability then
		return false
	end

	local palette = self:GetSansEffectPalette(player)
	local beamColor = color or palette.Beam
	self.Effects:SpawnBeam(origin, endPos, beamColor)
	local cf = CFrame.lookAt(origin:Lerp(endPos, 0.5), endPos)
	local size = Vector3.new(3, 4, math.max(6, (endPos - origin).Magnitude))
	local targets = self.Hitboxes:QueryBox(player, cf, size, {
		CFrame = cf,
		Size = size,
		Color = beamColor,
		Duration = 0.12,
	})

	return self:DamageTargets(
		player,
		targets,
		ability.FireDamage or ability.Damage,
		ability.FireKnockback or ability.Knockback,
		ability.FireStun or ability.Stun,
		options
	)
end

function CombatService:SetKit(player, kitId)
	local state = self:GetState(player)
	local kit = self:GetKitById(kitId)
	if not state or not kit then
		return
	end

	if kit.PrivateAccess == "Tester" and not self:UpdateTesterAccess(player) then
		self:SendMessage(player, string.format("%s is only available to Roblox group testers.", kit.DisplayName))
		return
	end

	self:DestroyActiveBlasters(player, state)
	self:InvalidatePendingAbilityCasts(state)
	state.KitId = kitId
	state.Cooldowns = {}
	state.AbilityBurstCounts = {}
	state.AbilityHoldStates = {}
	state.CastLockUntil = 0
	state.Mode = kit.Modes and kit.Modes[1] or "Base"
	self:ResetTelekinesisState(state)
	player:SetAttribute(Constants.AWAITING_CHARACTER_ATTRIBUTE, false)

	local humanoid = getHumanoid(player.Character)
	if not player.Character or not humanoid or humanoid.Health <= 0 then
		player:LoadCharacter()
	elseif player.Character then
		self:OnCharacterAdded(player, player.Character)
	end

	self.Remotes.CombatState:FireClient(player, {
		Type = "KitChanged",
		KitId = kitId,
		Mode = state.Mode,
	})
end

function CombatService:CycleKit(player)
	local state = self:GetState(player)
	if state then
		local availableKits = {"Sans", "Magnus"}
		table.insert(availableKits, "Samurai")
		if self:HasTesterAccess(player) then
			table.insert(availableKits, "Naoya")
		end

		local currentIndex = table.find(availableKits, state.KitId) or 1
		local nextIndex = (currentIndex % #availableKits) + 1
		self:SetKit(player, availableKits[nextIndex])
	end
end

function CombatService:FindPlayerByText(sourcePlayer, text)
	if type(text) ~= "string" or text == "" then
		return nil
	end

	local needle = string.lower(text)
	local exactMatch
	local partialMatch

	for _, otherPlayer in ipairs(Players:GetPlayers()) do
		if otherPlayer ~= sourcePlayer then
			local name = string.lower(otherPlayer.Name)
			local displayName = string.lower(otherPlayer.DisplayName)
			if name == needle or displayName == needle then
				exactMatch = otherPlayer
				break
			end
			if string.sub(name, 1, #needle) == needle or string.find(displayName, needle, 1, true) then
				partialMatch = partialMatch or otherPlayer
			end
		end
	end

	return exactMatch or partialMatch
end

function CombatService:FindDuelDummy()
	local folder = getNpcFolder()
	return folder:FindFirstChild("TargetDummy") or folder:FindFirstChild("BlockDummy") or folder:FindFirstChild("AttackDummy")
end

function CombatService:ReturnToMainMap(target)
	local character = getTargetCharacter(target)
	local root = getCharacterRoot(character)
	if root then
		root.CFrame = CFrame.new(Constants.MAIN_MAP_RETURN_POSITION)
	end
end

function CombatService:CleanupDuelState(target)
	self:LeaveRankedQueue(target, true)

	local duel = self.ActiveDuels[target]
	if duel then
		self.ActiveDuels[duel.A] = nil
		self.ActiveDuels[duel.B] = nil
	end

	for requestedPlayer, request in pairs(self.PendingDuelRequests) do
		if requestedPlayer == target or request.From == target then
			self.PendingDuelRequests[requestedPlayer] = nil
		end
	end
end

function CombatService:ResolveDuel(winner, loser)
	local duel = self.ActiveDuels[winner] or self.ActiveDuels[loser]
	if not duel or duel.Resolved then
		return
	end

	duel.Resolved = true
	self.ActiveDuels[duel.A] = nil
	self.ActiveDuels[duel.B] = nil

	local winnerPlayer = getTargetPlayer(winner)
	local loserPlayer = getTargetPlayer(loser)
	local winnerName = winnerPlayer and winnerPlayer.DisplayName or (getTargetCharacter(winner) and (getTargetCharacter(winner):GetAttribute("DisplayName") or getTargetCharacter(winner).Name)) or "Unknown"
	local loserName = loserPlayer and loserPlayer.DisplayName or (getTargetCharacter(loser) and (getTargetCharacter(loser):GetAttribute("DisplayName") or getTargetCharacter(loser).Name)) or "Unknown"

	if winnerPlayer and loserPlayer then
		self:AddKill(winnerPlayer, 1)
		self:AddDeath(loserPlayer, 1)
		if duel.IsRanked then
			self:ApplyRankedResult(winnerPlayer, loserPlayer)
		end
	end

	self.Remotes.CombatState:FireAllClients({
		Type = "DuelEnded",
		Winner = winnerName,
		Loser = loserName,
		Mode = duel.ModeName or "1v1",
	})

	task.delay(Constants.DUEL_RETURN_DELAY, function()
		if duel.IsRanked and winnerPlayer and loserPlayer then
			local playersToReturn = {}
			if winnerPlayer.Parent then
				table.insert(playersToReturn, winnerPlayer)
			end
			if loserPlayer.Parent then
				table.insert(playersToReturn, loserPlayer)
			end
			if #playersToReturn > 0 then
				for _, player in ipairs(playersToReturn) do
					self:SendMessage(player, "Returning to main server...")
				end
				pcall(function()
					TeleportService:TeleportAsync(Constants.MAIN_GAME_PLACE_ID, playersToReturn)
				end)
			end
			return
		end

		if winnerPlayer and winnerPlayer.Character then
			self:ResetCombatState(winnerPlayer)
			self:ReturnToMainMap(winnerPlayer)
		elseif getTargetCharacter(winner) then
			self:ResetDummyState(getTargetCharacter(winner))
			self:ReturnToMainMap(winner)
		end

		if loserPlayer then
			if loserPlayer.Character and getHumanoid(loserPlayer.Character) and getHumanoid(loserPlayer.Character).Health > 0 then
				self:ResetCombatState(loserPlayer)
				self:ReturnToMainMap(loserPlayer)
			end
		elseif getTargetCharacter(loser) then
			self:ResetDummyState(getTargetCharacter(loser))
			self:ReturnToMainMap(loser)
		end
	end)
end

function CombatService:HandleCharacterDeath(player)
	self:DestroyActiveBlasters(player)
	self:InvalidatePendingAbilityCasts(self:GetState(player))
	self:ClearNaoyaFrameMarks(player.Character)
	self:ClearNaoyaFrozenState(player.Character)
	self:ClearSamuraiBleedMarks(player.Character)
	self:ClearSamuraiBleedState(player.Character)
	local duel = self.ActiveDuels[player]
	if duel then
		local opponent = duel.A == player and duel.B or duel.A
		self:ResolveDuel(opponent, player)
		return
	end

	local character = player.Character
	local killerUserId = character and character:GetAttribute("LastDamagedByUserId")
	if killerUserId then
		local killer = Players:GetPlayerByUserId(killerUserId)
		if killer and killer ~= player then
			self:AddDeath(player, 1)
			self:AddKill(killer, 1)
			self:SendMessage(killer, string.format("You defeated %s.", player.DisplayName))
		end
	end

	if not self:IsRankedMatchServer() then
		player:SetAttribute(Constants.AWAITING_CHARACTER_ATTRIBUTE, true)
	end
end

function CombatService:ResetCombatState(player)
	local state = self:GetState(player)
	local character = player.Character
	local humanoid = getHumanoid(character)
	local root = getCharacterRoot(character)
	local kit = self:GetKit(player)
	if not state or not character or not humanoid or not root or not kit then
		return false
	end
	local buffs = state.Buffs or {}
	self:ClearNaoyaFrameMarks(character)
	self:ClearNaoyaFrozenState(character)
	self:ClearSamuraiBleedMarks(character)
	self:ClearSamuraiBleedState(character)

	state.LastM1At = 0
	state.ComboStep = 0
	state.M1CooldownUntil = 0
	state.Cooldowns = {}
	state.AbilityBurstCounts = {}
	state.AbilityHoldStates = {}
	self:InvalidatePendingAbilityCasts(state)
	state.CastLockUntil = 0
	state.IsBlocking = false
	state.IsStunnedUntil = 0
	state.LastDashAt = 0
	state.CounterUntil = 0
	state.IFrameUntil = 0
	self:DestroyActiveBlasters(player, state)
	self:ResetTelekinesisState(state)
	state.LastBlockEndedAt = 0
	state.PerfectBlockUntil = 0

	if state.BlockAura then
		self.Effects:DestroyBlockAura(state.BlockAura)
		state.BlockAura = nil
	end

	local maxHealth = buffs.Health or kit.Stats.Health
	if kit.DisplayName == "Sans" then
		maxHealth = self:GetSansDodgeCapacity(player, kit)
	end
	humanoid.MaxHealth = maxHealth
	humanoid.Health = maxHealth
	humanoid.WalkSpeed = tonumber(kit.Stats and kit.Stats.WalkSpeed) or Constants.DEFAULT_WALKSPEED
	root.AssemblyLinearVelocity = Vector3.zero
	root.AssemblyAngularVelocity = Vector3.zero

	character:SetAttribute("Blocking", false)
	character:SetAttribute("BlockName", "")
	character:SetAttribute("Stunned", false)
	character:SetAttribute("InCombat", false)
	character:SetAttribute("Mana", buffs.Mana or kit.Stats.Mana or 0)
	character:SetAttribute("Stamina", buffs.Stamina or kit.Stats.Stamina or 0)
	character:SetAttribute("Attack", buffs.Attack or kit.Stats.Attack or 0)
	character:SetAttribute("Defense", buffs.Defense or kit.Stats.Defense or 0)
	character:SetAttribute("MaxDodge", kit.DisplayName == "Sans" and maxHealth or 0)
	character:SetAttribute("Dodge", kit.DisplayName == "Sans" and maxHealth or 0)
	character:SetAttribute("Dodging", false)
	character:SetAttribute("DodgeDirection", "")
	character:SetAttribute("DodgeNonce", 0)
	character:SetAttribute("ActiveBlasters", 0)
	character:SetAttribute("PendingBlasterShots", 0)
	character:SetAttribute("NaoyaFrameMarks", 0)
	character:SetAttribute("NaoyaFrozen", false)
	character:SetAttribute("SamuraiBleedMarks", 0)
	character:SetAttribute("SamuraiBleeding", false)

	return true
end

function CombatService:ResetDummyState(dummy)
	local humanoid = getHumanoid(dummy)
	local root = getCharacterRoot(dummy)
	if not humanoid or not root then
		return false
	end

	self:ClearNaoyaFrameMarks(dummy)
	self:ClearNaoyaFrozenState(dummy)
	self:ClearSamuraiBleedMarks(dummy)
	self:ClearSamuraiBleedState(dummy)
	humanoid.MaxHealth = 400
	humanoid.Health = humanoid.MaxHealth
	humanoid.WalkSpeed = 0
	root.AssemblyLinearVelocity = Vector3.zero
	root.AssemblyAngularVelocity = Vector3.zero
	dummy:SetAttribute("Stunned", false)
	dummy:SetAttribute("Blocking", dummy:GetAttribute("DummyBehavior") == "Blocking" or dummy:GetAttribute("DummyBehavior") == "PerfectBlocking")
	dummy:SetAttribute("NaoyaFrameMarks", 0)
	dummy:SetAttribute("NaoyaFrozen", false)
	dummy:SetAttribute("SamuraiBleedMarks", 0)
	dummy:SetAttribute("SamuraiBleeding", false)

	return true
end

function CombatService:StartOneVOne(challenger, opponent, options)
	options = options or {}
	local challengerCharacter = challenger.Character
	local opponentCharacter = getTargetCharacter(opponent)
	local challengerRoot = getCharacterRoot(challengerCharacter)
	local opponentRoot = getCharacterRoot(opponentCharacter)
	local challengerHumanoid = getHumanoid(challengerCharacter)
	local opponentHumanoid = getHumanoid(opponentCharacter)
	local duelFolder = getDuelSpawnFolder()
	local spawnA = duelFolder and duelFolder:FindFirstChild("SpawnA")
	local spawnB = duelFolder and duelFolder:FindFirstChild("SpawnB")
	local opponentPlayer = getTargetPlayer(opponent)
	local opponentName = opponentPlayer and opponentPlayer.DisplayName or (opponentCharacter and (opponentCharacter:GetAttribute("DisplayName") or opponentCharacter.Name)) or "Opponent"
	local modeName = options.ModeName or "1v1"

	if not challengerRoot or not opponentRoot or not challengerHumanoid or not opponentHumanoid then
		self:SendMessage(challenger, "Both fighters need active characters for /1v1.")
		return
	end

	if challengerHumanoid.Health <= 0 or opponentHumanoid.Health <= 0 then
		self:SendMessage(challenger, "Both fighters must be alive for /1v1.")
		return
	end

	if not spawnA or not spawnB then
		self:SendMessage(challenger, "Duel spawns are missing.")
		return
	end

	self:LeaveRankedQueue(challenger, true)
	if opponentPlayer then
		self:LeaveRankedQueue(opponentPlayer, true)
	end

	self.ActiveDuels[challenger] = {
		A = challenger,
		B = opponent,
		StartedAt = now(),
		Resolved = false,
		IsRanked = options.IsRanked == true,
		ModeName = modeName,
	}
	self.ActiveDuels[opponent] = self.ActiveDuels[challenger]

	self:ResetCombatState(challenger)
	if opponentPlayer then
		self:ResetCombatState(opponentPlayer)
	else
		self:ResetDummyState(opponentCharacter)
	end

	for count = Constants.DUEL_COUNTDOWN, 1, -1 do
		self.Remotes.CombatState:FireClient(challenger, {
			Type = "DuelCountdown",
			Value = count,
			Opponent = opponentName,
			Mode = modeName,
		})
		if opponentPlayer then
			self.Remotes.CombatState:FireClient(opponentPlayer, {
				Type = "DuelCountdown",
				Value = count,
				Opponent = challenger.DisplayName,
				Mode = modeName,
			})
		end
		task.wait(1)
	end

	challengerRoot.CFrame = spawnA.CFrame + Vector3.new(0, 3, 0)
	opponentRoot.CFrame = spawnB.CFrame + Vector3.new(0, 3, 0)

	self:SendMessage(challenger, string.format("Starting %s with %s.", modeName, opponentName))
	if opponentPlayer then
		self:SendMessage(opponentPlayer, string.format("%s started a %s with you.", challenger.DisplayName, modeName))
	end
end

function CombatService:RequestOneVOne(challenger, target)
	if self:IsTrainingServer() then
		self:SendMessage(challenger, "Player duels are disabled in the training server.")
		return
	end

	if self.ActiveDuels[challenger] or self.ActiveDuels[target] then
		self:SendMessage(challenger, "One of the fighters is already in a duel.")
		return
	end

	if self.PendingDuelRequests[target] then
		self:SendMessage(challenger, "That player already has a pending duel request.")
		return
	end

	self.PendingDuelRequests[target] = {
		From = challenger,
		CreatedAt = now(),
	}

	self.Remotes.CombatState:FireClient(target, {
		Type = "DuelRequested",
		From = challenger.DisplayName,
		Timeout = Constants.DUEL_REQUEST_TIMEOUT,
	})
	self:SendMessage(challenger, string.format("Sent 1v1 request to %s.", target.DisplayName))

	task.delay(Constants.DUEL_REQUEST_TIMEOUT, function()
		local request = self.PendingDuelRequests[target]
		if request and request.From == challenger then
			self.PendingDuelRequests[target] = nil
			self:SendMessage(challenger, "Duel request expired.")
			self:SendMessage(target, "Duel request expired.")
		end
	end)
end

function CombatService:RespondToDuelRequest(player, accepted)
	local request = self.PendingDuelRequests[player]
	if not request then
		self:SendMessage(player, "No duel request is pending.")
		return
	end

	self.PendingDuelRequests[player] = nil
	local challenger = request.From
	if not challenger or not challenger.Parent then
		self:SendMessage(player, "That duel requester is no longer available.")
		return
	end

	if not accepted then
		self:SendMessage(player, "Duel declined.")
		self:SendMessage(challenger, string.format("%s declined your duel.", player.DisplayName))
		return
	end

	self:SendMessage(player, "Duel accepted.")
	self:SendMessage(challenger, string.format("%s accepted your duel.", player.DisplayName))
	self:StartOneVOne(challenger, player)
end

function CombatService:HandleAdminCommand(player, command, args)
	if not isAdminUserId(player.UserId) then
		self:SendMessage(player, "You are not allowed to use admin commands.")
		return true
	end

	if command == "setkills" then
		local target = self:FindPlayerByText(player, args[1] or "")
		local amount = tonumber(args[2])
		if not target or not amount then
			self:SendMessage(player, "Usage: /setkills <player> <amount>")
			return true
		end
		local profile = self:GetProfile(target)
		if profile then
			profile.Kills = math.max(0, math.floor(amount))
			self:SaveProfile(target)
			self:SendProfile(target)
			self:SendMessage(player, string.format("%s kills set to %d.", target.DisplayName, profile.Kills))
		end
		return true
	elseif command == "setdeaths" then
		local target = self:FindPlayerByText(player, args[1] or "")
		local amount = tonumber(args[2])
		if not target or not amount then
			self:SendMessage(player, "Usage: /setdeaths <player> <amount>")
			return true
		end
		local profile = self:GetProfile(target)
		if profile then
			profile.Deaths = math.max(0, math.floor(amount))
			self:SaveProfile(target)
			self:SendProfile(target)
			self:SendMessage(player, string.format("%s deaths set to %d.", target.DisplayName, profile.Deaths))
		end
		return true
	elseif command == "setrating" then
		local target = self:FindPlayerByText(player, args[1] or "")
		local amount = tonumber(args[2])
		if not target or not amount then
			self:SendMessage(player, "Usage: /setrating <player> <amount>")
			return true
		end
		local profile = self:GetProfile(target)
		if profile then
			profile.RankedRating = math.max(0, math.floor(amount))
			self:SaveProfile(target)
			self:SendProfile(target)
			self:SendMessage(player, string.format("%s rating set to %d.", target.DisplayName, profile.RankedRating))
		end
		return true
	elseif command == "buff" then
		local target = self:FindPlayerByText(player, args[1] or "")
		local statName = args[2]
		local amount = tonumber(args[3])
		local allowed = {Attack = true, Defense = true, Health = true, Mana = true, Stamina = true}
		if not target or not statName or not amount or not allowed[statName] then
			self:SendMessage(player, "Usage: /buff <player> <Attack|Defense|Health|Mana|Stamina> <amount>")
			return true
		end
		local kit = self:GetKit(target)
		local character = target.Character
		local humanoid = getHumanoid(character)
		local targetState = self:GetState(target)
		if not kit or not character then
			self:SendMessage(player, "Target is not ready.")
			return true
		end
		targetState.Buffs = targetState.Buffs or {}
		targetState.Buffs[statName] = math.max(0, math.floor(amount))

		if statName == "Health" and humanoid then
			humanoid.MaxHealth = math.max(1, math.floor(amount))
			humanoid.Health = humanoid.MaxHealth
		else
			character:SetAttribute(statName, math.max(0, math.floor(amount)))
		end
		self:SendMessage(player, string.format("%s %s set to %d.", target.DisplayName, statName, amount))
		return true
	elseif command == "theme" then
		local themeText = table.concat(args, " ")
		local normalizedThemeText = normalizeLookupText(themeText)
		if normalizedThemeText == "" then
			self:SendMessage(player, "Usage: /theme <character|off|list>")
			return true
		end

		if normalizedThemeText == "off" or normalizedThemeText == "stop" or normalizedThemeText == "clear" then
			self.GlobalMusicOverride = nil
			self:BroadcastGlobalMusicOverride()
			self:SendMessage(player, "Global theme override cleared.")
			return true
		end

		if normalizedThemeText == "list" then
			local availableThemes = {}
			for kitId, kit in pairs(CharacterKits) do
				local soundId = tonumber((Constants.CHARACTER_THEME_IDS or {})[kitId]) or 0
				if soundId ~= 0 then
					table.insert(availableThemes, (kit and kit.DisplayName) or kitId)
				end
			end
			table.sort(availableThemes)
			if #availableThemes == 0 then
				self:SendMessage(player, "No character themes are configured yet.")
			else
				self:SendMessage(player, "Configured themes: " .. table.concat(availableThemes, ", "))
			end
			return true
		end

		local themeInfo = self:ResolveCharacterTheme(themeText)
		if not themeInfo then
			self:SendMessage(player, "Character not found. Use /theme <character|off|list>.")
			return true
		end
		if not themeInfo.SoundId or themeInfo.SoundId == 0 then
			self:SendMessage(player, string.format("No theme is configured for %s yet.", themeInfo.DisplayName))
			return true
		end

		self.GlobalMusicOverride = {
			ThemeKey = themeInfo.KitId,
			ThemeName = themeInfo.DisplayName,
			SoundId = themeInfo.SoundId,
			SongName = themeInfo.SongName,
			CreatorName = themeInfo.CreatorName,
		}
		self:BroadcastGlobalMusicOverride()
		self:SendMessage(player, string.format("Now playing %s's theme globally.", themeInfo.DisplayName))
		return true
	end

	return false
end

function CombatService:HandleChatCommand(player, message)
	if type(message) ~= "string" then
		return
	end

	local lowerMessage = string.lower(message)
	local command, rest = string.match(lowerMessage, "^/(%S+)%s*(.*)$")
	if not command then
		return
	end

	local originalRest = string.match(message, "^/%S+%s*(.*)$") or ""
	local args = {}
	for token in string.gmatch(originalRest, "%S+") do
		table.insert(args, token)
	end

	if command == "accept" then
		self:RespondToDuelRequest(player, true)
		return
	elseif command == "decline" then
		self:RespondToDuelRequest(player, false)
		return
	elseif command == "ranked" then
		self:QueueForRanked(player)
		return
	elseif command == "unranked" then
		self:LeaveRankedQueue(player, false)
		return
	elseif command == "rankedstats" then
		local rating, wins, losses = self:GetRankedStats(player)
		self:SendMessage(player, string.format("Ranked: %s | Rating: %d | W: %d | L: %d", Constants.GetRankTierName(rating), rating, wins, losses))
		return
	elseif self:HandleAdminCommand(player, command, args) then
		return
	end

	if command ~= "1v1" then
		return
	end

	local targetText = originalRest
	if targetText == "" then
		self:SendMessage(player, "Use /1v1 <player> or /1v1 dummy.")
		return
	end

	if string.lower(targetText) == "dummy" then
		local dummy = self:FindDuelDummy()
		if not dummy then
			self:SendMessage(player, "No dummy is available for /1v1 dummy.")
			return
		end
		self:StartOneVOne(player, dummy)
		return
	end

	local targetPlayer = self:FindPlayerByText(player, targetText)
	if not targetPlayer then
		self:SendMessage(player, "Player not found. Use /1v1 <player> or /1v1 dummy.")
		return
	end

	self:RequestOneVOne(player, targetPlayer)
end

function CombatService:CycleMode(player, direction)
	local state = self:GetState(player)
	local kit = self:GetKit(player)
	if not state or not kit or not kit.Modes then
		return
	end

	local currentIndex = table.find(kit.Modes, state.Mode) or 1
	local step = direction == "Previous" and -1 or 1
	local nextIndex = ((currentIndex - 1 + step) % #kit.Modes) + 1
	state.Mode = kit.Modes[nextIndex]
	state.AbilityBurstCounts = {}
	state.AbilityHoldStates = {}
	self:InvalidatePendingAbilityCasts(state)
	self:DestroyActiveBlasters(player, state)
	self:ResetTelekinesisState(state)
	setCharacterAttribute(player, "Mode", state.Mode)

	self.Remotes.CombatState:FireClient(player, {
		Type = "ModeChanged",
		Mode = state.Mode,
	})
end

function CombatService:SetBlocking(player, isBlocking)
	local state = self:GetState(player)
	local character = player.Character
	local humanoid = getHumanoid(character)
	if not state or not character or not humanoid then
		return
	end

	if isBlocking and (self:IsActionLocked(player) or (state.CastLockUntil or 0) > now()) then
		return
	end

	if isBlocking and state.IsBlocking then
		return
	end

	if not isBlocking and not state.IsBlocking then
		return
	end

	if isBlocking and now() - state.LastBlockEndedAt < Constants.BLOCK_COOLDOWN then
		return
	end

	state.IsBlocking = isBlocking
	state.PerfectBlockUntil = isBlocking and (now() + (Constants.PERFECT_BLOCK_WINDOW or 0)) or 0
	character:SetAttribute("Blocking", isBlocking)
	character:SetAttribute("BlockName", isBlocking and (self:GetKit(player).Block.Name or "Block") or "")

	if isBlocking then
		local root = getCharacterRoot(character)
		if root then
			local preserveVerticalMomentum = shouldPreserveAirMomentum(humanoid, root)
			root.AssemblyLinearVelocity = preserveVerticalMomentum
				and Vector3.new(0, root.AssemblyLinearVelocity.Y, 0)
				or Vector3.zero
			root.AssemblyAngularVelocity = Vector3.zero
			if state.BlockAura then
				self.Effects:DestroyBlockAura(state.BlockAura)
			end
			local blockColor = self:GetKit(player).DisplayName == "Sans" and self:GetSansEffectPalette(player).Block or Color3.fromRGB(245, 245, 255)
			state.BlockAura = self.Effects:CreateBlockAura(root, blockColor)
		end
	else
		state.LastBlockEndedAt = now()
		if state.BlockAura then
			self.Effects:DestroyBlockAura(state.BlockAura)
			state.BlockAura = nil
		end
	end

	if isBlocking and self:GetKit(player).DisplayName == "Sans" then
		local root = getCharacterRoot(character)
		if root then
			local palette = self:GetSansEffectPalette(player)
			local blasterTemplates = self:GetSansBlasterTemplateNames(player)
			if state.Mode == "Blasters" then
				self.Effects:SpawnBlaster(
					root.Position
						+ root.CFrame.RightVector * 1.9
						+ root.CFrame.LookVector * 1.3
						+ Vector3.new(0, 3, 0),
					palette.Beam,
					blasterTemplates
				)
			else
				self.Effects:SpawnBlockWall(root, palette.White)
			end
		end
	end

	self:RefreshMovementState(player)

end

function CombatService:ApplyStun(player, duration, options)
	options = options or {}
	local targetPlayer = getTargetPlayer(player)
	local character = getTargetCharacter(player)
	if not character then
		return
	end

	if targetPlayer then
		local state = self:GetState(targetPlayer)
		if not state then
			return
		end
		self:SetBlocking(targetPlayer, false)
		self:DestroyActiveBlasters(targetPlayer, state)
		state.IsStunnedUntil = math.max(state.IsStunnedUntil, now() + duration)
		local root = getCharacterRoot(character)
		if root and not options.PreserveMomentum then
			root.AssemblyLinearVelocity = Vector3.zero
			root.AssemblyAngularVelocity = Vector3.zero
		end
		character:SetAttribute("Stunned", true)
		self:RefreshMovementState(targetPlayer, {PreserveMomentum = options.PreserveMomentum})

		task.delay(duration, function()
			if self.PlayerState[targetPlayer] and targetPlayer.Character and self.PlayerState[targetPlayer].IsStunnedUntil <= now() then
				targetPlayer.Character:SetAttribute("Stunned", false)
				self:RefreshMovementState(targetPlayer)
			end
		end)
		return
	end

	local humanoid = getHumanoid(character)
	if not humanoid then
		return
	end

	local originalSpeed = humanoid.WalkSpeed
	humanoid.WalkSpeed = 0
	task.delay(duration, function()
		if humanoid.Parent and humanoid.Health > 0 then
			humanoid.WalkSpeed = originalSpeed
		end
	end)
end

function CombatService:ClearKnockbackAnimationState(character)
	local state = self.ActiveKnockbackAnimations[character]
	if character and character.Parent then
		character:SetAttribute("KnockbackLocked", false)
	end
	if not state then
		return
	end

	self.ActiveKnockbackAnimations[character] = nil
	if state.Connection then
		state.Connection:Disconnect()
	end
	if state.AirTrack then
		pcall(function()
			if state.AirTrack.IsPlaying then
				state.AirTrack:Stop(0.08)
			end
		end)
	end
	if state.SlideTrack then
		pcall(function()
			if state.SlideTrack.IsPlaying then
				state.SlideTrack:Stop(0.05)
			end
			state.SlideTrack:Destroy()
		end)
	end
	if state.SlideAnimation then
		state.SlideAnimation:Destroy()
	end
	if state.SlideVelocity then
		state.SlideVelocity:Destroy()
	end
	if state.FacingLock then
		state.FacingLock:Destroy()
	end
	local root = getCharacterRoot(character)
	if root then
		pcall(function()
			root:SetNetworkOwnershipAuto()
		end)
	end
	local humanoid = getHumanoid(character)
	if humanoid then
		humanoid.Jump = false
		humanoid.AutoRotate = true
	end
	local targetPlayer = getTargetPlayer(character)
	if targetPlayer then
		self:RefreshMovementState(targetPlayer)
	elseif humanoid then
		humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, true)
	end
end

function CombatService:GetKnockbackSlideDuration(target)
	local fullDuration = Constants.KNOCKBACK_SLIDE_DURATION_FULL_MANA or 2
	local emptyDuration = math.max(fullDuration, Constants.KNOCKBACK_SLIDE_DURATION_EMPTY_MANA or 4)
	local targetPlayer = getTargetPlayer(target)
	local targetCharacter = getTargetCharacter(target)
	if not targetPlayer or not targetCharacter then
		return fullDuration
	end

	local kit = self:GetKit(targetPlayer)
	local maxMana = tonumber(kit and kit.Stats and kit.Stats.Mana) or 0
	if maxMana <= 0 then
		return fullDuration
	end

	local currentMana = math.clamp(tonumber(targetCharacter:GetAttribute("Mana")) or maxMana, 0, maxMana)
	local manaRatio = math.clamp(currentMana / maxMana, 0, 1)
	return fullDuration + ((1 - manaRatio) * (emptyDuration - fullDuration))
end

function CombatService:PlayKnockbackAnimations(target, horizontalVelocity)
	local targetCharacter = getTargetCharacter(target)
	local humanoid = getHumanoid(targetCharacter)
	local root = getCharacterRoot(targetCharacter)
	local airAnimationId = Constants.KNOCKBACK_AIR_ANIMATION_ID or 0
	local slideAnimationId = Constants.KNOCKBACK_SLIDE_ANIMATION_ID or 0
	if not targetCharacter or not humanoid or humanoid.Health <= 0 or not root then
		return
	end
	if airAnimationId == 0 and slideAnimationId == 0 then
		return
	end

	self:ClearKnockbackAnimationState(targetCharacter)

	local state = {}
	self.ActiveKnockbackAnimations[targetCharacter] = state
	targetCharacter:SetAttribute("KnockbackLocked", true)
	humanoid.AutoRotate = false
	humanoid.Jump = false
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, false)
	pcall(function()
		root:SetNetworkOwner(nil)
	end)
	local flatLook = Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z)
	if flatLook.Magnitude <= 0.001 then
		flatLook = Vector3.zAxis
	end
	local facingLock = Instance.new("BodyGyro")
	facingLock.Name = "KnockbackFacingLock"
	facingLock.MaxTorque = Vector3.new(0, 1, 0) * 500000
	facingLock.P = 30000
	facingLock.D = 1200
	facingLock.CFrame = CFrame.lookAt(root.Position, root.Position + flatLook.Unit)
	facingLock.Parent = root
	state.FacingLock = facingLock
	state.HorizontalVelocity = Vector3.new(horizontalVelocity and horizontalVelocity.X or 0, 0, horizontalVelocity and horizontalVelocity.Z or 0)
	state.AirTrack = playActionAnimation(targetCharacter, airAnimationId, {
		Priority = Enum.AnimationPriority.Action4,
		Looped = true,
		FadeTime = 0.05,
	})
	state.SlideTrack, state.SlideAnimation = createActionTrack(targetCharacter, slideAnimationId, {
		Priority = Enum.AnimationPriority.Action4,
	})
	state.Connection = humanoid.Died:Connect(function()
		self:ClearKnockbackAnimationState(targetCharacter)
	end)

	local minLandingAt = now() + (Constants.KNOCKBACK_LANDING_MIN_TIME or 0.16)
	local timeoutAt = now() + (Constants.KNOCKBACK_LANDING_TIMEOUT or 2.1)
	task.spawn(function()
		while self.ActiveKnockbackAnimations[targetCharacter] == state and targetCharacter.Parent and humanoid.Health > 0 and now() < timeoutAt do
			if humanoid.FloorMaterial == Enum.Material.Air then
				state.HasBeenAirborne = true
			end

			local grounded = humanoid.FloorMaterial ~= Enum.Material.Air
			if now() >= minLandingAt and state.HasBeenAirborne and grounded then
				local slideDuration = self:GetKnockbackSlideDuration(target)
				local slideDirection = state.HorizontalVelocity.Magnitude > 0.001 and state.HorizontalVelocity.Unit or Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z).Unit
				local slideSpeed = math.clamp(
					state.HorizontalVelocity.Magnitude * (Constants.KNOCKBACK_SLIDE_SPEED_SCALE or 0.35),
					Constants.KNOCKBACK_SLIDE_SPEED_MIN or 8,
					Constants.KNOCKBACK_SLIDE_SPEED_MAX or 24
				)
				if slideDirection.Magnitude > 0.001 and slideSpeed > 0 then
					local slideVelocity = Instance.new("BodyVelocity")
					slideVelocity.Name = "CombatSlideKnockback"
					slideVelocity.MaxForce = Vector3.new(1, 0, 1) * math.max(30000, math.floor((Constants.KNOCKBACK_FORCE or 70000) * 0.6))
					slideVelocity.Parent = root
					state.SlideVelocity = slideVelocity
					if self.Effects and self.Effects.CreateGroundSlideTrail then
						state.SlideTrail = self.Effects:CreateGroundSlideTrail(root, slideDuration)
					end
					task.spawn(function()
						local startAt = now()
						while self.ActiveKnockbackAnimations[targetCharacter] == state and state.SlideVelocity == slideVelocity and targetCharacter.Parent and humanoid.Health > 0 do
							local alpha = math.clamp((now() - startAt) / slideDuration, 0, 1)
							slideVelocity.Velocity = slideDirection * (slideSpeed * (1 - alpha))
							if alpha >= 1 then
								break
							end
							task.wait(0.02)
						end
					end)
				end
				if state.AirTrack then
					local airTrack = state.AirTrack
					task.delay(0.08, function()
						if self.ActiveKnockbackAnimations[targetCharacter] ~= state or state.AirTrack ~= airTrack then
							return
						end
						pcall(function()
							if airTrack.IsPlaying then
								airTrack:Stop(0.12)
							end
						end)
					end)
				end
				if state.SlideTrack then
					pcall(function()
						state.SlideTrack:Play(0.03)
					end)
					task.spawn(function()
						local track = state.SlideTrack
						local waitDeadline = now() + 0.5
						while self.ActiveKnockbackAnimations[targetCharacter] == state and state.SlideTrack == track and track.Length <= 0 and now() < waitDeadline do
							task.wait()
						end
						if self.ActiveKnockbackAnimations[targetCharacter] ~= state or state.SlideTrack ~= track then
							return
						end
						if track.Length > 0 then
							track:AdjustSpeed(math.clamp(track.Length / slideDuration, 0.08, 3))
						end
					end)
				end
				task.delay(slideDuration, function()
					if self.ActiveKnockbackAnimations[targetCharacter] == state then
						self:ClearKnockbackAnimationState(targetCharacter)
					end
				end)
				return
			end
			task.wait(0.02)
		end

		if self.ActiveKnockbackAnimations[targetCharacter] == state then
			self:ClearKnockbackAnimationState(targetCharacter)
		end
	end)
end

function CombatService:ApplyKnockback(attacker, target, knockback, launch)
	if knockback <= 0 then
		return
	end

	local attackerRoot = getCharacterRoot(getTargetCharacter(attacker))
	local targetRoot = getCharacterRoot(getTargetCharacter(target))
	if not attackerRoot or not targetRoot then
		return
	end

	local direction = targetRoot.Position - attackerRoot.Position
	if direction.Magnitude < 0.001 then
		direction = attackerRoot.CFrame.LookVector
	end

	local horizontalVelocity = direction.Unit * knockback
	local verticalScale = launch and (Constants.KNOCKBACK_LAUNCH_VERTICAL_SCALE or 0.45) or (Constants.KNOCKBACK_VERTICAL_SCALE or 0.18)
	local verticalVelocity = math.min(knockback * verticalScale, Constants.KNOCKBACK_VERTICAL_CAP or 32)
	local durationAlpha = math.clamp(knockback / 40, 0, 1)
	local duration = (Constants.KNOCKBACK_DURATION_MIN or 0.08)
		+ ((Constants.KNOCKBACK_DURATION_MAX or 0.22) - (Constants.KNOCKBACK_DURATION_MIN or 0.08)) * durationAlpha
	local existingKnockback = targetRoot:FindFirstChild("CombatKnockback")
	if existingKnockback then
		existingKnockback:Destroy()
	end

	targetRoot.AssemblyLinearVelocity = Vector3.zero
	targetRoot.AssemblyAngularVelocity = Vector3.zero

	local velocity = Instance.new("BodyVelocity")
	velocity.Name = "CombatKnockback"
	velocity.MaxForce = Vector3.new(1, 1, 1) * (Constants.KNOCKBACK_FORCE or 70000)
	velocity.Velocity = horizontalVelocity + Vector3.new(0, verticalVelocity, 0)
	velocity.Parent = targetRoot
	Debris:AddItem(velocity, duration)

	if launch then
		self:PlayKnockbackAnimations(target, horizontalVelocity)
	end
end

function CombatService:ClearNaoyaFrameMarks(target)
	local targetCharacter = getTargetCharacter(target)
	if not targetCharacter then
		return
	end

	self.NaoyaFrameMarks[targetCharacter] = nil
	targetCharacter:SetAttribute("NaoyaFrameMarks", 0)
end

function CombatService:ClearNaoyaFrozenState(target)
	local targetCharacter = getTargetCharacter(target)
	if not targetCharacter then
		return
	end

	targetCharacter:SetAttribute("NaoyaFrozen", false)
end

function CombatService:GetNaoyaFrameMarkState(target)
	local targetCharacter = getTargetCharacter(target)
	if not targetCharacter then
		return nil, nil
	end

	self.NaoyaFrameMarks = self.NaoyaFrameMarks or {}
	local state = self.NaoyaFrameMarks[targetCharacter]
	if state and (state.ExpiresAt or 0) <= now() then
		self:ClearNaoyaFrameMarks(targetCharacter)
		state = nil
	end

	return state, targetCharacter
end

function CombatService:ApplyNaoyaFrameMarks(attacker, target, stacks)
	local targetCharacter = getTargetCharacter(target)
	if not targetCharacter or (targetCharacter:GetAttribute("Blocking") == true) then
		return 0
	end

	self.NaoyaFrameMarks = self.NaoyaFrameMarks or {}
	local currentState = self.NaoyaFrameMarks[targetCharacter]
	if currentState and (currentState.ExpiresAt or 0) <= now() then
		currentState = nil
	end

	local nextCount = math.clamp((currentState and currentState.Count or 0) + (stacks or 1), 0, Constants.NAOYA_FRAME_MARK_MAX or 3)
	local expiresAt = now() + (Constants.NAOYA_FRAME_MARK_DURATION or 3)
	self.NaoyaFrameMarks[targetCharacter] = {
		Count = nextCount,
		ExpiresAt = expiresAt,
	}
	targetCharacter:SetAttribute("NaoyaFrameMarks", nextCount)

	task.delay(Constants.NAOYA_FRAME_MARK_DURATION or 3, function()
		local latestState = self.NaoyaFrameMarks[targetCharacter]
		if latestState and latestState.ExpiresAt <= now() then
			self:ClearNaoyaFrameMarks(targetCharacter)
		end
	end)

	return nextCount
end

function CombatService:ApplyNaoyaFrameFreeze(target, duration)
	local targetCharacter = getTargetCharacter(target)
	if not targetCharacter then
		return
	end

	targetCharacter:SetAttribute("NaoyaFrozen", true)
	self:ApplyStun(target, duration)
	task.delay(duration, function()
		if targetCharacter.Parent then
			targetCharacter:SetAttribute("NaoyaFrozen", false)
		end
	end)
end

function CombatService:TryTriggerNaoyaFrameFreeze(attacker, target)
	local markState, targetCharacter = self:GetNaoyaFrameMarkState(target)
	if not markState or not targetCharacter or targetCharacter:GetAttribute("Blocking") == true or (markState.Count or 0) < (Constants.NAOYA_FRAME_MARK_MAX or 3) then
		return false
	end

	self:ClearNaoyaFrameMarks(targetCharacter)
	self:ApplyNaoyaFrameFreeze(target, Constants.NAOYA_FRAME_FREEZE_DURATION or 0.9)
	self:MarkInCombat(attacker)
	local attackerPlayer = getTargetPlayer(attacker)
	if attackerPlayer then
		self:SendMessage(attackerPlayer, "Frame freeze confirmed.")
	end

	return true
end

function CombatService:ClearSamuraiBleedMarks(target)
	local targetCharacter = getTargetCharacter(target)
	if not targetCharacter then
		return
	end

	self.SamuraiBleedMarks = self.SamuraiBleedMarks or {}
	self.SamuraiBleedMarks[targetCharacter] = nil
	targetCharacter:SetAttribute("SamuraiBleedMarks", 0)
end

function CombatService:ClearSamuraiBleedState(target)
	local targetCharacter = getTargetCharacter(target)
	if not targetCharacter then
		return
	end

	self.ActiveSamuraiBleeds = self.ActiveSamuraiBleeds or {}
	self.ActiveSamuraiBleeds[targetCharacter] = nil
	targetCharacter:SetAttribute("SamuraiBleeding", false)
end

function CombatService:GetSamuraiBleedMarkState(target)
	local targetCharacter = getTargetCharacter(target)
	if not targetCharacter then
		return nil, nil
	end

	self.SamuraiBleedMarks = self.SamuraiBleedMarks or {}
	local state = self.SamuraiBleedMarks[targetCharacter]
	if state and (state.ExpiresAt or 0) <= now() then
		self:ClearSamuraiBleedMarks(targetCharacter)
		state = nil
	end

	return state, targetCharacter
end

function CombatService:ApplySamuraiBleedMarks(attacker, target, stacks)
	local targetCharacter = getTargetCharacter(target)
	if not targetCharacter or (targetCharacter:GetAttribute("Blocking") == true) then
		return 0
	end

	self.SamuraiBleedMarks = self.SamuraiBleedMarks or {}
	local currentState = self.SamuraiBleedMarks[targetCharacter]
	if currentState and (currentState.ExpiresAt or 0) <= now() then
		currentState = nil
	end

	local nextCount = math.clamp((currentState and currentState.Count or 0) + (stacks or 1), 0, Constants.SAMURAI_BLEED_MARK_MAX or 3)
	local expiresAt = now() + (Constants.SAMURAI_BLEED_MARK_DURATION or 10)
	self.SamuraiBleedMarks[targetCharacter] = {
		Count = nextCount,
		ExpiresAt = expiresAt,
	}
	targetCharacter:SetAttribute("SamuraiBleedMarks", nextCount)

	task.delay(Constants.SAMURAI_BLEED_MARK_DURATION or 10, function()
		local latestState = self.SamuraiBleedMarks[targetCharacter]
		if latestState and latestState.ExpiresAt <= now() then
			self:ClearSamuraiBleedMarks(targetCharacter)
		end
	end)

	return nextCount
end

function CombatService:ApplySamuraiBleed(attacker, target, markCount)
	local targetCharacter = getTargetCharacter(target)
	if not targetCharacter then
		return false
	end

	self.ActiveSamuraiBleeds = self.ActiveSamuraiBleeds or {}
	local tickInterval = Constants.SAMURAI_BLEED_TICK_INTERVAL or 0.5
	local damagePerTick = Constants.SAMURAI_BLEED_DAMAGE_PER_TICK or 2
	local totalTicks = math.max(1, math.floor(((markCount or 1) * (Constants.SAMURAI_BLEED_TICKS_PER_MARK or 2.5)) + 0.5))
	local currentToken = (self.ActiveSamuraiBleeds[targetCharacter] and self.ActiveSamuraiBleeds[targetCharacter].Token or 0) + 1
	self.ActiveSamuraiBleeds[targetCharacter] = {
		Token = currentToken,
	}
	targetCharacter:SetAttribute("SamuraiBleeding", true)

	for tickIndex = 1, totalTicks do
		task.delay(tickIndex * tickInterval, function()
			local activeState = self.ActiveSamuraiBleeds[targetCharacter]
			if not activeState or activeState.Token ~= currentToken then
				return
			end
			if not targetCharacter.Parent then
				self:ClearSamuraiBleedState(targetCharacter)
				return
			end

			self:DamageTarget(attacker, targetCharacter, damagePerTick, 0, 0, {
				IgnoreBlock = true,
				NoKR = true,
				NoSansDodge = true,
			})

			if tickIndex >= totalTicks then
				self:ClearSamuraiBleedState(targetCharacter)
			end
		end)
	end

	return true
end

function CombatService:TryTriggerSamuraiBleed(attacker, target)
	local markState, targetCharacter = self:GetSamuraiBleedMarkState(target)
	if not markState or not targetCharacter or targetCharacter:GetAttribute("Blocking") == true or (markState.Count or 0) <= 0 then
		return false
	end

	local markCount = markState.Count or 0
	self:ClearSamuraiBleedMarks(targetCharacter)
	self:ApplySamuraiBleed(attacker, targetCharacter, markCount)
	self:MarkInCombat(attacker)
	return true
end

function CombatService:ApplyKarmicRetribution(attacker, target)
	local attackerKit = self:GetKit(attacker)
	local passive = attackerKit and attackerKit.Passive
	if not passive then
		return
	end

	local targetCharacter = getTargetCharacter(target)
	local targetPlayer = getTargetPlayer(target)
	local attackerPlayer = getTargetPlayer(attacker)
	local attackerUserId = attackerPlayer and attackerPlayer.UserId or nil
	if not targetCharacter then
		return
	end

	self.ActiveKarmicEffects = self.ActiveKarmicEffects or {}
	local attackerKey = attackerPlayer and attackerPlayer.UserId or 0
	self.ActiveKarmicEffects[attackerKey] = self.ActiveKarmicEffects[attackerKey] or {}
	local attackerEffects = self.ActiveKarmicEffects[attackerKey]
	local activeEffect = attackerEffects[targetCharacter]
	if activeEffect then
		activeEffect.RemainingTicks = passive.DotTicks
		return
	end

	local effectState = {
		RemainingTicks = passive.DotTicks,
	}
	attackerEffects[targetCharacter] = effectState

	task.spawn(function()
		while attackerEffects[targetCharacter] == effectState and effectState.RemainingTicks > 0 do
			task.wait(passive.DotInterval)
			local targetCharacter = getTargetCharacter(target)
			local targetPlayer = getTargetPlayer(target)
			local humanoid = getHumanoid(targetCharacter)
			if not humanoid or humanoid.Health <= 0 then
				break
			end

			local appliedDamage = self:ScaleDamage(attacker, targetCharacter, passive.DotDamage)
			local targetState = targetPlayer and self:GetState(targetPlayer)
			local targetKit = targetPlayer and self:GetKit(targetPlayer)
			local isBlocking = (targetState and targetState.IsBlocking) or (targetCharacter and targetCharacter:GetAttribute("Blocking"))
			if isBlocking then
				continue
			end

			if appliedDamage > 0 then
				if targetPlayer and targetKit and targetKit.DisplayName == "Sans" then
					self:SetSansDodgePoints(targetPlayer, (targetCharacter:GetAttribute("Dodge") or humanoid.Health) - appliedDamage, targetKit)
					targetCharacter:SetAttribute("LastDamagedByUserId", attackerUserId)
				else
					humanoid:TakeDamage(appliedDamage)
					if targetPlayer then
						targetCharacter:SetAttribute("LastDamagedByUserId", attackerUserId)
					end
				end
				self.Remotes.CombatState:FireAllClients({
					Type = "HitConfirm",
					Attacker = attackerUserId,
					Target = targetPlayer and targetPlayer.UserId or targetCharacter.Name,
					Damage = appliedDamage,
					IsKarmic = true,
				})
			end

			effectState.RemainingTicks -= 1
		end

		if attackerEffects[targetCharacter] == effectState then
			attackerEffects[targetCharacter] = nil
			if next(attackerEffects) == nil then
				self.ActiveKarmicEffects[attackerKey] = nil
			end
		end
	end)
end

function CombatService:ResolveSansCounter(defender, attacker)
	local defenderPlayer = getTargetPlayer(defender)
	local defenderState = defenderPlayer and self:GetState(defenderPlayer)
	local counterAbility = CharacterKits.Sans.Abilities.Bones.G
	if not defenderState or defenderState.CounterUntil <= now() then
		return false
	end

	defenderState.CounterUntil = 0
	defenderState.IFrameUntil = now() + 1

	local defenderRoot = getCharacterRoot(getTargetCharacter(defender))
	local attackerCharacter = getTargetCharacter(attacker)
	local attackerPlayer = getTargetPlayer(attacker)
	local attackerRoot = getCharacterRoot(attackerCharacter)
	local counterPalette = self:GetKit(defender) and self:GetKit(defender).DisplayName == "Sans" and self:GetSansEffectPalette(defender) or DEFAULT_SANS_PALETTE
	if defenderRoot then
		self.Effects:SpawnCounterFlash(defenderRoot.Position, counterPalette.Counter)
		defenderRoot.CFrame = defenderRoot.CFrame + defenderRoot.CFrame.LookVector * -8
	end

	if attackerRoot then
		self.Effects:SpawnBoneBurst(attackerRoot.Position, 4, counterPalette.White)
	end

	self:ApplyStun(attacker, counterAbility.Stun)
	local attackerHumanoid = getHumanoid(attackerCharacter)
	if attackerHumanoid and attackerHumanoid.Health > 0 then
		local appliedDamage = self:ScaleDamage(defenderPlayer, attackerCharacter, counterAbility.Damage)
		if attackerPlayer and self:GetKit(attackerPlayer) and self:GetKit(attackerPlayer).DisplayName == "Sans" then
			self:SetSansDodgePoints(attackerPlayer, (attackerCharacter:GetAttribute("Dodge") or attackerHumanoid.Health) - appliedDamage)
			attackerCharacter:SetAttribute("LastDamagedByUserId", defenderPlayer and defenderPlayer.UserId or nil)
		else
			attackerHumanoid:TakeDamage(appliedDamage)
			if attackerCharacter then
				attackerCharacter:SetAttribute("LastDamagedByUserId", defenderPlayer and defenderPlayer.UserId or nil)
			end
		end
		self:ApplyKarmicRetribution(defenderPlayer, attacker)
	end

	self.Remotes.CombatState:FireAllClients({
		Type = "CounterTriggered",
		Player = defenderPlayer.UserId,
		Target = attackerPlayer and attackerPlayer.UserId or (attackerCharacter and attackerCharacter.Name) or nil,
	})

	return true
end

function CombatService:ScaleDamage(attacker, targetCharacter, damage, options)
	options = options or {}
	if not damage or damage <= 0 then
		return 0
	end

	local attackerPlayer = getTargetPlayer(attacker)
	local targetPlayer = getTargetPlayer(targetCharacter)
	local attackerCharacter = getTargetCharacter(attacker)
	local attackStat = attackerCharacter and attackerCharacter:GetAttribute("Attack") or 100
	local defenseStat = targetCharacter and targetCharacter:GetAttribute("Defense") or 0
	local attackMultiplier = math.max(0, attackStat) / 100
	local defenseMultiplier = 100 / (100 + math.max(0, defenseStat))
	local scaledDamage = damage * attackMultiplier * defenseMultiplier
	if attackerPlayer and targetPlayer then
		scaledDamage *= Constants.PVP_DAMAGE_MULTIPLIER or 1
	end

	return math.max(1, math.floor(scaledDamage + 0.5))
end

function CombatService:ResolvePerfectBlock(defender, defenderCharacter, defenderState, defenderKit, attacker, options)
	if not defenderCharacter then
		return false
	end

	if not (options and options.HitType == "M1Melee") then
		return false
	end

	local defenderPlayer = getTargetPlayer(defender)
	local isDummyPerfectBlock = defenderCharacter:GetAttribute("DummyBehavior") == "PerfectBlocking"
	local isBlocking = (defenderState and defenderState.IsBlocking) or defenderCharacter:GetAttribute("Blocking")
	if not isBlocking then
		return false
	end

	if defenderState then
		if (defenderState.PerfectBlockUntil or 0) <= now() then
			return false
		end
		defenderState.PerfectBlockUntil = 0
	elseif not isDummyPerfectBlock then
		return false
	end

	local defenderRoot = getCharacterRoot(defenderCharacter)
	local blockColor = Color3.fromRGB(170, 215, 255)
	local flashColor = Color3.fromRGB(255, 255, 255)
	if defenderPlayer and defenderKit and defenderKit.DisplayName == "Sans" then
		local palette = self:GetSansEffectPalette(defenderPlayer)
		blockColor = palette.Block or blockColor
		flashColor = palette.White or flashColor
	end

	if defenderRoot then
		self.Effects:SpawnBlockOutline(defenderRoot, blockColor)
		self.Effects:SpawnCounterFlash(defenderRoot.Position, flashColor)
	end

	if attackerCharacter then
		self:MaybeTriggerNaoyaEngageQuote(defender, attacker)
		self:ApplyKnockback(defender, attacker, Constants.PERFECT_BLOCK_KNOCKBACK or 0, false)
		self:ApplyStun(attacker, Constants.PERFECT_BLOCK_STUN or 0, {PreserveMomentum = true})
		local perfectBlockDamage = defenderKit and defenderKit.Block and tonumber(defenderKit.Block.PerfectBlockDamage) or 0
		if perfectBlockDamage > 0 and defenderState and defenderState.KitId == "Samurai" then
			self:DamageTarget(defenderPlayer or defenderCharacter, attacker, perfectBlockDamage, 0, 0, {
				IgnoreBlock = true,
				NoKR = true,
				NoSansDodge = true,
			})
		end
		self:MarkInCombat(attacker)
	end
	if defenderPlayer then
		self:MarkInCombat(defenderPlayer)
	end

	self.Remotes.CombatState:FireAllClients({
		Type = "PerfectBlock",
		Player = defenderPlayer and defenderPlayer.UserId or nil,
		Dummy = defenderPlayer and nil or defenderCharacter.Name,
		Target = attackerPlayer and attackerPlayer.UserId or nil,
	})

	return true
end

function CombatService:ResolveSansDodge(targetPlayer, targetCharacter, targetHumanoid, targetState, targetKit, damageAmount, options)
	options = options or {}
	if not targetPlayer or not targetCharacter or not targetHumanoid or not targetState or not targetKit then
		return false
	end

	if targetKit.DisplayName ~= "Sans" or targetState.IsBlocking or targetState.IsStunnedUntil > now() or options.NoSansDodge then
		return false
	end

	local passive = targetKit.Passive
	if not passive or not passive.AutoDodge then
		return false
	end

	local currentDodge = targetCharacter:GetAttribute("Dodge")
	if currentDodge == nil then
		currentDodge = math.floor(targetHumanoid.Health + 0.5)
	end
	if currentDodge <= 0 then
		return false
	end

	local animationIds = targetKit.AnimationIds or {}
	local dodgeDirection = math.random() < 0.5 and "Left" or "Right"
	local animationId = dodgeDirection == "Left" and animationIds.DodgeLeft or animationIds.DodgeRight
	local dodgeCost = math.max(1, math.ceil(damageAmount or 1))
	local remainingDodge = self:SetSansDodgePoints(targetPlayer, currentDodge - dodgeCost, targetKit)
	local dodgeDuration = passive.DodgeIFrame or 0.35
	local dodgeNonce = (targetCharacter:GetAttribute("DodgeNonce") or 0) + 1
	targetCharacter:SetAttribute("Dodging", true)
	targetCharacter:SetAttribute("DodgeDirection", dodgeDirection)
	targetCharacter:SetAttribute("DodgeNonce", dodgeNonce)

	targetState.IFrameUntil = math.max(targetState.IFrameUntil or 0, now() + dodgeDuration)
	playActionAnimation(targetCharacter, animationId)
	self:MarkInCombat(targetPlayer)
	if Constants.SANS_DODGE_DEBUG then
		warn(string.format("[SansDodgeDebug][Server] SUCCESS player=%s direction=%s damage=%s remaining=%s", targetPlayer.Name, dodgeDirection, tostring(damageAmount), tostring(remainingDodge)))
	end
	self:SendDodgeDebug(targetPlayer, string.format("SERVER SUCCESS %s | dmg %s | dodge %s", dodgeDirection, tostring(damageAmount), tostring(remainingDodge)))
	task.delay(dodgeDuration, function()
		if targetCharacter.Parent and targetCharacter:GetAttribute("DodgeNonce") == dodgeNonce then
			targetCharacter:SetAttribute("Dodging", false)
		end
	end)

	self.Remotes.CombatState:FireAllClients({
		Type = "SansDodged",
		Player = targetPlayer.UserId,
		Direction = dodgeDirection,
		Remaining = remainingDodge,
	})

	return true
end

function CombatService:GetAbilityHitOptions(ability, extraOptions)
	local options = {}
	if ability then
		if ability.BreakBlock == true then
			options.BreakBlock = true
		end
		if ability.IgnoreBlock == true then
			options.IgnoreBlock = true
		end
	end

	if extraOptions then
		for key, value in pairs(extraOptions) do
			options[key] = value
		end
	end

	return next(options) and options or nil
end

function CombatService:DamageTarget(attacker, target, damage, knockback, stun, options)
	options = options or {}

	local targetCharacter = getTargetCharacter(target)
	local targetPlayer = getTargetPlayer(target)
	local attackerCharacter = getTargetCharacter(attacker)
	local attackerPlayer = getTargetPlayer(attacker)
	local attackerUserId = attackerPlayer and attackerPlayer.UserId or nil
	local targetWasInCombat = targetCharacter and targetCharacter:GetAttribute("InCombat") == true
	if self:IsTrainingServer() and targetPlayer and not options.AllowTrainingDamage then
		return false
	end
	local targetHumanoid = getHumanoid(targetCharacter)
	local targetState = targetPlayer and self:GetState(targetPlayer)
	local targetKit = targetPlayer and self:GetKit(targetPlayer)
	if not targetHumanoid or targetHumanoid.Health <= 0 then
		return false
	end

	if targetState and self:ResolveSansCounter(target, attacker) then
		return false
	end

	if targetState and targetState.IFrameUntil > now() then
		return false
	end

	local isBlocking = (targetState and targetState.IsBlocking) or (targetCharacter and targetCharacter:GetAttribute("Blocking"))
	if isBlocking and not options.IgnoreBlock and self:ResolvePerfectBlock(target, targetCharacter, targetState, targetKit, attacker, options) then
		return false
	end

	local brokeBlock = false
	if isBlocking and options.BreakBlock then
		if targetPlayer then
			self:SetBlocking(targetPlayer, false)
			targetState = self:GetState(targetPlayer)
		elseif targetCharacter then
			targetCharacter:SetAttribute("Blocking", false)
		end
		isBlocking = false
		brokeBlock = true
	end
	if isBlocking and options.IgnoreBlock then
		isBlocking = false
	end

	local appliedDamage = self:ScaleDamage(attacker, targetCharacter, damage, options)
	if targetPlayer and not brokeBlock and self:ResolveSansDodge(targetPlayer, targetCharacter, targetHumanoid, targetState, targetKit, appliedDamage, options) then
		return false
	end
	if targetPlayer and targetKit and targetKit.DisplayName == "Sans" and Constants.SANS_DODGE_DEBUG then
		warn(string.format(
			"[SansDodgeDebug][Server] BYPASS player=%s blocking=%s stunned=%s dodge=%s noSansDodge=%s damage=%s",
			targetPlayer.Name,
			tostring(isBlocking),
			tostring(targetState and (targetState.IsStunnedUntil > now()) or false),
			tostring(targetCharacter:GetAttribute("Dodge") or targetHumanoid.Health),
			tostring(options.NoSansDodge == true),
			tostring(appliedDamage)
		))
		self:SendDodgeDebug(targetPlayer, string.format(
			"SERVER BYPASS | block %s | stunned %s | dodge %s | noDodge %s | dmg %s",
			tostring(isBlocking),
			tostring(targetState and (targetState.IsStunnedUntil > now()) or false),
			tostring(targetCharacter:GetAttribute("Dodge") or targetHumanoid.Health),
			tostring(options.NoSansDodge == true),
			tostring(appliedDamage)
		))
	end
	if isBlocking then
		local reduction = (targetKit and targetKit.Block and targetKit.Block.DamageReduction) or 0.75
		appliedDamage = math.max(0, math.floor((appliedDamage * (1 - reduction)) + 0.5))
	end

	if appliedDamage > 0 then
		if targetPlayer and targetKit and targetKit.DisplayName == "Sans" then
			self:SetSansDodgePoints(targetPlayer, (targetCharacter:GetAttribute("Dodge") or targetHumanoid.Health) - appliedDamage, targetKit)
		else
			targetHumanoid:TakeDamage(appliedDamage)
		end
		if targetPlayer then
			targetCharacter:SetAttribute("LastDamagedByUserId", attackerUserId)
		end
	end
	if brokeBlock then
		self.Remotes.CombatState:FireAllClients({
			Type = "BlockBreak",
			Attacker = attackerUserId,
			Target = targetPlayer and targetPlayer.UserId or (targetCharacter and targetCharacter.Name) or nil,
		})
	end
	if targetPlayer and attackerCharacter and attackerCharacter ~= targetCharacter then
		self:MaybeTriggerNaoyaEngageQuote(target, attacker)
	end
	self:MarkInCombat(attacker)
	if targetPlayer then
		self:MarkInCombat(targetPlayer)
	end
	local appliedStun = stun
	if brokeBlock then
		appliedStun = math.max(tonumber(appliedStun) or 0, Constants.BLOCK_BREAK_STUN or 2)
	end
	if appliedStun and appliedStun > 0 then
		self:ApplyStun(target, appliedStun)
	end
	if knockback and knockback > 0 then
		self:ApplyKnockback(attacker, target, knockback, options.Launch)
	end

	if targetPlayer and targetKit and targetKit.DisplayName == "Sans" and targetKit.Passive then
		self:SetResource(targetPlayer, "Mana", self:GetResource(targetPlayer, "Mana") - targetKit.Passive.OnHitManaLoss - appliedDamage)
	end

	if not options.NoKR and self:GetKit(attacker) and self:GetKit(attacker).Passive then
		self:ApplyKarmicRetribution(attacker, target)
	end

	self.Remotes.CombatState:FireAllClients({
		Type = "HitConfirm",
		Attacker = attackerUserId,
		Target = targetPlayer and targetPlayer.UserId or targetCharacter.Name,
		Damage = appliedDamage,
	})

	if attackerCharacter and targetCharacter and attackerCharacter ~= targetCharacter then
		local dummyBehavior = targetCharacter:GetAttribute("DummyBehavior")
		if dummyBehavior == "KnockbackOnHit" and options.HitType == "M1Melee" then
			local reactiveKnockback = tonumber(targetCharacter:GetAttribute("DummyReactiveKnockback")) or 0
			local reactiveLaunch = targetCharacter:GetAttribute("DummyReactiveLaunch") == true
			local reactiveStun = tonumber(targetCharacter:GetAttribute("DummyReactiveStun")) or 0
			if reactiveKnockback > 0 then
				self:ApplyKnockback(targetCharacter, attacker, reactiveKnockback, reactiveLaunch)
			end
			if reactiveStun > 0 then
				self:ApplyStun(attacker, reactiveStun, {
					PreserveMomentum = true,
				})
			end
		end
	end

	return true
end

function CombatService:DamageTargets(attacker, targets, damage, knockback, stun, options)
	local hitAny = false
	for _, target in ipairs(targets) do
		if self:DamageTarget(attacker, target, damage, knockback, stun, options) then
			hitAny = true
		end
	end
	return hitAny
end

function CombatService:DamageTargetsAndCollect(attacker, targets, damage, knockback, stun, options)
	local hitAny = false
	local hitTargets = {}
	for _, target in ipairs(targets) do
		if self:DamageTarget(attacker, target, damage, knockback, stun, options) then
			hitAny = true
			table.insert(hitTargets, target)
		end
	end
	return hitAny, hitTargets
end

function CombatService:TryM1(player, payload)
	local state = self:GetState(player)
	local kit = self:GetKit(player)
	local root = getCharacterRoot(player.Character)
	if not state or not kit or not root or self:IsActionLocked(player) or self:IsMovementLocked(player) then
		return
	end

	if state.M1CooldownUntil > now() then
		return
	end

	if kit.DisplayName == "Sans" and state.Mode == "Blasters" then
		local summonAbility = kit.Abilities and kit.Abilities.Blasters and kit.Abilities.Blasters.Z
		if not summonAbility or state.ActiveBlasters <= 0 then
			return
		end

		local aimPosition = self:GetAimPosition(player, payload, summonAbility.FireRange or summonAbility.Range or 32)
		local lockedTarget = self:GetLockedTargetFromPayload(player, payload, summonAbility.FireRange or summonAbility.Range or 32)
		local targetRoot = lockedTarget and getCharacterRoot(lockedTarget)
		local shotIndex = state.ActiveBlasters
		local origin = root.Position
			+ root.CFrame.RightVector * (1 + (shotIndex % 2 == 0 and -0.9 or 0.9))
			+ root.CFrame.LookVector * 0.8
			+ Vector3.new(0, 3.2, 0)

		local consumed = self:ConsumeActiveBlasters(player, state, 1)
		if consumed <= 0 then
			return
		end
		state.M1CooldownUntil = now() + (summonAbility.FireCooldown or 0.3)

		self:FireSansBlasterBeam(
			player,
			origin,
			targetRoot and (targetRoot.Position + Vector3.new(0, 2, 0)) or aimPosition,
			summonAbility
		)
		self.Remotes.CombatState:FireAllClients({
			Type = "M1",
			Player = player.UserId,
			Combo = 1,
		})
		self:MarkInCombat(player)
		return
	end

	if not kit.M1Damage then
		if kit.DisplayName == "Sans" then
			self:SendMessage(player, "Sans has no M1 combo.")
		end
		return
	end

	if now() - state.LastM1At > Constants.M1_RESET_TIME then
		state.ComboStep = 0
	end

	state.LastM1At = now()
	state.ComboStep = (state.ComboStep % #kit.M1Damage) + 1
	local comboIndex = state.ComboStep
	local isFinalComboHit = comboIndex >= #kit.M1Damage
	local m1Knockback = kit.M1Knockback[comboIndex] or 0
	if isFinalComboHit then
		m1Knockback = math.max(m1Knockback, Constants.FINAL_M1_KNOCKBACK or m1Knockback)
	end

	local size = Vector3.new(7, 6, comboIndex >= 3 and 10 or 8)
	local cframe = root.CFrame * CFrame.new(0, 1.5, -4)
	local color = comboIndex >= 3 and Color3.fromRGB(30, 30, 35) or Color3.fromRGB(220, 220, 220)
	self.Effects:SpawnSlash(cframe, Vector3.new(5.5, 5.5, 1.5), color, 0.24)

	local targets = self.Hitboxes:QueryBox(player, cframe, size, {
		CFrame = cframe,
		Size = size,
		Color = Color3.fromRGB(255, 255, 255),
	})
	local _, hitTargets = self:DamageTargetsAndCollect(player, targets, kit.M1Damage[comboIndex], m1Knockback, Constants.M1_STUN_TIME, {
		HitType = "M1Melee",
		Launch = isFinalComboHit,
	})
	if kit.DisplayName == "Naoya" and (kit.M1FrameMarks or 0) > 0 then
		local uniqueTargets = {}
		for _, target in ipairs(hitTargets) do
			appendUniqueTarget(uniqueTargets, target)
		end
		for _, target in pairs(uniqueTargets) do
			self:ApplyNaoyaFrameMarks(player, target, kit.M1FrameMarks)
		end
	elseif state.KitId == "Samurai" and (kit.M1BleedMarks or 0) > 0 then
		local uniqueTargets = {}
		for _, target in ipairs(hitTargets) do
			appendUniqueTarget(uniqueTargets, target)
		end
		for _, target in pairs(uniqueTargets) do
			self:ApplySamuraiBleedMarks(player, target, kit.M1BleedMarks)
		end
	end

	self.Remotes.CombatState:FireAllClients({
		Type = "M1",
		Player = player.UserId,
		Combo = comboIndex,
	})
	self:MarkInCombat(player)

	if comboIndex >= #kit.M1Damage and (kit.M1ComboCooldown or 0) > 0 then
		state.M1CooldownUntil = now() + kit.M1ComboCooldown
		state.ComboStep = 0
	end
end

function CombatService:TryDash(player, payload)
	local state = self:GetState(player)
	local character = player.Character
	local root = getCharacterRoot(player.Character)
	local humanoid = getHumanoid(character)
	local kit = self:GetKit(player)
	if not state or not character or not root or not humanoid or self:IsActionLocked(player) or self:IsMovementLocked(player) then
		return
	end

	if now() - state.LastDashAt < Constants.DASH_COOLDOWN then
		return
	end

	if not self:SpendResource(player, "Stamina", Constants.DASH_STAMINA_COST) then
		self:SendMessage(player, "Not enough stamina to dash.")
		return
	end

	if kit and kit.DisplayName == "Sans" and not self:SpendResource(player, "Mana", 20) then
		self:SetResource(player, "Stamina", self:GetResource(player, "Stamina") + Constants.DASH_STAMINA_COST)
		self:SendMessage(player, "Not enough mana to dodge.")
		return
	end

	state.LastDashAt = now()
	self:TryEscapeTelekinesis(player)
	if forceCharacterStand(character) then
		RunService.Heartbeat:Wait()
	end

	local dashDirection
	if typeof(payload) == "table" and typeof(payload.MoveDirection) == "Vector3" then
		local requestedDirection = Vector3.new(payload.MoveDirection.X, 0, payload.MoveDirection.Z)
		if requestedDirection.Magnitude > 0.01 then
			dashDirection = requestedDirection.Unit
		end
	end

	if not dashDirection then
		local moveDirection = Vector3.new(humanoid.MoveDirection.X, 0, humanoid.MoveDirection.Z)
		if moveDirection.Magnitude > 0.01 then
			dashDirection = moveDirection.Unit
		end
	end

	if not dashDirection then
		dashDirection = root.CFrame.LookVector
	end

	local velocity = Instance.new("BodyVelocity")
	velocity.MaxForce = Vector3.new(1, 0, 1) * 50000
	velocity.Velocity = dashDirection * Constants.DASH_SPEED
	velocity.Parent = root
	Debris:AddItem(velocity, Constants.DASH_TIME)

	if kit and kit.DisplayName == "Sans" then
		state.IFrameUntil = now() + Constants.DASH_TIME
	end

	local dashColor = kit and kit.DisplayName == "Sans" and self:GetSansEffectPalette(player).Beam or Color3.fromRGB(115, 180, 255)
	self.Effects:SpawnSlash(CFrame.lookAt(root.Position, root.Position + dashDirection), Vector3.new(3, 3, 3), dashColor, 0.2)
	self.Remotes.CombatState:FireAllClients({
		Type = "Dash",
		Player = player.UserId,
	})
end

function CombatService:SetRunning(player, enabled)
	local state = self:GetState(player)
	local character = player.Character
	local humanoid = getHumanoid(character)
	local kit = self:GetKit(player)
	if not state or not character or not humanoid or not kit then
		return
	end

	local wantsRunning = enabled == true
	if wantsRunning then
		if self:IsMovementLocked(player) or humanoid.Health <= 0 then
			wantsRunning = false
		elseif (kit.Stats.Stamina or 0) > 0 and self:GetResource(player, "Stamina") <= 0 then
			wantsRunning = false
		end
	end

	if state.IsRunning == wantsRunning then
		return
	end

	state.IsRunning = wantsRunning
	self:RefreshMovementState(player)
end

function CombatService:SpendAbilityCost(player, ability)
	if ability.ManaCost and not self:SpendResource(player, "Mana", ability.ManaCost) then
		self:SendMessage(player, "Not enough mana.")
		return false
	end

	return true
end

function CombatService:RefundAbilityCost(player, ability)
	if ability.ManaCost then
		self:SetResource(player, "Mana", self:GetResource(player, "Mana") + ability.ManaCost)
	end
end

function CombatService:PerformSansBonesAbility(player, slot, ability, payload)
	local state = self:GetState(player)
	local root = getCharacterRoot(player.Character)
	if not state or not root then
		return false
	end

	local palette = self:GetSansEffectPalette(player)
	local blasterTemplates = self:GetSansBlasterTemplateNames(player)

	if slot == "Z" then
		local aim = self:GetAimPosition(player, payload, ability.Range)
		local startPos = root.Position + Vector3.new(0, 2.2, 0)
		local endPos = startPos + clampVector(aim - startPos, ability.Range)
		local cf = CFrame.lookAt(startPos:Lerp(endPos, 0.5), endPos)
		local size = Vector3.new(3, 4, math.max(5, (endPos - startPos).Magnitude))
		self.Effects:SpawnBoneLine(startPos, endPos, palette.White)
		local targets = self.Hitboxes:QueryBox(player, cf, size, {
			CFrame = cf,
			Size = size,
			Color = palette.BoneBright,
		})
		self:DamageTargets(player, targets, ability.Damage, ability.Knockback, ability.Stun)
		return true
	elseif slot == "X" then
		local target = self:ResolveSansTargetFromPayload(player, payload, ability.Range)
		if not target then
			return false
		end
		local targetRoot = getCharacterRoot(target)
		if not targetRoot then
			return false
		end
		local tossStart = root.Position + root.CFrame.RightVector * 1.15 + Vector3.new(0, 2.9, 0)
		local tossPeak = tossStart + Vector3.new(0, 6.5, 0)
		self.Effects:SpawnBoneBall(tossStart, 1.1, palette.Bone, 0.24)
		self.Effects:SpawnBoneLine(tossStart, tossPeak, palette.Bone)

		task.delay(tonumber(ability.Windup) or 0.9, function()
			if not self.PlayerState[player] then
				return
			end

			local liveTargetRoot = getCharacterRoot(target)
			if not liveTargetRoot then
				return
			end

			self.Effects:SpawnBoneBatSwing(
				root.CFrame * CFrame.new(1.55, 1.65, -1.1) * CFrame.Angles(math.rad(-18), 0, math.rad(18)),
				palette.White
			)

			local endPos = liveTargetRoot.Position + Vector3.new(0, 2, 0)
			self.Effects:SpawnBoneBall(tossPeak, 1.1, palette.Bone, 0.16)
			self.Effects:SpawnBoneLine(tossPeak, endPos, palette.Bone)
			local cf = CFrame.lookAt(tossPeak:Lerp(endPos, 0.5), endPos)
			local size = Vector3.new(2.5, 2.5, math.max(5, (endPos - tossPeak).Magnitude))
			local targets = self.Hitboxes:QueryBox(player, cf, size, {
				CFrame = cf,
				Size = size,
				Color = palette.Bone,
				Duration = 0.14,
			})
			self:DamageTargets(player, targets, ability.Damage, ability.Knockback, ability.Stun)
		end)
		return true
	elseif slot == "C" then
		local wallColor = math.random() < ability.BlueChance and palette.Bone or palette.White
		local cf = root.CFrame * CFrame.new(0, 1.5, -8)
		local size = Vector3.new(11, 6, 10)
		self.Effects:SpawnWaveWall(cf, Vector3.new(10, 5, 2), wallColor)
		local targets = self.Hitboxes:QueryBox(player, cf, size, {
			CFrame = cf,
			Size = size,
			Color = wallColor,
		})
		self:DamageTargets(player, targets, ability.Damage, ability.Knockback, ability.Stun + (wallColor.B > 0.8 and 0.35 or 0), self:GetAbilityHitOptions(ability))
		return true
	elseif slot == "V" then
		local position = root.Position
		self.Effects:SpawnZone(position, ability.Radius, palette.Zone)
		local targets = self.Hitboxes:QueryRadius(player, position, ability.Radius, {
			CFrame = CFrame.new(position),
			Size = Vector3.new(ability.Radius * 2, ability.Radius * 2, ability.Radius * 2),
			Color = palette.BonePale,
			Shape = "Sphere",
			Duration = 0.3,
		})
		self:DamageTargets(player, targets, ability.Damage, ability.Knockback, ability.Stun, self:GetAbilityHitOptions(ability))
		return true
	elseif slot == "G" then
		state.CounterUntil = now() + ability.CounterWindow
		self.Effects:SpawnCounterFlash(root.Position, palette.Counter)
		self.Remotes.CombatState:FireClient(player, {
			Type = "CounterReady",
			Duration = ability.CounterWindow,
		})
		return true
	end

	return false
end

function CombatService:PerformSansTelekinesisAbility(player, slot, ability, payload)
	if slot ~= "Z" then
		return false
	end

	local state = self:GetState(player)
	if not state or state.PendingTeleTargetKey or state.HeldTargetUserId then
		return false
	end

	local target = self:GetLockedTargetFromPayload(player, payload, ability.Range)
	local root = target and getCharacterRoot(target)
	local targetKey = getTelekinesisTargetKey(target)
	if not target or not root or not targetKey then
		return false
	end

	local palette = self:GetSansEffectPalette(player)
	self.Effects:SpawnZone(root.Position, 4, palette.ZoneBright)
	self.Hitboxes:BroadcastDebug({
		CFrame = CFrame.new(root.Position),
		Size = Vector3.new(7, 7, 7),
		Color = palette.ZoneBright,
		Shape = "Sphere",
		Duration = 0.25,
	})

	local escapeWindow = ability.EscapeWindow or 1.5
	state.TelekinesisAttemptId = (state.TelekinesisAttemptId or 0) + 1
	local attemptId = state.TelekinesisAttemptId
	state.PendingTeleTargetKey = targetKey
	if state.TelekinesisMarker then
		self.Effects:DestroyTelekinesisMarker(state.TelekinesisMarker)
	end
	state.TelekinesisMarker = self.Effects:CreateTelekinesisMarker(root, palette.White)
	self:ApplyStun(player, escapeWindow)

	task.delay(escapeWindow, function()
		local currentState = self.PlayerState[player]
		if not currentState or currentState.TelekinesisAttemptId ~= attemptId or currentState.PendingTeleTargetKey ~= targetKey then
			return
		end

		currentState.PendingTeleTargetKey = nil
		local heldTarget = self:FindTelekinesisTargetByKey(player, targetKey)
		local heldRoot = heldTarget and getCharacterRoot(heldTarget)
		if not heldTarget or not heldRoot then
			self:ResetTelekinesisState(currentState)
			return
		end

		currentState.HeldTargetUserId = targetKey
		if currentState.TelekinesisMarker then
			self.Effects:DestroyTelekinesisMarker(currentState.TelekinesisMarker)
		end
		currentState.TelekinesisMarker = self.Effects:CreateTelekinesisMarker(heldRoot, palette.Beam)
		self:DamageTarget(player, heldTarget, ability.Damage, 0, 0.2, self:GetAbilityHitOptions(ability, {NoKR = true}))
		self:ApplyStun(heldTarget, ability.HoldDuration)
		self.Remotes.CombatState:FireClient(player, {
			Type = "TelekinesisGrab",
			Target = heldTarget.Name,
		})

		task.delay(ability.HoldDuration, function()
			local latestState = self.PlayerState[player]
			if latestState and latestState.TelekinesisAttemptId == attemptId and latestState.HeldTargetUserId == targetKey then
				self:ResetTelekinesisState(latestState)
			end
		end)
	end)

	return true
end

function CombatService:PerformSansBlasterAbility(player, slot, ability, payload)
	local state = self:GetState(player)
	local root = getCharacterRoot(player.Character)
	if not state or not root then
		return false
	end

	local palette = self:GetSansEffectPalette(player)
	local blasterTemplates = self:GetSansBlasterTemplateNames(player)

	if slot == "Z" then
		self:CleanupActiveBlasterList(state)
		if state.ActiveBlasters >= ability.MaxCount then
			self:SendMessage(player, "Blaster cap reached.")
			return false
		end
		state.BlasterEffects = state.BlasterEffects or {}
		local slotIndex = self:GetOpenSansBlasterSlot(state, ability.MaxCount)
		local offset = self:GetSansPersistentBlasterOffset(slotIndex)
		local effect = self.Effects:CreatePersistentBlaster(root, offset, palette.Beam, blasterTemplates)
		if effect then
			effect:SetAttribute("BlasterSlotIndex", slotIndex)
			table.insert(state.BlasterEffects, effect)
			state.ActiveBlasters = #state.BlasterEffects
			setCharacterAttribute(player, "ActiveBlasters", state.ActiveBlasters)
		end
		return true
	elseif slot == "X" then
		if state.ActiveBlasters <= 0 then
			self:SendMessage(player, "No blasters available.")
			return false
		end

		if state.PendingBlasterShots > 0 then
			local target = self:FindTelekinesisTargetByKey(player, state.PendingBlasterTargetKey)
			local targetRoot = target and getCharacterRoot(target)
			if not target or not targetRoot then
				state.PendingBlasterShots = 0
				state.PendingBlasterTargetKey = nil
				setCharacterAttribute(player, "PendingBlasterShots", 0)
				return false
			end

			local shotCount = math.min(state.PendingBlasterShots, state.ActiveBlasters)
			local consumed = self:ConsumeActiveBlasters(player, state, shotCount)
			state.PendingBlasterShots = 0
			state.PendingBlasterTargetKey = nil
			setCharacterAttribute(player, "PendingBlasterShots", 0)

			for index = 1, consumed do
				local directionSign = index % 2 == 0 and -1 or 1
				local origin = root.Position + root.CFrame.RightVector * (2.4 * directionSign) + Vector3.new(0, 3.2, 0)
				self:FireSansBlasterBeam(player, origin, targetRoot.Position + Vector3.new(0, 2, 0), ability, nil, self:GetAbilityHitOptions(ability))
			end
			return consumed > 0
		end

		local target = self:ResolveSansTargetFromPayload(player, payload, ability.Range)
		local targetRoot = target and getCharacterRoot(target)
		local targetKey = getTelekinesisTargetKey(target)
		if not target or not targetRoot or not targetKey then
			return false
		end

		state.PendingBlasterShots = math.min(ability.TrackCount, state.ActiveBlasters)
		state.PendingBlasterTargetKey = targetKey
		setCharacterAttribute(player, "PendingBlasterShots", state.PendingBlasterShots)
		for index = 1, state.PendingBlasterShots do
			local directionSign = index % 2 == 0 and -1 or 1
			local trackPos = targetRoot.Position + root.CFrame.RightVector * (2.6 * directionSign) + Vector3.new(0, 3.4, 0)
			self.Effects:SpawnBlaster(trackPos, palette.Beam, blasterTemplates)
		end
		self:SendMessage(player, "Tracked blasters locked on. Press X again to fire.")
		return true
	end

	return false
end

function CombatService:PerformMagnusAbility(player, slot, ability, payload)
	local character = player.Character
	local root = getCharacterRoot(character)
	if not character or not root then
		return false
	end

	if self:IsBlackSilenceSkinEquipped(player) and slot ~= "G" then
		if slot == "Z" then
			local cf = root.CFrame * CFrame.new(0, 1.35, -3.8)
			local size = Vector3.new(3.2, 4.4, 6.2)
			self.Effects:SpawnSlash(cf, Vector3.new(1.1, 4.6, 5.6), Color3.fromRGB(16, 16, 18), 0.18)
			local targets = self.Hitboxes:QueryBox(player, cf, size, {
				CFrame = cf,
				Size = size,
				Color = Color3.fromRGB(56, 56, 60),
			})
			self:DamageTargets(player, targets, ability.Damage, ability.Knockback, ability.Stun, self:GetAbilityHitOptions(ability))
			return true
		elseif slot == "X" then
			if forceCharacterStand(character) then
				RunService.Heartbeat:Wait()
			end
			root.CFrame = root.CFrame * CFrame.new(0, 0, -math.min(ability.Range * 0.55, 7.2))
			local cf = root.CFrame * CFrame.new(0, 1.45, -5.4)
			local size = Vector3.new(4.2, 4.6, 9.4)
			self.Effects:SpawnSlash(cf, Vector3.new(1.35, 2.4, 8.6), Color3.fromRGB(210, 210, 214), 0.18)
			local targets = self.Hitboxes:QueryBox(player, cf, size, {
				CFrame = cf,
				Size = size,
				Color = Color3.fromRGB(210, 210, 214),
			})
			self:DamageTargets(player, targets, ability.Damage, ability.Knockback, ability.Stun, self:GetAbilityHitOptions(ability))
			return true
		elseif slot == "C" then
			local cf = root.CFrame * CFrame.new(0, 1.4, -3.2)
			local size = Vector3.new(5.2, 5, 4.6)
			self.Effects:SpawnSlash(cf, Vector3.new(3.6, 2.5, 3.1), Color3.fromRGB(232, 232, 236), 0.14)
			self.Effects:SpawnZone(root.Position + root.CFrame.LookVector * 3.1, 1.6, Color3.fromRGB(22, 22, 26))
			local targets = self.Hitboxes:QueryBox(player, cf, size, {
				CFrame = cf,
				Size = size,
				Color = Color3.fromRGB(100, 100, 108),
			})
			self:DamageTargets(player, targets, ability.Damage, ability.Knockback, ability.Stun, self:GetAbilityHitOptions(ability))
			return true
		elseif slot == "V" then
			local cf = root.CFrame * CFrame.new(0, 1.5, -4.1) * CFrame.Angles(0, 0, math.rad(24))
			local size = Vector3.new(5.6, 5.2, 6.2)
			self.Effects:SpawnSlash(cf, Vector3.new(4.8, 4.2, 1.4), Color3.fromRGB(245, 245, 248), 0.15)
			local targets = self.Hitboxes:QueryBox(player, cf, size, {
				CFrame = cf,
				Size = size,
				Color = Color3.fromRGB(245, 245, 248),
			})
			self:DamageTargets(player, targets, ability.Damage, ability.Knockback, ability.Stun, self:GetAbilityHitOptions(ability))
			return true
		end
	end

	if slot == "Z" then
		local cf = root.CFrame * CFrame.new(0, 1.5, -4.5)
		local size = Vector3.new(6, 6, 6)
		self.Effects:SpawnSlash(cf, Vector3.new(3.5, 7, 1.2), Color3.fromRGB(30, 30, 35), 0.22)
		local targets = self.Hitboxes:QueryBox(player, cf, size, {
			CFrame = cf,
			Size = size,
			Color = Color3.fromRGB(70, 70, 70),
		})
		self:DamageTargets(player, targets, ability.Damage, 0, ability.Stun + 0.5, self:GetAbilityHitOptions(ability))
		return true
	elseif slot == "X" then
		if forceCharacterStand(character) then
			RunService.Heartbeat:Wait()
		end
		root.CFrame = root.CFrame * CFrame.new(0, 0, -math.min(ability.Range * 0.55, 7))
		local cf = root.CFrame * CFrame.new(0, 1.5, -5)
		local size = Vector3.new(5, 5, 9)
		self.Effects:SpawnSlash(cf, Vector3.new(2.5, 3.2, 7), Color3.fromRGB(20, 20, 20), 0.18)
		local targets = self.Hitboxes:QueryBox(player, cf, size, {
			CFrame = cf,
			Size = size,
			Color = Color3.fromRGB(30, 30, 30),
		})
		self:DamageTargets(player, targets, ability.Damage, ability.Knockback, ability.Stun, self:GetAbilityHitOptions(ability))
		return true
	elseif slot == "C" then
		local cf = root.CFrame * CFrame.new(0, 1.5, -3.5)
		local size = Vector3.new(5, 5, 5)
		self.Effects:SpawnSlash(cf * CFrame.new(-1, 0, 0), Vector3.new(1.5, 4, 4), Color3.fromRGB(28, 28, 30), 0.18)
		self.Effects:SpawnSlash(cf * CFrame.new(1, 0, 0), Vector3.new(1.5, 4, 4), Color3.fromRGB(28, 28, 30), 0.18)
		local targets = self.Hitboxes:QueryBox(player, cf, size, {
			CFrame = cf,
			Size = size,
			Color = Color3.fromRGB(50, 50, 50),
		})
		local hit = self:DamageTargets(player, targets, math.floor(ability.Damage * 0.5), 0, 0.2, self:GetAbilityHitOptions(ability))
		if hit then
			task.delay(0.18, function()
				if self.PlayerState[player] then
					self:DamageTargets(player, targets, math.ceil(ability.Damage * 0.5), ability.Knockback, ability.Stun, self:GetAbilityHitOptions(ability))
				end
			end)
		end
		return true
	elseif slot == "V" then
		local cf = root.CFrame * CFrame.new(0, 1.5, -3.5)
		local size = Vector3.new(5, 6, 5)
		self.Effects:SpawnSlash(cf, Vector3.new(3, 4, 3), Color3.fromRGB(255, 255, 255), 0.15)
		local targets = self.Hitboxes:QueryBox(player, cf, size, {
			CFrame = cf,
			Size = size,
			Color = Color3.fromRGB(245, 245, 245),
		})
		self:DamageTargets(player, targets, ability.Damage, ability.Knockback, ability.Stun, self:GetAbilityHitOptions(ability, {
			Launch = true,
		}))
		return true
	elseif slot == "G" then
		local target = self:FindClosestTargetToPosition(player, self:GetAimPosition(player, payload, ability.Range), ability.Range)
		local targetRoot = target and getCharacterRoot(target)
		if not target or not targetRoot then
			return false
		end

		task.delay(ability.Windup, function()
			if not self.PlayerState[player] or not target.Parent then
				return
			end

			for hitIndex = 1, ability.Hits do
				task.delay((hitIndex - 1) * 0.18, function()
					if not self.PlayerState[player] or not target.Parent then
						return
					end
					local impact = targetRoot.Position + Vector3.new(((hitIndex % 2 == 0) and -1 or 1) * hitIndex, 0, (hitIndex - 3) * 1.5)
					self.Effects:SpawnSwordRain(impact)
					local cf = CFrame.new(impact + Vector3.new(0, 3, 0))
					local size = Vector3.new(4, 8, 4)
					local targets = self.Hitboxes:QueryBox(player, cf, size, {
						CFrame = cf,
						Size = size,
						Color = Color3.fromRGB(20, 20, 25),
						Duration = 0.18,
					})
					self:DamageTargets(player, targets, ability.Damage, ability.Knockback, ability.Stun, self:GetAbilityHitOptions(ability))
				end)
			end
		end)
		return true
	end

	return false
end

function CombatService:PerformSamuraiAbility(player, slot, ability, payload)
	local character = player.Character
	local root = getCharacterRoot(character)
	if not character or not root then
		return false
	end

	local function applyBleedMarksToHits(hitTargets, stacks)
		local uniqueTargets = {}
		for _, target in ipairs(hitTargets) do
			appendUniqueTarget(uniqueTargets, target)
		end
		for _, target in pairs(uniqueTargets) do
			self:ApplySamuraiBleedMarks(player, target, stacks)
		end
	end

	local function tryBleedHitTargets(hitTargets)
		local uniqueTargets = {}
		local bledAny = false
		for _, target in ipairs(hitTargets) do
			appendUniqueTarget(uniqueTargets, target)
		end
		for _, target in pairs(uniqueTargets) do
			if self:TryTriggerSamuraiBleed(player, target) then
				bledAny = true
			end
		end
		return bledAny
	end

	if slot == "Z" then
		if forceCharacterStand(character) then
			RunService.Heartbeat:Wait()
		end
		root.CFrame = root.CFrame * CFrame.new(0, 0, -math.min(ability.Range * 0.45, 5.2))
		local cf = root.CFrame * CFrame.new(0, 1.45, -4.2)
		local size = Vector3.new(4.8, 4.8, 8.5)
		self.Effects:SpawnSlash(cf, Vector3.new(2.2, 3.2, 7.8), Color3.fromRGB(245, 245, 255), 0.14)
		local targets = self.Hitboxes:QueryBox(player, cf, size, {
			CFrame = cf,
			Size = size,
			Color = Color3.fromRGB(245, 245, 255),
		})
		local hit, hitTargets = self:DamageTargetsAndCollect(player, targets, ability.Damage, ability.Knockback, ability.Stun, self:GetAbilityHitOptions(ability))
		if hit and ability.BleedMarks then
			applyBleedMarksToHits(hitTargets, ability.BleedMarks)
		end
		return true
	elseif slot == "X" then
		if forceCharacterStand(character) then
			RunService.Heartbeat:Wait()
		end
		root.CFrame = root.CFrame * CFrame.new(0, 0, -math.min(ability.Range * 0.5, 6.2))
		local cf = root.CFrame * CFrame.new(0, 1.5, -4.8)
		local size = Vector3.new(4.8, 5.2, 9.8)
		self.Effects:SpawnSlash(cf, Vector3.new(2.4, 3.6, 8.8), Color3.fromRGB(235, 235, 245), 0.16)
		local targets = self.Hitboxes:QueryBox(player, cf, size, {
			CFrame = cf,
			Size = size,
			Color = Color3.fromRGB(235, 235, 245),
		})
		local hit, hitTargets = self:DamageTargetsAndCollect(player, targets, ability.Damage, ability.Knockback, ability.Stun, self:GetAbilityHitOptions(ability))
		if hit and ability.TriggerBleedOnHit then
			tryBleedHitTargets(hitTargets)
		end
		return true
	elseif slot == "C" then
		local cf = root.CFrame * CFrame.new(0, 1.5, -3.8)
		local size = Vector3.new(6.2, 5, 7.2)
		self.Effects:SpawnSlash(cf * CFrame.new(-0.8, 0, 0), Vector3.new(2.2, 3.8, 5.2), Color3.fromRGB(240, 240, 250), 0.14)
		self.Effects:SpawnSlash(cf * CFrame.Angles(0, math.rad(26), 0), Vector3.new(2.2, 3.8, 5.2), Color3.fromRGB(240, 240, 250), 0.14)
		local targets = self.Hitboxes:QueryBox(player, cf, size, {
			CFrame = cf,
			Size = size,
			Color = Color3.fromRGB(240, 240, 250),
		})
		local hit, hitTargets = self:DamageTargetsAndCollect(player, targets, ability.Damage, ability.Knockback, ability.Stun, self:GetAbilityHitOptions(ability))
		if hit and ability.BleedMarks then
			applyBleedMarksToHits(hitTargets, ability.BleedMarks)
		end
		return true
	elseif slot == "V" then
		local cf = root.CFrame * CFrame.new(0, 1.55, -3.2)
		local size = Vector3.new(4.6, 6.2, 5.8)
		self.Effects:SpawnSlash(cf, Vector3.new(2.5, 5.2, 2.8), Color3.fromRGB(250, 250, 255), 0.16)
		local targets = self.Hitboxes:QueryBox(player, cf, size, {
			CFrame = cf,
			Size = size,
			Color = Color3.fromRGB(250, 250, 255),
		})
		self:DamageTargets(
			player,
			targets,
			ability.Damage,
			ability.Knockback,
			ability.Stun,
			self:GetAbilityHitOptions(ability, {
				Launch = true,
			})
		)
		return true
	elseif slot == "G" then
		local target = self:GetLockedTargetFromPayload(player, payload, ability.Range)
			or self:FindClosestTargetToPosition(player, self:GetAimPosition(player, payload, ability.Range), ability.Range)
		local targetRoot = target and getCharacterRoot(target)
		if not target or not targetRoot then
			return false
		end

		task.delay(ability.Windup, function()
			if not self.PlayerState[player] or not target.Parent then
				return
			end

			local totalHits = math.max(1, tonumber(ability.Hits) or 1)
			local hitInterval = tonumber(ability.HitInterval) or 0.18

			for hitIndex = 1, totalHits do
				task.delay((hitIndex - 1) * hitInterval, function()
					if not self.PlayerState[player] then
						return
					end

					local liveRoot = getCharacterRoot(player.Character)
					local liveTargetRoot = getCharacterRoot(target)
					if not liveRoot or not liveTargetRoot then
						return
					end

					local sideSign = (hitIndex % 2 == 0) and -1 or 1
					local slashPosition = liveTargetRoot.Position + Vector3.new(1.8 * sideSign, 1.45, 0.45)
					local slashCf = CFrame.lookAt(slashPosition, liveTargetRoot.Position + Vector3.new(0, 1.4, 0))
					liveRoot.CFrame = CFrame.lookAt(liveRoot.Position, liveTargetRoot.Position)
					self.Effects:SpawnSlash(slashCf, Vector3.new(2.6, 3.2, 3.4), Color3.fromRGB(248, 248, 255), 0.12)

					local isFinalHit = hitIndex == totalHits
					local hit = self:DamageTarget(
						player,
						target,
						isFinalHit and (ability.FinisherDamage or ability.Damage) or ability.Damage,
						isFinalHit and (ability.FinisherKnockback or ability.Knockback) or ability.Knockback,
						isFinalHit and (ability.FinisherStun or ability.Stun) or ability.Stun,
						self:GetAbilityHitOptions(ability, {
							Launch = isFinalHit,
						})
					)
					if hit and isFinalHit and ability.TriggerBleedOnHit then
						self:TryTriggerSamuraiBleed(player, target)
					end
				end)
			end
		end)
		return true
	end

	return false
end

function CombatService:PerformNaoyaAbility(player, slot, ability, payload)
	local character = player.Character
	local root = getCharacterRoot(character)
	if not character or not root then
		return false
	end

	local function applyFrameMarksToHits(hitTargets, stacks)
		local uniqueTargets = {}
		for _, target in ipairs(hitTargets) do
			appendUniqueTarget(uniqueTargets, target)
		end
		for _, target in pairs(uniqueTargets) do
			self:ApplyNaoyaFrameMarks(player, target, stacks)
		end
	end

	local function tryFreezeHitTargets(hitTargets)
		local uniqueTargets = {}
		local frozeAny = false
		for _, target in ipairs(hitTargets) do
			appendUniqueTarget(uniqueTargets, target)
		end
		for _, target in pairs(uniqueTargets) do
			if self:TryTriggerNaoyaFrameFreeze(player, target) then
				frozeAny = true
			end
		end
		return frozeAny
	end

	if slot == "Z" then
		if forceCharacterStand(character) then
			RunService.Heartbeat:Wait()
		end
		root.CFrame = root.CFrame * CFrame.new(0, 0, -math.min(ability.Range * 0.55, 6.5))
		local cf = root.CFrame * CFrame.new(0, 1.5, -4.5)
		local size = Vector3.new(5, 5, 8)
		self.Effects:SpawnSlash(cf, Vector3.new(2.4, 3.2, 7), Color3.fromRGB(235, 235, 245), 0.15)
		local targets = self.Hitboxes:QueryBox(player, cf, size, {
			CFrame = cf,
			Size = size,
			Color = Color3.fromRGB(240, 240, 255),
		})
		local hit, hitTargets = self:DamageTargetsAndCollect(
			player,
			targets,
			ability.Damage,
			ability.Knockback,
			ability.Stun,
			self:GetAbilityHitOptions(ability)
		)
		if hit and ability.FrameMarks then
			applyFrameMarksToHits(hitTargets, ability.FrameMarks)
		end
		return true
	elseif slot == "X" then
		local cf = root.CFrame * CFrame.new(0, 1.5, -3.8)
		local size = Vector3.new(5, 5, 6)
		self.Effects:SpawnSlash(cf * CFrame.new(-0.8, 0, 0), Vector3.new(1.8, 4, 4), Color3.fromRGB(220, 220, 235), 0.15)
		self.Effects:SpawnSlash(cf * CFrame.new(0.8, 0, 0), Vector3.new(1.8, 4, 4), Color3.fromRGB(220, 220, 235), 0.15)
		local targets = self.Hitboxes:QueryBox(player, cf, size, {
			CFrame = cf,
			Size = size,
			Color = Color3.fromRGB(235, 235, 250),
		})
		local hit, firstHitTargets = self:DamageTargetsAndCollect(
			player,
			targets,
			math.floor(ability.Damage * 0.5),
			0,
			0.15,
			self:GetAbilityHitOptions(ability)
		)
		local combinedTargets = {}
		for _, target in ipairs(firstHitTargets) do
			table.insert(combinedTargets, target)
		end
		if hit then
			task.delay(0.12, function()
				if self.PlayerState[player] then
					local _, secondHitTargets = self:DamageTargetsAndCollect(
						player,
						targets,
						math.ceil(ability.Damage * 0.5),
						ability.Knockback,
						ability.Stun,
						self:GetAbilityHitOptions(ability)
					)
					for _, target in ipairs(secondHitTargets) do
						table.insert(combinedTargets, target)
					end
					if ability.FrameMarks then
						applyFrameMarksToHits(combinedTargets, ability.FrameMarks)
					end
				end
			end)
		end
		return true
	elseif slot == "C" then
		local cf = root.CFrame * CFrame.new(0, 1.6, -3.2)
		local size = Vector3.new(4.5, 6, 5)
		self.Effects:SpawnSlash(cf, Vector3.new(2.8, 4.5, 2.4), Color3.fromRGB(245, 245, 255), 0.15)
		local targets = self.Hitboxes:QueryBox(player, cf, size, {
			CFrame = cf,
			Size = size,
			Color = Color3.fromRGB(245, 245, 255),
		})
		local hit, hitTargets = self:DamageTargetsAndCollect(
			player,
			targets,
			ability.Damage,
			ability.Knockback,
			ability.Stun,
			self:GetAbilityHitOptions(ability, {
				Launch = true,
			})
		)
		if hit and ability.FreezeOnMaxFrameMarks then
			tryFreezeHitTargets(hitTargets)
		end
		return true
	elseif slot == "V" then
		if forceCharacterStand(character) then
			RunService.Heartbeat:Wait()
		end
		local target = self:GetLockedTargetFromPayload(player, payload, ability.Range)
			or self:FindClosestTargetToPosition(player, self:GetAimPosition(player, payload, ability.Range), ability.Range)
		local targetRoot = target and getCharacterRoot(target)
		if not target or not targetRoot then
			return false
		end

		local startPosition = root.Position
		local sequenceHits = math.max(2, tonumber(ability.SequenceHits) or 6)
		local sequenceInterval = tonumber(ability.SequenceInterval) or 0.08
		local sequenceDamage = tonumber(ability.SequenceDamage) or 3
		local sequenceStun = tonumber(ability.SequenceStun) or 0.08
		local sequenceRadius = tonumber(ability.SequenceRadius) or 2.4
		local ringDuration = tonumber(ability.RingDuration) or tonumber(ability.ActiveDuration) or 5
		local ringCloneCount = tonumber(ability.RingCloneCount) or 6
		local initialDelta = Vector3.new(targetRoot.Position.X - startPosition.X, 0, targetRoot.Position.Z - startPosition.Z)
		local dashDirection = initialDelta.Magnitude > 0.01 and initialDelta.Unit or Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z).Unit
		local flatLookTarget = Vector3.new(targetRoot.Position.X, root.Position.Y, targetRoot.Position.Z)
		root.CFrame = CFrame.lookAt(root.Position, flatLookTarget)
		self.Effects:CreateAfterimageRing(character, targetRoot, {
			Count = ringCloneCount,
			Radius = sequenceRadius,
			Color = Color3.fromRGB(55, 145, 255),
			Transparency = 0.18,
			Duration = ringDuration,
		})
		self.Effects:SpawnSlash(
			CFrame.lookAt(startPosition + Vector3.new(0, 1.4, 0), targetRoot.Position + Vector3.new(0, 1.4, 0)),
			Vector3.new(3.2, 3.6, math.max(7, initialDelta.Magnitude + 2)),
			Color3.fromRGB(255, 255, 255),
			0.16
		)

		local openingHit = self:DamageTarget(
			player,
			target,
			sequenceDamage,
			0,
			sequenceStun,
			self:GetAbilityHitOptions(ability, {
				NoKR = true,
			})
		)
		if openingHit and ability.FreezeOnMaxFrameMarks then
			self:TryTriggerNaoyaFrameFreeze(player, target)
		end

		for hitIndex = 2, sequenceHits do
			task.delay((hitIndex - 1) * sequenceInterval, function()
				if not self.PlayerState[player] then
					return
				end

				local liveRoot = getCharacterRoot(player.Character)
				local liveTargetRoot = getCharacterRoot(target)
				if not liveRoot or not liveTargetRoot then
					return
				end

				local orbitAngle = ((hitIndex - 1) / math.max(1, sequenceHits)) * math.pi * 2
				local impactOffset = Vector3.new(math.cos(orbitAngle) * sequenceRadius, 0, math.sin(orbitAngle) * sequenceRadius)
				local impactPosition = liveTargetRoot.Position + impactOffset + Vector3.new(0, 1.45, 0)
				local impactCf = CFrame.lookAt(impactPosition, liveTargetRoot.Position + Vector3.new(0, 1.45, 0))
				self.Effects:SpawnSlash(impactCf, Vector3.new(2.6, 3.2, 2.6), Color3.fromRGB(255, 255, 255), 0.11)

				local isFinalHit = hitIndex == sequenceHits
				self:DamageTarget(
					player,
					target,
					isFinalHit and ability.Damage or sequenceDamage,
					isFinalHit and ability.Knockback or 0,
					isFinalHit and ability.Stun or sequenceStun,
					self:GetAbilityHitOptions(ability, {
						Launch = isFinalHit,
						NoKR = true,
					})
				)
			end)
		end
		return true
	elseif slot == "G" then
		local target = self:GetLockedTargetFromPayload(player, payload, ability.Range)
			or self:FindClosestTargetToPosition(player, self:GetAimPosition(player, payload, ability.Range), ability.Range)
		local targetRoot = target and getCharacterRoot(target)
		if not target or not targetRoot then
			return false
		end

		task.delay(ability.Windup, function()
			if not self.PlayerState[player] or not target.Parent then
				return
			end

			local hitInterval = tonumber(ability.HitInterval) or 0.1
			local totalHits = math.max(1, tonumber(ability.Hits) or 1)
			local damageEvery = math.max(1, tonumber(ability.DamageEvery) or 1)
			local finalPoseDuration = tonumber(ability.FinalPoseDuration) or 0.3

			for hitIndex = 1, ability.Hits do
				task.delay((hitIndex - 1) * hitInterval, function()
					if not self.PlayerState[player] then
						return
					end

					local liveRoot = getCharacterRoot(player.Character)
					local liveTargetRoot = getCharacterRoot(target)
					if not liveRoot or not liveTargetRoot then
						return
					end

					local sideSign = (hitIndex % 2 == 0) and -1 or 1
					local orbitDepth = (hitIndex == totalHits) and 2.4 or 1.3
					local orbitHeight = (hitIndex == totalHits) and 0.25 or 0
					local facingTarget = liveTargetRoot.Position + Vector3.new(0, 1.2, 0)
					local offset = Vector3.new(2.2 * sideSign, orbitHeight, orbitDepth)
					local naoyaPosition = liveTargetRoot.Position + offset
					liveRoot.CFrame = CFrame.lookAt(naoyaPosition, facingTarget)

					local impact = liveTargetRoot.Position + Vector3.new(0, 1.5, 0)
					local cf = CFrame.lookAt(impact, impact + liveRoot.CFrame.LookVector)
					self.Effects:SpawnSlash(cf, Vector3.new(2.6, 3.2, 2.6), Color3.fromRGB(245, 245, 255), 0.12)
					local isFinalHit = hitIndex == ability.Hits
					local shouldDealDamage = isFinalHit or ((hitIndex - 1) % damageEvery == 0)
					if shouldDealDamage then
						self:DamageTarget(
							player,
							target,
							isFinalHit and (ability.FinisherDamage or ability.Damage) or ability.Damage,
							isFinalHit and (ability.FinisherKnockback or ability.Knockback) or math.max(8, math.floor(ability.Knockback * 0.5)),
							isFinalHit and (ability.FinisherStun or ability.Stun) or ability.Stun,
							self:GetAbilityHitOptions(ability, {Launch = isFinalHit})
						)
					end

					if isFinalHit then
						task.delay(0.03, function()
							local finalRoot = getCharacterRoot(player.Character)
							local finalTargetRoot = getCharacterRoot(target)
							if not finalRoot or not finalTargetRoot or not self.PlayerState[player] then
								return
							end

							local posePosition = finalTargetRoot.Position + Vector3.new(2.9, 0, 2)
							finalRoot.CFrame = CFrame.lookAt(posePosition, finalTargetRoot.Position + Vector3.new(0, 1.1, 0))
							task.delay(finalPoseDuration, function()
								if self.PlayerState[player] and player.Character and getCharacterRoot(player.Character) == finalRoot then
									finalRoot.AssemblyLinearVelocity = Vector3.zero
								end
							end)
						end)
					end
				end)
			end
		end)
		return true
	end

	return false
end

function CombatService:TryAbility(player, slot, payload)
	local state = self:GetState(player)
	local kit = self:GetKit(player)
	local abilities = self:GetModeAbilities(player)
	if not state or not kit or not abilities or self:IsActionLocked(player) or state.IsBlocking then
		return
	end

	local ability = abilities[slot]
	if not ability then
		return
	end

	local cooldownKey = self:GetCooldownKey(player, slot)
	local holdState = state.AbilityHoldStates and state.AbilityHoldStates[cooldownKey]
	local continuingHeldCast = ability.Holdable and holdState ~= nil
	if (state.CastLockUntil or 0) > now() and not continuingHeldCast then
		return
	end

	local cooldownReadyAt = state.Cooldowns[cooldownKey] or 0
	local allowBlasterSecondPress = kit.DisplayName == "Sans" and state.Mode == "Blasters" and slot == "X" and state.PendingBlasterShots > 0
	if cooldownReadyAt > now() and not allowBlasterSecondPress then
		return
	end

	if not allowBlasterSecondPress and not self:SpendAbilityCost(player, ability) then
		return
	end

	local startupDuration = continuingHeldCast and 0 or self:GetAbilityStartupDuration(ability)
	local castLockDuration = continuingHeldCast and 0 or self:GetAbilityCastLockDuration(player, slot, ability)

	if startupDuration > 0 then
		local appliedCooldown = self:GetAppliedAbilityCooldown(player, slot, ability)
		if not continuingHeldCast then
			self:ApplyCastLock(player, castLockDuration)
		end

		self:MarkInCombat(player)

		if not allowBlasterSecondPress then
			state.Cooldowns[cooldownKey] = now() + appliedCooldown
		end

		self.Remotes.CombatState:FireAllClients({
			Type = "Ability",
			Player = player.UserId,
			Slot = slot,
			Name = ability.Name,
			Cooldown = appliedCooldown,
			CooldownKey = cooldownKey,
			KitId = state.KitId,
			Mode = state.Mode,
		})

		local castToken = state.AbilityCastToken or 0
		task.delay(startupDuration, function()
			if not self:IsAbilityCastTokenValid(player, castToken) then
				return
			end
			self:PerformAbilityByKit(player, slot, ability, payload)
		end)
		return
	end

	local success = self:PerformAbilityByKit(player, slot, ability, payload)
	if not success then
		if not allowBlasterSecondPress then
			self:RefundAbilityCost(player, ability)
		end
		return
	end

	if not continuingHeldCast then
		self:ApplyCastLock(player, castLockDuration)
	end

	self:MarkInCombat(player)

	local appliedCooldown = self:GetAppliedAbilityCooldown(player, slot, ability)
	if not allowBlasterSecondPress then
		state.Cooldowns[cooldownKey] = now() + appliedCooldown
	end

	self.Remotes.CombatState:FireAllClients({
		Type = "Ability",
		Player = player.UserId,
		Slot = slot,
		Name = ability.Name,
		Cooldown = appliedCooldown,
		CooldownKey = cooldownKey,
		KitId = state.KitId,
		Mode = state.Mode,
	})
end

function CombatService:TryTelekinesisMove(player, payload)
	local state = self:GetState(player)
	local kit = self:GetKit(player)
	if not state or not kit or state.KitId ~= "Sans" or state.Mode ~= "Telekinesis" or self:IsActionLocked(player) or state.IsBlocking then
		return
	end

	local direction = type(payload) == "table" and payload.Direction or nil
	if not direction then
		return
	end

	local sourceRoot = getCharacterRoot(player.Character)
	local ability = kit.Abilities and kit.Abilities.Telekinesis and kit.Abilities.Telekinesis.Z
	if not sourceRoot or not ability then
		return
	end

	local heldTarget = self:FindTelekinesisTargetByKey(player, state.HeldTargetUserId)
	local targetRoot = heldTarget and getCharacterRoot(heldTarget)
	if not targetRoot then
		self:ResetTelekinesisState(state)
		return
	end

	local offsets = {
		W = sourceRoot.CFrame.LookVector,
		S = -sourceRoot.CFrame.LookVector,
		A = -sourceRoot.CFrame.RightVector,
		D = sourceRoot.CFrame.RightVector,
	}

	local horizontalDirection = offsets[direction]
	if direction ~= "Space" and not horizontalDirection then
		return
	end

	local launchVelocity
	if direction == "Space" then
		launchVelocity = (sourceRoot.CFrame.LookVector * 68) + Vector3.new(0, 110, 0)
	else
		launchVelocity = (horizontalDirection.Unit * 132) + Vector3.new(0, 18, 0)
	end

	targetRoot.AssemblyLinearVelocity = launchVelocity
	local launchForce = Instance.new("BodyVelocity")
	launchForce.MaxForce = Vector3.new(1, 1, 1) * 85000
	launchForce.Velocity = launchVelocity
	launchForce.Parent = targetRoot
	Debris:AddItem(launchForce, direction == "Space" and 0.16 or 0.2)
	if launchVelocity.Y > 0 then
		self:PlayKnockbackAnimations(heldTarget, Vector3.new(launchVelocity.X, 0, launchVelocity.Z))
	end
	self.Effects:SpawnZone(targetRoot.Position, 2.8, self:GetSansEffectPalette(player).ZoneBright)
	self:ApplyStun(heldTarget, 0.35, {PreserveMomentum = true})
	self:ResetTelekinesisState(state)

	self.Remotes.CombatState:FireClient(player, {
		Type = "TelekinesisCast",
		Player = player.UserId,
		Direction = direction,
	})
end

function CombatService:HandleRequest(player, payload)
	if typeof(payload) ~= "table" then
		return
	end

	local action = payload.Action
	if action == "M1" then
		self:TryM1(player, payload)
	elseif action == "Dash" then
		self:TryDash(player, payload)
	elseif action == "SetRun" then
		self:SetRunning(player, payload.Enabled)
	elseif action == "BlockStart" then
		self:SetBlocking(player, true)
	elseif action == "BlockEnd" then
		self:SetBlocking(player, false)
	elseif action == "Ability" then
		self:TryAbility(player, payload.Slot, payload)
	elseif action == "CycleKit" then
		self:CycleKit(player)
	elseif action == "SelectKit" then
		self:SetKit(player, payload.KitId)
	elseif action == "SelectSkin" then
		if not self:SetSelectedSkin(player, payload.KitId, payload.SkinId) then
			self:SendMessage(player, "That skin is locked.")
		else
			self:SendMessage(player, "Skin selected.")
		end
	elseif action == "RequestProfile" then
		self:SendProfile(player)
	elseif action == "ToggleRankedQueue" then
		if self:IsQueuedForRanked(player) then
			self:LeaveRankedQueue(player, false)
		else
			self:QueueForRanked(player)
		end
	elseif action == "TeleportMenuDestination" then
		self:TeleportPlayerToMenuDestination(player, payload.Destination)
	elseif action == "RespondToDuel" then
		self:RespondToDuelRequest(player, payload.Accepted == true)
	elseif action == "SwitchMode" then
		self:CycleMode(player, payload.Direction)
	elseif action == "TelekinesisMove" then
		self:TryTelekinesisMove(player, payload)
	elseif action == "EndHeldAbility" then
		self:FinalizeHeldAbility(player, payload.Slot)
	elseif action == "AdminCommand" then
		local commandText = type(payload.CommandText) == "string" and payload.CommandText or ""
		commandText = string.match(commandText, "^%s*(.-)%s*$") or ""
		if commandText ~= "" then
			if string.sub(commandText, 1, 1) ~= "/" then
				commandText = "/" .. commandText
			end
			self:HandleChatCommand(player, commandText)
		end
	end
end

return CombatService
