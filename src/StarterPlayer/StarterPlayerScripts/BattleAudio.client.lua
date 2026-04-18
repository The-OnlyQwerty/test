local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Constants = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Constants"))

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local combatState = remotes:WaitForChild("CombatState")

if playerGui:GetAttribute(Constants.GLOBAL_MUSIC_OVERRIDE_ATTRIBUTE) == nil then
	playerGui:SetAttribute(Constants.GLOBAL_MUSIC_OVERRIDE_ATTRIBUTE, false)
end

local function isTrainingServer()
	if Workspace:GetAttribute(Constants.TRAINING_SERVER_ATTRIBUTE) == true then
		return true
	end

	for _, placeId in ipairs(Constants.TRAINING_SERVER_PLACE_IDS) do
		if placeId == game.PlaceId then
			return true
		end
	end

	return false
end

local function createSound(name, soundId)
	local sound = Instance.new("Sound")
	sound.Name = name
	sound.Looped = true
	sound.Volume = 0
	sound.RollOffMaxDistance = 0
	sound.SoundId = soundId ~= 0 and ("rbxassetid://" .. tostring(soundId)) or ""
	sound.Parent = SoundService
	return sound
end

local function buildThemeInfo(themeKey, songName, creatorName, soundIds)
	local normalizedSoundIds = {}
	if type(soundIds) == "table" then
		for _, soundId in ipairs(soundIds) do
			local numericSoundId = tonumber(soundId) or 0
			if numericSoundId ~= 0 then
				table.insert(normalizedSoundIds, numericSoundId)
			end
		end
	else
		local numericSoundId = tonumber(soundIds) or 0
		if numericSoundId ~= 0 then
			table.insert(normalizedSoundIds, numericSoundId)
		end
	end

	if #normalizedSoundIds == 0 then
		return nil
	end

	return {
		ThemeKey = themeKey,
		SoundId = normalizedSoundIds[1],
		SoundIds = normalizedSoundIds,
		SongName = songName or tostring(themeKey or "Theme"),
		CreatorName = creatorName or "",
	}
end

local function getBlackSilenceTheme(character)
	local kitId = character and character:GetAttribute("KitId")
	local selectedSkin = character and character:GetAttribute("SelectedSkin")
	if kitId ~= "Magnus" or selectedSkin ~= "BlackSilence" then
		return nil
	end

	local skinThemes = (((Constants.SKIN_THEME_IDS or {}).Magnus or {}).BlackSilence or {})
	local skinThemeMetadata = (((Constants.SKIN_THEME_METADATA or {}).Magnus or {}).BlackSilence or {})
	local inCombat = character:GetAttribute("InCombat") == true
	local phase = tonumber(character:GetAttribute("BlackSilencePhase")) or 1

	if not inCombat then
		local metadata = skinThemeMetadata.Neutral or {}
		return buildThemeInfo(
			"Magnus:BlackSilence:Neutral",
			metadata.SongName or "Roland01",
			metadata.CreatorName or "",
			skinThemes.Neutral
		)
	end

	if phase >= 3 then
		local metadata = skinThemeMetadata.Phase3 or {}
		return buildThemeInfo(
			"Magnus:BlackSilence:Phase3",
			metadata.SongName or "Gone Angels",
			metadata.CreatorName or "",
			skinThemes.Phase3
		)
	elseif phase == 2 then
		local metadata = skinThemeMetadata.Phase2 or {}
		return buildThemeInfo(
			"Magnus:BlackSilence:Phase2",
			metadata.SongName or "Roland03",
			metadata.CreatorName or "",
			{skinThemes.Phase2, skinThemes.Phase2Part2}
		)
	end

	local metadata = skinThemeMetadata.Phase1 or {}
	return buildThemeInfo(
		"Magnus:BlackSilence:Phase1",
		metadata.SongName or "Roland02",
		metadata.CreatorName or "",
		skinThemes.Phase1
	)
end

