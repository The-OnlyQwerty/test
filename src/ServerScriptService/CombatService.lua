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
local rankedQueueStore = MemoryStoreService:GetSortedMap("JudgementDividedRankedQueue_v1")
local rankedAssignmentStore = MemoryStoreService:GetSortedMap("JudgementDividedRankedAssignments_v1")
local rankedLockStore = MemoryStoreService:GetSortedMap("JudgementDividedRankedLock_v1")

local function now()
	return os.clock()
end

local function getCharacterRoot(character)
	return character and character:FindFirstChild("HumanoidRootPart")
end

local function getHumanoid(character)
	return character and character:FindFirstChildOfClass("Humanoid")
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

local function makeUrl(baseUrl, path)
	if string.sub(baseUrl, -1) == "/" then
		baseUrl = string.sub(baseUrl, 1, -2)
	end
	return baseUrl .. path
end

function CombatService.new(remotes)
	local self = setmetatable({}, CombatService)
	self.Remotes = remotes
	self.PlayerState = {}
	self.PlayerProfiles = {}
	self.PendingDuelRequests = {}
	self.ActiveDuels = {}
	self.RankedQueue = {}
	self.RankedMatchData = nil
	self.BridgeStatus = "unknown"
	self.Effects = EffectService.new()
	self.Hitboxes = HitboxService.new(remotes)
	return self
end

function CombatService:IsTrainingServer()
	return workspace:GetAttribute(Constants.TRAINING_SERVER_ATTRIBUTE) == true or isTrainingPlaceId(game.PlaceId)
end

function CombatService:IsRankedMatchServer()
	return self.RankedMatchData ~= nil
end

function CombatService:GetServerRole()
	return self:IsTrainingServer() and "training" or "main"
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
	Players.PlayerAdded:Connect(function(player)
		self:OnPlayerAdded(player)
	end)

	Players.PlayerRemoving:Connect(function(player)
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
		IsBlocking = false,
		IsStunnedUntil = 0,
		LastDashAt = 0,
		Mode = "Bones",
		CounterUntil = 0,
		IFrameUntil = 0,
		ActiveBlasters = 0,
		PendingBlasterShots = 0,
		HeldTargetUserId = nil,
		LastBlockEndedAt = 0,
		BlockAura = nil,
		Buffs = {},
	}
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
		},
	}
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
	local skins = SkinCatalog[kitId]
	if not profile or not skins then
		return false
	end

	for _, skin in ipairs(skins) do
		if skin.Id == skinId then
			return profile.Kills >= skin.UnlockKills
		end
	end

	return false
end

function CombatService:SetSelectedSkin(player, kitId, skinId)
	local profile = self:GetProfile(player)
	if not profile or not self:IsSkinUnlocked(player, kitId, skinId) then
		return false
	end

	profile.SelectedSkins[kitId] = skinId
	self:SaveProfile(player)
	self:SendProfile(player)
	return true
end

function CombatService:SendProfile(player)
	local profile = self:GetProfile(player)
	if not profile then
		return
	end

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
	self:SendMessage(winnerPlayer, string.format("Ranked win: +%d rating (%d).", winnerGain, winnerProfile.RankedRating))
	self:SendMessage(loserPlayer, string.format("Ranked loss: -%d rating (%d).", loserLoss, loserProfile.RankedRating))
end