local function getCurrentCharacterTheme()
	local character = player.Character
	if not character then
		return nil
	end

	local kitId = character:GetAttribute("KitId")
	local selectedSkin = character:GetAttribute("SelectedSkin")
	local blackSilenceTheme = getBlackSilenceTheme(character)
	if blackSilenceTheme then
		return blackSilenceTheme
	end

	local characterThemeSoundId = tonumber(character:GetAttribute("ThemeSoundId")) or 0
	if characterThemeSoundId ~= 0 then
		local skinThemes = kitId and (Constants.SKIN_THEME_IDS or {})[kitId]
		local skinThemeMetadata = kitId and (Constants.SKIN_THEME_METADATA or {})[kitId]
		if type(selectedSkin) == "string" and selectedSkin ~= "" and type(skinThemes) == "table" and type(skinThemes[selectedSkin]) == "table" then
			for phaseName, soundId in pairs(skinThemes[selectedSkin]) do
				if tonumber(soundId) == characterThemeSoundId then
					local metadata = skinThemeMetadata and skinThemeMetadata[selectedSkin] and skinThemeMetadata[selectedSkin][phaseName] or {}
					return {
						ThemeKey = string.format("%s:%s:%s", tostring(kitId), tostring(selectedSkin), tostring(phaseName)),
						SoundId = characterThemeSoundId,
						SongName = metadata.SongName or tostring(selectedSkin),
						CreatorName = metadata.CreatorName or "",
					}
				end
			end
		end

		local metadata = (Constants.CHARACTER_THEME_METADATA or {})[kitId] or {}
		return {
			ThemeKey = tostring(selectedSkin or kitId or "CharacterTheme"),
			SoundId = characterThemeSoundId,
			SongName = metadata.SongName or tostring(kitId or "Character Theme"),
			CreatorName = metadata.CreatorName or "",
		}
	end

	if type(kitId) ~= "string" or kitId == "" then
		return nil
	end

	local soundId = tonumber((Constants.CHARACTER_THEME_IDS or {})[kitId]) or 0
	if soundId == 0 then
		return nil
	end

	local metadata = (Constants.CHARACTER_THEME_METADATA or {})[kitId] or {}
	return {
		ThemeKey = kitId,
		SoundId = soundId,
		SongName = metadata.SongName or tostring(kitId),
		CreatorName = metadata.CreatorName or "",
	}
end

local sounds = {
	battle = createSound("BattleMusic", Constants.BATTLE_MUSIC_ID),
	tense = createSound("TenseBattleMusic", Constants.TENSE_BATTLE_MUSIC_ID),
	training = createSound("TrainingMusic", Constants.TRAINING_MUSIC_ID),
	theme = createSound("ThemeMusic", 0),
}

local targetVolumes = {
	battle = Constants.BATTLE_MUSIC_VOLUME or 0.42,
	tense = Constants.TENSE_BATTLE_MUSIC_VOLUME or 0.46,
	training = Constants.TRAINING_MUSIC_VOLUME or 0.42,
	theme = Constants.CHARACTER_THEME_VOLUME or 0.5,
}

local tweenTokens = {}
local characterConnections = {}
local currentMode = nil
local currentThemeSoundId = 0
local currentTrackKey = nil
local globalOverride = nil
local themeNotificationNonce = 0
local showThemeNotification
local themeSoundNeedsRestart = false
local currentThemeSequenceIds = {}
local currentThemeSequenceIndex = 0
local TRACK_NOTIFICATION_METADATA = {
	battle = {
		Key = "battle",
		SongName = "Battle Theme",
		CreatorName = "AstralBlue",
	},
	tense = {
		Key = "tense",
		SongName = "Tense Battle Theme",
		CreatorName = "AstralBlue",
	},
	training = {
		Key = "training",
		SongName = "Training Theme",
		CreatorName = "AstralBlue",
	},
}

local function create(instanceType, props)
	local instance = Instance.new(instanceType)
	for key, value in pairs(props) do
		instance[key] = value
	end
	return instance
end

local themeGui = create("ScreenGui", {
	Name = "ThemeAnnouncement",
	IgnoreGuiInset = true,
	ResetOnSpawn = false,
	Parent = playerGui,
})

local themeBanner = create("Frame", {
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, -94),
	Size = UDim2.fromOffset(420, 78),
	BackgroundColor3 = Color3.fromRGB(18, 18, 24),
	BackgroundTransparency = 0.08,
	BorderSizePixel = 0,
	Visible = false,
	Parent = themeGui,
})
create("UICorner", {
	CornerRadius = UDim.new(0, 16),
	Parent = themeBanner,
})
create("UIStroke", {
	Color = Color3.fromRGB(255, 189, 74),
	Thickness = 1.6,
	Transparency = 0.15,
	Parent = themeBanner,
})

local accentBar = create("Frame", {
	Position = UDim2.new(0, 0, 0, 0),
	Size = UDim2.new(0, 6, 1, 0),
	BackgroundColor3 = Color3.fromRGB(255, 176, 58),
	BorderSizePixel = 0,
	Parent = themeBanner,
})
create("UICorner", {
	CornerRadius = UDim.new(0, 16),
	Parent = accentBar,
})

local themeCaption = create("TextLabel", {
	BackgroundTransparency = 1,
	Position = UDim2.fromOffset(18, 10),
	Size = UDim2.new(1, -36, 0, 16),
	Font = Enum.Font.GothamBold,
	Text = "NOW PLAYING",
	TextColor3 = Color3.fromRGB(255, 200, 108),
	TextSize = 12,
	TextXAlignment = Enum.TextXAlignment.Left,
	Parent = themeBanner,
})

local themeTitle = create("TextLabel", {
	BackgroundTransparency = 1,
	Position = UDim2.fromOffset(18, 25),
	Size = UDim2.new(1, -36, 0, 24),
	Font = Enum.Font.Arcade,
	Text = "",
	TextColor3 = Color3.fromRGB(245, 244, 240),
	TextSize = 20,
	TextXAlignment = Enum.TextXAlignment.Left,
	TextTruncate = Enum.TextTruncate.AtEnd,
	Parent = themeBanner,
})

local themeCreator = create("TextLabel", {
	BackgroundTransparency = 1,
	Position = UDim2.fromOffset(18, 50),
	Size = UDim2.new(1, -36, 0, 16),
	Font = Enum.Font.GothamMedium,
	Text = "",
	TextColor3 = Color3.fromRGB(211, 206, 196),
	TextSize = 12,
	TextXAlignment = Enum.TextXAlignment.Left,
	TextTruncate = Enum.TextTruncate.AtEnd,
	Parent = themeBanner,
})

local function disconnectCharacterSignals()
	for _, connection in ipairs(characterConnections) do
		connection:Disconnect()
	end
	table.clear(characterConnections)
end

local function tweenSound(sound, targetVolume, shouldPlay)
	if not sound then
		return
	end

	local token = (tweenTokens[sound] or 0) + 1
	tweenTokens[sound] = token

	if shouldPlay and sound.SoundId ~= "" and not sound.IsPlaying then
		sound:Play()
	end

	local tween = TweenService:Create(sound, TweenInfo.new(Constants.GAMEPLAY_MUSIC_FADE_TIME or 0.4), {
		Volume = targetVolume,
	})
	tween:Play()
	tween.Completed:Connect(function()
		if tweenTokens[sound] ~= token then
			return
		end
		if targetVolume <= 0.001 and sound.IsPlaying then
			sound:Stop()
		end
	end)
end