function CombatService:TryStartRankedMatch()
	if self:IsTrainingServer() or self:IsRankedMatchServer() then
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
			if value.UserId and value.JobId and value.PlaceId and not chosen[value.UserId] then
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

	local reserveSuccess, reservedServerCode = pcall(function()
		return TeleportService:ReserveServer(Constants.MAIN_GAME_PLACE_ID)
	end)
	if not reserveSuccess or not reservedServerCode then
		return
	end

	local matchId = HttpService:GenerateGUID(false)
	local assignment = {
		MatchId = matchId,
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
					Constants.MAIN_GAME_PLACE_ID,
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
	local state = self:GetDefaultState()
	self.PlayerState[player] = state

	player.CharacterAdded:Connect(function(character)
		self:OnCharacterAdded(player, character)
	end)

	player.Chatted:Connect(function(message)
		self:HandleChatCommand(player, message)
	end)

	if player.Character then
		self:OnCharacterAdded(player, player.Character)
	end

	self:SendProfile(player)
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

	state.LastM1At = 0
	state.ComboStep = 0
	state.M1CooldownUntil = 0
	state.IsBlocking = false
	state.IsStunnedUntil = 0
	state.LastDashAt = 0
	state.CounterUntil = 0
	state.IFrameUntil = 0
	state.ActiveBlasters = 0
	state.PendingBlasterShots = 0
	state.HeldTargetUserId = nil
	state.LastBlockEndedAt = 0
	if state.BlockAura then
		self.Effects:DestroyBlockAura(state.BlockAura)
		state.BlockAura = nil
	end
	state.Mode = kit.Modes and kit.Modes[1] or "Base"
	local buffs = state.Buffs or {}

	humanoid.MaxHealth = buffs.Health or kit.Stats.Health
	humanoid.Health = buffs.Health or kit.Stats.Health
	humanoid.WalkSpeed = Constants.DEFAULT_WALKSPEED

	character:SetAttribute("KitId", state.KitId)
	character:SetAttribute("Mode", state.Mode)
	character:SetAttribute("Blocking", false)
	character:SetAttribute("Stunned", false)
	character:SetAttribute("Mana", buffs.Mana or kit.Stats.Mana or 0)
	character:SetAttribute("Stamina", buffs.Stamina or kit.Stats.Stamina or 0)
	character:SetAttribute("Attack", buffs.Attack or kit.Stats.Attack or 0)
	character:SetAttribute("Defense", buffs.Defense or kit.Stats.Defense or 0)
	character:SetAttribute("ActiveBlasters", 0)
	local profile = self:GetProfile(player)
	character:SetAttribute("SelectedSkin", profile and profile.SelectedSkins[state.KitId] or "Default")

	humanoid.Died:Connect(function()
		self:HandleCharacterDeath(player)
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

function CombatService:IsActionLocked(player)
	local state = self:GetState(player)
	return not state or state.IsStunnedUntil > now()
end

function CombatService:SendMessage(player, text)
	self.Remotes.CombatState:FireClient(player, {
		Type = "SystemMessage",
		Text = text,
	})
end

function CombatService:GetResource(player, resourceName)
	local character = player.Character
	return character and (character:GetAttribute(resourceName) or 0) or 0
end

function CombatService:SetResource(player, resourceName, value)
	setCharacterAttribute(player, resourceName, math.max(0, math.floor(value)))
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
			if state and kit and player.Character then
				local manaMax = kit.Stats.Mana or 0
				if manaMax > 0 then
					local manaGain = Constants.MANA_REGEN_PER_SECOND * 0.25
					self:SetResource(player, "Mana", math.min(manaMax, self:GetResource(player, "Mana") + manaGain))
				end

				local staminaMax = kit.Stats.Stamina or 0
				if staminaMax > 0 then
					local staminaGain = Constants.STAMINA_REGEN_PER_SECOND * 0.25
					self:SetResource(player, "Stamina", math.min(staminaMax, self:GetResource(player, "Stamina") + staminaGain))
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

function CombatService:SetKit(player, kitId)
	local state = self:GetState(player)
	local kit = self:GetKitById(kitId)
	if not state or not kit then
		return
	end

	state.KitId = kitId
	state.Cooldowns = {}
	state.Mode = kit.Modes and kit.Modes[1] or "Base"
	state.ActiveBlasters = 0
	state.PendingBlasterShots = 0
	state.HeldTargetUserId = nil

	if player.Character then
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
		self:SetKit(player, state.KitId == "Sans" and "Magnus" or "Sans")
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

	state.LastM1At = 0
	state.ComboStep = 0
	state.M1CooldownUntil = 0
	state.Cooldowns = {}
	state.IsBlocking = false
	state.IsStunnedUntil = 0
	state.LastDashAt = 0
	state.CounterUntil = 0
	state.IFrameUntil = 0
	state.ActiveBlasters = 0
	state.PendingBlasterShots = 0
	state.HeldTargetUserId = nil
	state.LastBlockEndedAt = 0

	if state.BlockAura then
		self.Effects:DestroyBlockAura(state.BlockAura)
		state.BlockAura = nil
	end

	humanoid.MaxHealth = buffs.Health or kit.Stats.Health
	humanoid.Health = buffs.Health or kit.Stats.Health
	humanoid.WalkSpeed = Constants.DEFAULT_WALKSPEED
	root.AssemblyLinearVelocity = Vector3.zero
	root.AssemblyAngularVelocity = Vector3.zero

	character:SetAttribute("Blocking", false)
	character:SetAttribute("BlockName", "")
	character:SetAttribute("Stunned", false)
	character:SetAttribute("Mana", buffs.Mana or kit.Stats.Mana or 0)
	character:SetAttribute("Stamina", buffs.Stamina or kit.Stats.Stamina or 0)
	character:SetAttribute("Attack", buffs.Attack or kit.Stats.Attack or 0)
	character:SetAttribute("Defense", buffs.Defense or kit.Stats.Defense or 0)
	character:SetAttribute("ActiveBlasters", 0)

	return true
end

function CombatService:ResetDummyState(dummy)
	local humanoid = getHumanoid(dummy)
	local root = getCharacterRoot(dummy)
	if not humanoid or not root then
		return false
	end

	humanoid.MaxHealth = 400
	humanoid.Health = humanoid.MaxHealth
	humanoid.WalkSpeed = 0
	root.AssemblyLinearVelocity = Vector3.zero
	root.AssemblyAngularVelocity = Vector3.zero
	dummy:SetAttribute("Stunned", false)
	dummy:SetAttribute("Blocking", dummy:GetAttribute("DummyBehavior") == "Blocking")

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
		self:SendMessage(player, string.format("Ranked Rating: %d | W: %d | L: %d", rating, wins, losses))
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
	state.HeldTargetUserId = nil
	state.PendingBlasterShots = 0
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

	if self:IsActionLocked(player) and isBlocking then
		return
	end

	if isBlocking and state.IsBlocking then
		return
	end

	if isBlocking and now() - state.LastBlockEndedAt < Constants.BLOCK_COOLDOWN then
		self:SendMessage(player, "Block is on cooldown.")
		return
	end

	state.IsBlocking = isBlocking
	humanoid.WalkSpeed = isBlocking and Constants.BLOCK_WALKSPEED or Constants.DEFAULT_WALKSPEED
	character:SetAttribute("Blocking", isBlocking)
	character:SetAttribute("BlockName", isBlocking and (self:GetKit(player).Block.Name or "Block") or "")

	if isBlocking then
		local root = getCharacterRoot(character)
		if root then
			if state.BlockAura then
				self.Effects:DestroyBlockAura(state.BlockAura)
			end
			state.BlockAura = self.Effects:CreateBlockAura(root, (self:GetKit(player).DisplayName == "Sans") and Color3.fromRGB(145, 205, 255) or Color3.fromRGB(245, 245, 255))
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
			self.Effects:SpawnBlockWall(root, Color3.fromRGB(245, 245, 255))
		end
	end
end

function CombatService:ApplyStun(player, duration)
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
		state.IsStunnedUntil = math.max(state.IsStunnedUntil, now() + duration)
		character:SetAttribute("Stunned", true)

		task.delay(duration, function()
			if self.PlayerState[targetPlayer] and targetPlayer.Character and self.PlayerState[targetPlayer].IsStunnedUntil <= now() then
				targetPlayer.Character:SetAttribute("Stunned", false)
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

function CombatService:ApplyKnockback(attacker, target, knockback, launch)
	if knockback <= 0 then
		return
	end

	local attackerRoot = getCharacterRoot(attacker.Character)
	local targetRoot = getCharacterRoot(getTargetCharacter(target))
	if not attackerRoot or not targetRoot then
		return
	end

	local direction = targetRoot.Position - attackerRoot.Position
	if direction.Magnitude < 0.001 then
		direction = attackerRoot.CFrame.LookVector
	end

	local velocity = Instance.new("BodyVelocity")
	velocity.MaxForce = Vector3.new(1, 1, 1) * 50000
	velocity.Velocity = direction.Unit * knockback + Vector3.new(0, launch and knockback * 0.45 or 0, 0)
	velocity.Parent = targetRoot
	Debris:AddItem(velocity, 0.12)
end

function CombatService:ApplyKarmicRetribution(attacker, target)
	local attackerKit = self:GetKit(attacker)
	local passive = attackerKit and attackerKit.Passive
	if not passive then
		return
	end

	task.spawn(function()
		for _ = 1, passive.DotTicks do
			task.wait(passive.DotInterval)
			local humanoid = getHumanoid(getTargetCharacter(target))
			if not humanoid or humanoid.Health <= 0 then
				return
			end
			humanoid:TakeDamage(passive.DotDamage)
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
	local attackerRoot = getCharacterRoot(attacker.Character)
	if defenderRoot then
		self.Effects:SpawnCounterFlash(defenderRoot.Position)
		defenderRoot.CFrame = defenderRoot.CFrame + defenderRoot.CFrame.LookVector * -8
	end

	if attackerRoot then
		self.Effects:SpawnBoneBurst(attackerRoot.Position, 4, Color3.fromRGB(255, 245, 245))
	end

	self:ApplyStun(attacker, counterAbility.Stun)
	local attackerHumanoid = getHumanoid(attacker.Character)
	if attackerHumanoid and attackerHumanoid.Health > 0 then
		attackerHumanoid:TakeDamage(counterAbility.Damage)
	end

	self.Remotes.CombatState:FireAllClients({
		Type = "CounterTriggered",
		Player = defenderPlayer.UserId,
		Target = attacker.UserId,
	})

	return true
end

function CombatService:DamageTarget(attacker, target, damage, knockback, stun, options)
	options = options or {}

	local targetCharacter = getTargetCharacter(target)
	local targetPlayer = getTargetPlayer(target)
	if self:IsTrainingServer() and targetPlayer then
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

	local appliedDamage = damage
	local isBlocking = (targetState and targetState.IsBlocking) or (targetCharacter and targetCharacter:GetAttribute("Blocking"))
	if isBlocking then
		local reduction = (targetKit and targetKit.Block and targetKit.Block.DamageReduction) or 0.75
		appliedDamage = math.max(0, math.floor(damage * (1 - reduction)))
	end

	targetHumanoid:TakeDamage(appliedDamage)
	if targetPlayer then
		targetCharacter:SetAttribute("LastDamagedByUserId", attacker.UserId)
	end
	if stun and stun > 0 then
		self:ApplyStun(target, stun)
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
		Attacker = attacker.UserId,
		Target = targetPlayer and targetPlayer.UserId or targetCharacter.Name,
		Damage = appliedDamage,
	})

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

function CombatService:TryM1(player)
	local state = self:GetState(player)
	local kit = self:GetKit(player)
	local root = getCharacterRoot(player.Character)
	if not state or not kit or not root or self:IsActionLocked(player) or state.IsBlocking then
		return
	end

	if state.M1CooldownUntil > now() then
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

	local size = Vector3.new(7, 6, comboIndex >= 3 and 10 or 8)
	local cframe = root.CFrame * CFrame.new(0, 1.5, -4)
	local color = comboIndex >= 3 and Color3.fromRGB(30, 30, 35) or Color3.fromRGB(220, 220, 220)
	self.Effects:SpawnSlash(cframe, Vector3.new(5.5, 5.5, 1.5), color, 0.24)

	local targets = self.Hitboxes:QueryBox(player, cframe, size, {
		CFrame = cframe,
		Size = size,
		Color = Color3.fromRGB(255, 255, 255),
	})
	self:DamageTargets(player, targets, kit.M1Damage[comboIndex], kit.M1Knockback[comboIndex], Constants.M1_STUN_TIME, {
		Launch = comboIndex == 4,
	})

	self.Remotes.CombatState:FireAllClients({
		Type = "M1",
		Player = player.UserId,
		Combo = comboIndex,
	})

	if comboIndex >= #kit.M1Damage and (kit.M1ComboCooldown or 0) > 0 then
		state.M1CooldownUntil = now() + kit.M1ComboCooldown
		state.ComboStep = 0
	end
end

function CombatService:TryDash(player)
	local state = self:GetState(player)
	local root = getCharacterRoot(player.Character)
	local kit = self:GetKit(player)
	if not state or not root or self:IsActionLocked(player) then
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

	local velocity = Instance.new("BodyVelocity")
	velocity.MaxForce = Vector3.new(1, 0, 1) * 50000
	velocity.Velocity = root.CFrame.LookVector * Constants.DASH_SPEED
	velocity.Parent = root
	Debris:AddItem(velocity, Constants.DASH_TIME)

	if kit and kit.DisplayName == "Sans" then
		state.IFrameUntil = now() + Constants.DASH_TIME
	end

	self.Effects:SpawnSlash(root.CFrame, Vector3.new(3, 3, 3), Color3.fromRGB(115, 180, 255), 0.2)

	self.Remotes.CombatState:FireAllClients({
		Type = "Dash",
		Player = player.UserId,
	})
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

	if slot == "Z" then
		local aim = self:GetAimPosition(player, payload, ability.Range)
		local startPos = root.Position + Vector3.new(0, 2.2, 0)
		local endPos = startPos + clampVector(aim - startPos, ability.Range)
		local cf = CFrame.lookAt(startPos:Lerp(endPos, 0.5), endPos)
		local size = Vector3.new(3, 4, math.max(5, (endPos - startPos).Magnitude))
		self.Effects:SpawnBoneLine(startPos, endPos)
		local targets = self.Hitboxes:QueryBox(player, cf, size, {
			CFrame = cf,
			Size = size,
			Color = Color3.fromRGB(210, 240, 255),
		})
		return self:DamageTargets(player, targets, ability.Damage, ability.Knockback, ability.Stun)
	elseif slot == "X" then
		local target = self:FindClosestTargetToPosition(player, self:GetAimPosition(player, payload, ability.Range), ability.Range)
		if not target then
			return false
		end
		local targetRoot = getCharacterRoot(target)
		if not targetRoot then
			return false
		end
		state.IFrameUntil = now() + ability.IFrameTime
		self.Effects:SpawnBoneBurst(targetRoot.Position, 5)
		local cf = CFrame.new(targetRoot.Position)
		local size = Vector3.new(10, 8, 10)
		local targets = self.Hitboxes:QueryBox(player, cf, size, {
			CFrame = cf,
			Size = size,
			Color = Color3.fromRGB(240, 240, 255),
		})
		return self:DamageTargets(player, targets, ability.Damage, ability.Knockback, ability.Stun)
	elseif slot == "C" then
		local wallColor = math.random() < ability.BlueChance and Color3.fromRGB(100, 170, 255) or Color3.fromRGB(245, 245, 255)
		local cf = root.CFrame * CFrame.new(0, 1.5, -8)
		local size = Vector3.new(11, 6, 10)
		self.Effects:SpawnWaveWall(cf, Vector3.new(10, 5, 2), wallColor)
		local targets = self.Hitboxes:QueryBox(player, cf, size, {
			CFrame = cf,
			Size = size,
			Color = wallColor,
		})
		return self:DamageTargets(player, targets, ability.Damage, ability.Knockback, ability.Stun + (wallColor.B > 0.8 and 0.35 or 0))
	elseif slot == "V" then
		local position = root.Position
		self.Effects:SpawnZone(position, ability.Radius, Color3.fromRGB(200, 210, 255))
		local targets = self.Hitboxes:QueryRadius(player, position, ability.Radius, {
			CFrame = CFrame.new(position),
			Size = Vector3.new(ability.Radius * 2, ability.Radius * 2, ability.Radius * 2),
			Color = Color3.fromRGB(180, 205, 255),
			Shape = "Sphere",
			Duration = 0.3,
		})
		return self:DamageTargets(player, targets, ability.Damage, ability.Knockback, ability.Stun)
	elseif slot == "G" then
		state.CounterUntil = now() + ability.CounterWindow
		self.Effects:SpawnCounterFlash(root.Position)
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

	local target = self:FindClosestTargetToPosition(player, self:GetAimPosition(player, payload, ability.Range), ability.Range)
	local root = target and getCharacterRoot(target)
	if not target or not root then
		return false
	end

	self.Effects:SpawnZone(root.Position, 4, Color3.fromRGB(140, 180, 255))
	self.Hitboxes:BroadcastDebug({
		CFrame = CFrame.new(root.Position),
		Size = Vector3.new(7, 7, 7),
		Color = Color3.fromRGB(140, 180, 255),
		Shape = "Sphere",
		Duration = 0.25,
	})

	local state = self:GetState(player)
	state.HeldTargetUserId = target.Name
	self:ApplyStun(target, ability.HoldDuration)
	self:DamageTarget(player, target, ability.Damage, 0, 0.2, {NoKR = true})

	task.delay(ability.HoldDuration, function()
		if self.PlayerState[player] and self.PlayerState[player].HeldTargetUserId == target.Name then
			self.PlayerState[player].HeldTargetUserId = nil
		end
	end)

	self.Remotes.CombatState:FireClient(player, {
		Type = "TelekinesisGrab",
		Target = target.Name,
	})
	return true
end

function CombatService:PerformSansBlasterAbility(player, slot, ability, payload)
	local state = self:GetState(player)
	local root = getCharacterRoot(player.Character)
	if not state or not root then
		return false
	end

	if slot == "Z" then
		if state.ActiveBlasters >= ability.MaxCount then
			self:SendMessage(player, "Blaster cap reached.")
			return false
		end
		state.ActiveBlasters += 1
		setCharacterAttribute(player, "ActiveBlasters", state.ActiveBlasters)
		local offset = root.CFrame.RightVector * (2.5 + state.ActiveBlasters * 1.2) + Vector3.new(0, 3, 0)
		self.Effects:SpawnBlaster(root.Position + offset)
		return true
	elseif slot == "X" then
		if state.ActiveBlasters <= 0 then
			self:SendMessage(player, "No blasters available.")
			return false
		end

		if state.PendingBlasterShots > 0 then
			local target = self:FindClosestTargetToPosition(player, self:GetAimPosition(player, payload, ability.Range), ability.Range)
			local targetRoot = target and getCharacterRoot(target)
			if not target or not targetRoot then
				return false
			end

			local shotCount = math.min(state.PendingBlasterShots, state.ActiveBlasters)
			state.ActiveBlasters -= shotCount
			state.PendingBlasterShots = 0
			setCharacterAttribute(player, "ActiveBlasters", state.ActiveBlasters)

			for index = 1, shotCount do
				local origin = root.Position + root.CFrame.RightVector * (index * 2.5) + Vector3.new(0, 3.2, 0)
				self.Effects:SpawnBeam(origin, targetRoot.Position + Vector3.new(0, 2, 0))
				local cf = CFrame.lookAt(origin:Lerp(targetRoot.Position, 0.5), targetRoot.Position)
				local size = Vector3.new(3, 4, math.max(6, (targetRoot.Position - origin).Magnitude))
				local targets = self.Hitboxes:QueryBox(player, cf, size, {
					CFrame = cf,
					Size = size,
					Color = Color3.fromRGB(120, 205, 255),
					Duration = 0.12,
				})
				self:DamageTargets(player, targets, ability.Damage, ability.Knockback, ability.Stun)
			end
			return true
		end

		state.PendingBlasterShots = math.min(ability.TrackCount, state.ActiveBlasters)
		self:SendMessage(player, "Blasters are tracking. Press X again to fire.")
		return true
	end

	return false
end

function CombatService:PerformMagnusAbility(player, slot, ability, payload)
	local root = getCharacterRoot(player.Character)
	if not root then
		return false
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
		return self:DamageTargets(player, targets, ability.Damage, 0, ability.Stun + 0.5)
	elseif slot == "X" then
		root.CFrame = root.CFrame * CFrame.new(0, 0, -math.min(ability.Range * 0.55, 7))
		local cf = root.CFrame * CFrame.new(0, 1.5, -5)
		local size = Vector3.new(5, 5, 9)
		self.Effects:SpawnSlash(cf, Vector3.new(2.5, 3.2, 7), Color3.fromRGB(20, 20, 20), 0.18)
		local targets = self.Hitboxes:QueryBox(player, cf, size, {
			CFrame = cf,
			Size = size,
			Color = Color3.fromRGB(30, 30, 30),
		})
		return self:DamageTargets(player, targets, ability.Damage, ability.Knockback, ability.Stun)
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
		local hit = self:DamageTargets(player, targets, math.floor(ability.Damage * 0.5), 0, 0.2)
		if hit then
			task.delay(0.18, function()
				if self.PlayerState[player] then
					self:DamageTargets(player, targets, math.ceil(ability.Damage * 0.5), ability.Knockback, ability.Stun)
				end
			end)
		end
		return hit
	elseif slot == "V" then
		local cf = root.CFrame * CFrame.new(0, 1.5, -3.5)
		local size = Vector3.new(5, 6, 5)
		self.Effects:SpawnSlash(cf, Vector3.new(3, 4, 3), Color3.fromRGB(255, 255, 255), 0.15)
		local targets = self.Hitboxes:QueryBox(player, cf, size, {
			CFrame = cf,
			Size = size,
			Color = Color3.fromRGB(245, 245, 245),
		})
		return self:DamageTargets(player, targets, ability.Damage, ability.Knockback, ability.Stun, {Launch = true})
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
					self:DamageTargets(player, targets, ability.Damage, ability.Knockback, ability.Stun)
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
	local cooldownReadyAt = state.Cooldowns[cooldownKey] or 0
	local allowBlasterSecondPress = kit.DisplayName == "Sans" and state.Mode == "Blasters" and slot == "X" and state.PendingBlasterShots > 0
	if cooldownReadyAt > now() and not allowBlasterSecondPress then
		return
	end

	if not allowBlasterSecondPress and not self:SpendAbilityCost(player, ability) then
		return
	end

	local success = false
	if kit.DisplayName == "Sans" then
		if state.Mode == "Bones" then
			success = self:PerformSansBonesAbility(player, slot, ability, payload)
		elseif state.Mode == "Telekinesis" then
			success = self:PerformSansTelekinesisAbility(player, slot, ability, payload)
		elseif state.Mode == "Blasters" then
			success = self:PerformSansBlasterAbility(player, slot, ability, payload)
		end
	elseif kit.DisplayName == "Magnus" then
		success = self:PerformMagnusAbility(player, slot, ability, payload)
	end

	if not success then
		if not allowBlasterSecondPress then
			self:RefundAbilityCost(player, ability)
		end
		return
	end

	if not allowBlasterSecondPress then
		state.Cooldowns[cooldownKey] = now() + ability.Cooldown
	end

	self.Remotes.CombatState:FireAllClients({
		Type = "Ability",
		Player = player.UserId,
		Slot = slot,
		Name = ability.Name,
		Cooldown = ability.Cooldown,
		CooldownKey = cooldownKey,
		KitId = state.KitId,
		Mode = state.Mode,
	})
end

function CombatService:TryTelekinesisMove(player, direction)
	local state = self:GetState(player)
	if not state or state.KitId ~= "Sans" or state.Mode ~= "Telekinesis" then
		return
	end

	local heldTarget
	for _, target in ipairs(self:GetAllPotentialTargets(player)) do
		if target.Name == state.HeldTargetUserId then
			heldTarget = target
			break
		end
	end

	local targetRoot = heldTarget and getCharacterRoot(heldTarget)
	local sourceRoot = getCharacterRoot(player.Character)
	if not targetRoot or not sourceRoot then
		return
	end

	local offsets = {
		W = sourceRoot.CFrame.LookVector * 10,
		S = -sourceRoot.CFrame.LookVector * 10,
		A = -sourceRoot.CFrame.RightVector * 10,
		D = sourceRoot.CFrame.RightVector * 10,
		Space = Vector3.new(0, 14, 0),
	}

	local offset = offsets[direction]
	if not offset then
		return
	end

	targetRoot.CFrame = targetRoot.CFrame + offset
	self.Effects:SpawnZone(targetRoot.Position, 2.8, Color3.fromRGB(100, 160, 255))
	self:ApplyStun(heldTarget, 0.35)
end

function CombatService:HandleRequest(player, payload)
	if typeof(payload) ~= "table" then
		return
	end

	local action = payload.Action
	if action == "M1" then
		self:TryM1(player)
	elseif action == "Dash" then
		self:TryDash(player)
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
	elseif action == "RespondToDuel" then
		self:RespondToDuelRequest(player, payload.Accepted == true)
	elseif action == "SwitchMode" then
		self:CycleMode(player, payload.Direction)
	elseif action == "TelekinesisMove" then
		self:TryTelekinesisMove(player, payload.Direction)
	end
end

return CombatService