local function resolveMode()
	if globalOverride and tonumber(globalOverride.SoundId) and tonumber(globalOverride.SoundId) ~= 0 then
		return "theme", buildThemeInfo(
			string.format("override:%s", tostring(globalOverride.ThemeKey or "theme")),
			globalOverride.SongName or globalOverride.ThemeName or "Unknown Theme",
			globalOverride.CreatorName or "",
			tonumber(globalOverride.SoundId)
		), {
			Key = string.format("override:%s:%s", tostring(globalOverride.ThemeKey or "theme"), tostring(globalOverride.SoundId)),
			SongName = globalOverride.SongName or globalOverride.ThemeName or "Unknown Theme",
			CreatorName = globalOverride.CreatorName or "",
		}
	end

	if playerGui:GetAttribute(Constants.MENU_ATTRIBUTE) == true then
		return nil, nil, nil
	end

	if isTrainingServer() then
		return "training", nil, TRACK_NOTIFICATION_METADATA.training
	end

	local characterTheme = getCurrentCharacterTheme()
	if characterTheme then
		return "theme", characterTheme, {
			Key = string.format("theme:%s:%s", tostring(characterTheme.ThemeKey or "theme"), tostring(characterTheme.SoundId)),
			SongName = characterTheme.SongName or tostring(characterTheme.ThemeKey or "Character Theme"),
			CreatorName = characterTheme.CreatorName or "",
		}
	end

	local character = player.Character
	if character and character:GetAttribute("InCombat") == true then
		return "tense", nil, TRACK_NOTIFICATION_METADATA.tense
	end

	return "battle", nil, TRACK_NOTIFICATION_METADATA.battle
end

local function themeSequencesMatch(soundIds)
	if #currentThemeSequenceIds ~= #soundIds then
		return false
	end
	for index, soundId in ipairs(soundIds) do
		if currentThemeSequenceIds[index] ~= soundId then
			return false
		end
	end
	return true
end

local function applyThemeSound(themeInfo)
	local soundIds = (themeInfo and themeInfo.SoundIds) or {}
	local soundId = soundIds[1] or 0
	local soundIdText = soundId ~= 0 and ("rbxassetid://" .. tostring(soundId)) or ""
	local isSequence = #soundIds > 1
	local sequenceChanged = not themeSequencesMatch(soundIds)
	if sounds.theme.SoundId ~= soundIdText or sounds.theme.Looped == isSequence or sequenceChanged then
		themeSoundNeedsRestart = true
		if sounds.theme.IsPlaying then
			sounds.theme:Stop()
		end
		sounds.theme.TimePosition = 0
		sounds.theme.SoundId = soundIdText
	end
	sounds.theme.Looped = not isSequence
	currentThemeSoundId = soundId
	currentThemeSequenceIds = soundIds
	currentThemeSequenceIndex = #soundIds > 0 and 1 or 0
end

local function refreshAudio()
	local nextMode, nextThemeInfo, nextTrackInfo = resolveMode()
	local nextTrackKey = nextTrackInfo and nextTrackInfo.Key or nextMode or "none"
	local nextThemeSoundIds = (nextThemeInfo and nextThemeInfo.SoundIds) or {}
	local nextThemeSoundId = nextThemeInfo and nextThemeInfo.SoundId or 0
	local nextThemeSoundIdText = nextThemeSoundId ~= 0 and ("rbxassetid://" .. tostring(nextThemeSoundId)) or ""
	local themeAlreadyActive = nextMode ~= "theme"
		or (
			currentThemeSoundId == nextThemeSoundId
			and sounds.theme.SoundId == nextThemeSoundIdText
			and themeSequencesMatch(nextThemeSoundIds)
			and sounds.theme.IsPlaying
		)
	if currentMode == nextMode and currentTrackKey == nextTrackKey and themeAlreadyActive then
		return
	end

	currentMode = nextMode
	currentTrackKey = nextTrackKey
	if nextMode == "theme" then
		applyThemeSound(nextThemeInfo)
	elseif nextMode ~= "theme" then
		themeSoundNeedsRestart = false
		currentThemeSequenceIds = {}
		currentThemeSequenceIndex = 0
	end
	playerGui:SetAttribute(Constants.GLOBAL_MUSIC_OVERRIDE_ATTRIBUTE, globalOverride ~= nil and nextMode == "theme")

	for key, sound in pairs(sounds) do
		local isActive = key == nextMode
		tweenSound(sound, isActive and targetVolumes[key] or 0, isActive)
	end

	if nextMode == "theme" and themeSoundNeedsRestart and sounds.theme.SoundId ~= "" then
		themeSoundNeedsRestart = false
		task.defer(function()
			if currentMode ~= "theme" or sounds.theme.SoundId == "" then
				return
			end
			sounds.theme:Stop()
			sounds.theme.TimePosition = 0
			sounds.theme:Play()
		end)
	end

	if nextMode and nextTrackInfo then
		showThemeNotification(nextTrackInfo.SongName, nextTrackInfo.CreatorName)
	end
end

sounds.theme.Ended:Connect(function()
	if currentMode ~= "theme" or #currentThemeSequenceIds <= 1 then
		return
	end

	currentThemeSequenceIndex = (currentThemeSequenceIndex % #currentThemeSequenceIds) + 1
	local nextSoundId = currentThemeSequenceIds[currentThemeSequenceIndex]
	if not nextSoundId or nextSoundId == 0 then
		return
	end

	sounds.theme.SoundId = "rbxassetid://" .. tostring(nextSoundId)
	sounds.theme.TimePosition = 0
	sounds.theme:Play()
end)

showThemeNotification = function(songName, creatorName)
	if type(songName) ~= "string" or songName == "" then
		return
	end

	themeNotificationNonce += 1
	local localNonce = themeNotificationNonce
	themeTitle.Text = songName
	themeCreator.Text = type(creatorName) == "string" and creatorName ~= "" and ("by " .. creatorName) or ""
	themeBanner.Visible = true
	themeBanner.Position = UDim2.new(0.5, 0, 0, -94)
	themeBanner.BackgroundTransparency = 0.08

	TweenService:Create(themeBanner, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Position = UDim2.new(0.5, 0, 0, 14),
	}):Play()

	task.delay(Constants.CHARACTER_THEME_NOTIFICATION_TIME or 3.6, function()
		if themeNotificationNonce ~= localNonce then
			return
		end

		local hideTween = TweenService:Create(themeBanner, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			Position = UDim2.new(0.5, 0, 0, -94),
			BackgroundTransparency = 0.28,
		})
		hideTween:Play()
		hideTween.Completed:Connect(function()
			if themeNotificationNonce == localNonce then
				themeBanner.Visible = false
			end
		end)
	end)
end

local function bindCharacter(character)
	disconnectCharacterSignals()
	if not character then
		refreshAudio()
		return
	end

	table.insert(characterConnections, character:GetAttributeChangedSignal("InCombat"):Connect(refreshAudio))
	table.insert(characterConnections, character:GetAttributeChangedSignal("KitId"):Connect(refreshAudio))
	table.insert(characterConnections, character:GetAttributeChangedSignal("SelectedSkin"):Connect(refreshAudio))
	table.insert(characterConnections, character:GetAttributeChangedSignal("BlackSilencePhase"):Connect(refreshAudio))
	table.insert(characterConnections, character:GetAttributeChangedSignal("ThemeSoundId"):Connect(refreshAudio))
	table.insert(characterConnections, character.AncestryChanged:Connect(function(_, parent)
		if not parent then
			refreshAudio()
		end
	end))

	refreshAudio()
end

player.CharacterAdded:Connect(bindCharacter)
if player.Character then
	bindCharacter(player.Character)
else
	refreshAudio()
end

playerGui:GetAttributeChangedSignal(Constants.MENU_ATTRIBUTE):Connect(refreshAudio)
Workspace:GetAttributeChangedSignal(Constants.TRAINING_SERVER_ATTRIBUTE):Connect(refreshAudio)

combatState.OnClientEvent:Connect(function(payload)
	if typeof(payload) ~= "table" or payload.Type ~= "GlobalMusicOverride" then
		return
	end

	if payload.Active == true and tonumber(payload.SoundId) and tonumber(payload.SoundId) ~= 0 then
		globalOverride = {
			ThemeKey = payload.ThemeKey,
			ThemeName = payload.ThemeName,
			SoundId = tonumber(payload.SoundId),
			SongName = payload.SongName,
			CreatorName = payload.CreatorName,
		}
	else
		globalOverride = nil
	end

	refreshAudio()
end)
