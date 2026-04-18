local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")
local TeleportService = game:GetService("TeleportService")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Constants = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Constants"))
local CharacterKits = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("CharacterKits"))
local SkinCatalog = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("SkinCatalog"))

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local combatRequest = remotes:WaitForChild("CombatRequest")
local combatState = remotes:WaitForChild("CombatState")
playerGui:SetAttribute(Constants.MENU_ATTRIBUTE, true)
if playerGui:GetAttribute(Constants.LOADING_ATTRIBUTE) == nil then
	playerGui:SetAttribute(Constants.LOADING_ATTRIBUTE, false)
end
if playerGui:GetAttribute(Constants.HITBOX_ATTRIBUTE) == nil then
	playerGui:SetAttribute(Constants.HITBOX_ATTRIBUTE, false)
end
if playerGui:GetAttribute(Constants.GLOBAL_MUSIC_OVERRIDE_ATTRIBUTE) == nil then
	playerGui:SetAttribute(Constants.GLOBAL_MUSIC_OVERRIDE_ATTRIBUTE, false)
end

local theme = {
	skyTop = Color3.fromRGB(107, 8, 8),
	skyMid = Color3.fromRGB(175, 67, 11),
	skyBottom = Color3.fromRGB(13, 14, 28),
	panel = Color3.fromRGB(64, 14, 16),
	panelSoft = Color3.fromRGB(96, 28, 20),
	panelDark = Color3.fromRGB(17, 18, 24),
	panelGlass = Color3.fromRGB(31, 18, 24),
	white = Color3.fromRGB(245, 244, 240),
	muted = Color3.fromRGB(220, 201, 180),
	gold = Color3.fromRGB(255, 182, 43),
	ember = Color3.fromRGB(255, 106, 46),
	red = Color3.fromRGB(219, 63, 63),
	green = Color3.fromRGB(72, 170, 71),
	blue = Color3.fromRGB(91, 159, 255),
}

local transparencyCache = {}

local function isTrainingPlace()
	for _, placeId in ipairs(Constants.TRAINING_SERVER_PLACE_IDS) do
		if placeId == game.PlaceId then
			return true
		end
	end
	return false
end

local function isRankedQueuePlace()
	return Constants.RANKED_QUEUE_PLACE_ID ~= 0 and game.PlaceId == Constants.RANKED_QUEUE_PLACE_ID
end

local function getTravelTarget()
	if isTrainingPlace() or isRankedQueuePlace() then
		return Constants.MAIN_GAME_PLACE_ID, "Main Game"
	end

	return Constants.TRAINING_SERVER_PLACE_IDS[1], "TR"
end

local credits = {
	{Name = "The_OnlyQwerty", Role = "Owner", UserId = 4527372044},
	{Name = "Cavespider07", Role = "Manager / Animator", UserId = 103145521},
	{Name = "LCB_Taxsane", Role = "Investor / Manager", UserId = 2583906719},
	{Name = "acedd", Role = "Music", UserId = 0, LinkLabel = "YouTube Channel", LinkUrl = "https://www.youtube.com/channel/UC3KBPeTgvEmTIyjwgZwEbPw"},
	{Name = "Emperor Jub", Role = "Musician", UserId = 1981196939},
}

local currentKills = 0
local currentDeaths = 0
local currentKDR = 0
local currentRankedRating = Constants.RANKED_START_RATING
local currentRankedWins = 0
local currentRankedLosses = 0
local hasLoadedProfile = false
local isTouchDevice = UserInputService.TouchEnabled
local menuViewportConnection
local selectedSkins = {
	Sans = "Default",
	Magnus = "Default",
	Samurai = "Default",
	Naoya = "Default",
}
local skinCategories = {"Sans", "Magnus", "Samurai"}

local function hasTesterAccess()
	return player:GetAttribute(Constants.TESTER_ACCESS_ATTRIBUTE) == true
end

local function getCharacterDisplayName(kitId)
	local kit = CharacterKits[kitId]
	return (kit and kit.DisplayName) or kitId
end

local function getCreditInitials(name)
	local text = tostring(name or "")
	local first = text:match("[%w]")
	return first and string.upper(first) or "?"
end

local function getCreditThumbnail(userId)
	local numericUserId = tonumber(userId) or 0
	if numericUserId <= 0 then
		return nil
	end

	local ok, content = pcall(function()
		return Players:GetUserThumbnailAsync(
			numericUserId,
			Enum.ThumbnailType.AvatarThumbnail,
			Enum.ThumbnailSize.Size420x420
		)
	end)
	if ok and type(content) == "string" and content ~= "" then
		return content
	end

	return nil
end

local function create(instanceType, props)
	local instance = Instance.new(instanceType)
	for key, value in pairs(props) do
		instance[key] = value
	end
	return instance
end

local function notify(text)
	return
end

local function playUnavailableCardFeedback(card, stroke)
	local originalPosition = card.Position
	local originalColor = card.BackgroundColor3
	local originalStrokeColor = stroke and stroke.Color or nil

	card.BackgroundColor3 = theme.red
	if stroke then
		stroke.Color = Color3.fromRGB(255, 235, 235)
	end

	local shakeOffsets = {-8, 8, -6, 6, -3, 3, 0}
	for _, offset in ipairs(shakeOffsets) do
		TweenService:Create(card, TweenInfo.new(0.035), {
			Position = originalPosition + UDim2.fromOffset(offset, 0),
		}):Play()
		task.wait(0.035)
	end

	TweenService:Create(card, TweenInfo.new(0.12), {
		BackgroundColor3 = originalColor,
		Position = originalPosition,
	}):Play()

	if stroke and originalStrokeColor then
		TweenService:Create(stroke, TweenInfo.new(0.12), {
			Color = originalStrokeColor,
		}):Play()
	end
end

local gui = create("ScreenGui", {
	Name = "MainMenu",
	IgnoreGuiInset = true,
	ResetOnSpawn = false,
	Parent = playerGui,
})
gui.Enabled = playerGui:GetAttribute(Constants.LOADING_ATTRIBUTE) and playerGui:GetAttribute(Constants.MENU_ATTRIBUTE)

local notificationGui = create("ScreenGui", {
	Name = "RankNotifications",
	IgnoreGuiInset = true,
	ResetOnSpawn = false,
	Parent = playerGui,
})

local rankPopup = create("Frame", {
	Visible = false,
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.fromScale(0.5, 0.06),
	Size = UDim2.fromOffset(420, 92),
	BackgroundColor3 = theme.panelDark,
	BackgroundTransparency = 0.08,
	BorderSizePixel = 0,
	Parent = notificationGui,
})
create("UICorner", {CornerRadius = UDim.new(0, 18), Parent = rankPopup})
local rankPopupStroke = create("UIStroke", {
	Color = theme.gold,
	Thickness = 2,
	Transparency = 0.2,
	Parent = rankPopup,
})
local rankPopupTitle = create("TextLabel", {
	BackgroundTransparency = 1,
	Position = UDim2.new(0, 18, 0, 12),
	Size = UDim2.new(1, -36, 0, 28),
	Font = Enum.Font.Arcade,
	Text = "Promotion",
	TextColor3 = theme.white,
	TextSize = 22,
	TextXAlignment = Enum.TextXAlignment.Left,
	Parent = rankPopup,
})
local rankPopupBody = create("TextLabel", {
	BackgroundTransparency = 1,
	Position = UDim2.new(0, 18, 0, 44),
	Size = UDim2.new(1, -36, 0, 30),
	Font = Enum.Font.Arcade,
	Text = "",
	TextColor3 = theme.muted,
	TextSize = 16,
	TextXAlignment = Enum.TextXAlignment.Left,
	Parent = rankPopup,
})
local rankPopupScale = create("UIScale", {
	Scale = 1,
	Parent = rankPopup,
})

local menuMusic = create("Sound", {
	Name = "MenuMusic",
	Parent = gui,
	Looped = true,
	Volume = 0,
	SoundId = Constants.MENU_MUSIC_ID ~= 0 and ("rbxassetid://" .. Constants.MENU_MUSIC_ID) or "",
})

local root = create("Frame", {
	Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = theme.skyTop,
	BorderSizePixel = 0,
	Parent = gui,
})

create("UIGradient", {
	Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, theme.skyTop),
		ColorSequenceKeypoint.new(0.42, theme.skyMid),
		ColorSequenceKeypoint.new(1, theme.skyBottom),
	}),
	Rotation = 90,
	Parent = root,
})

local vignette = create("Frame", {
	Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = Color3.fromRGB(8, 8, 10),
	BackgroundTransparency = 0.5,
	BorderSizePixel = 0,
	Parent = root,
})
create("UIGradient", {
	Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(0, 0, 0)),
		ColorSequenceKeypoint.new(0.5, Color3.fromRGB(40, 10, 10)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(0, 0, 0)),
	}),
	Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.15),
		NumberSequenceKeypoint.new(0.45, 0.85),
		NumberSequenceKeypoint.new(1, 0.15),
	}),
	Rotation = 90,
	Parent = vignette,
})

local floorGlow = create("Frame", {
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, 0),
	Size = UDim2.new(1.3, 0, 0.42, 0),
	BackgroundColor3 = theme.ember,
	BackgroundTransparency = 0.78,
	BorderSizePixel = 0,
	Parent = root,
})
create("UICorner", {CornerRadius = UDim.new(1, 0), Parent = floorGlow})

local scanlines = create("Frame", {
	Size = UDim2.fromScale(1, 1),
	BackgroundTransparency = 1,
	Parent = root,
})
for index = 0, 26 do
	create("Frame", {
		BackgroundColor3 = theme.white,
		BackgroundTransparency = 0.97,
		BorderSizePixel = 0,
		Position = UDim2.new(0, 0, 0, index * 32),
		Size = UDim2.new(1, 0, 0, 1),
		Parent = scanlines,
	})
end

local titleGlow = create("TextLabel", {
	BackgroundTransparency = 1,
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.fromScale(0.5, 0.05),
	Size = UDim2.new(0, 980, 0, 160),
	Font = Enum.Font.Arcade,
	Text = "JUDGEMENT\nDIVIDED",
	TextColor3 = theme.ember,
	TextTransparency = 0.35,
	TextSize = 62,
	TextWrapped = true,
	TextYAlignment = Enum.TextYAlignment.Top,
	Parent = root,
})

local title = create("TextLabel", {
	BackgroundTransparency = 1,
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.fromScale(0.5, 0.035),
	Size = UDim2.new(0, 980, 0, 160),
	Font = Enum.Font.Arcade,
	Text = "JUDGEMENT\nDIVIDED",
	TextColor3 = theme.white,
	TextSize = 62,
	TextWrapped = true,
	TextYAlignment = Enum.TextYAlignment.Top,
	Parent = root,
})

local titleRule = create("Frame", {
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.fromScale(0.5, 0.208),
	Size = UDim2.fromOffset(380, 6),
	BackgroundColor3 = theme.gold,
	BackgroundTransparency = 0.1,
	BorderSizePixel = 0,
	Parent = root,
})
create("UICorner", {CornerRadius = UDim.new(1, 0), Parent = titleRule})

local titleSub = create("TextLabel", {
	BackgroundTransparency = 1,
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.fromScale(0.5, 0.22),
	Size = UDim2.new(0, 520, 0, 26),
	Font = Enum.Font.Arcade,
	Text = "A battlegrounds prototype build",
	TextColor3 = theme.muted,
	TextSize = 16,
	Parent = root,
})

local topBadge = create("TextLabel", {
	BackgroundColor3 = theme.panelDark,
	BackgroundTransparency = 0.18,
	Position = UDim2.fromOffset(26, 24),
	Size = UDim2.fromOffset(170, 34),
	BorderSizePixel = 0,
	Font = Enum.Font.Arcade,
	Text = "BUILD: TEST",
	TextColor3 = theme.white,
	TextSize = 14,
	Parent = root,
})
topBadge.Visible = false
create("UICorner", {CornerRadius = UDim.new(0, 12), Parent = topBadge})
create("UIStroke", {
	Color = theme.ember,
	Transparency = 0.5,
	Thickness = 2,
	Parent = topBadge,
})

local serverBadge = create("TextLabel", {
	AnchorPoint = Vector2.new(1, 0),
	BackgroundColor3 = theme.panelDark,
	BackgroundTransparency = 0.18,
	Position = UDim2.new(1, -18, 0, 18),
	Size = UDim2.fromOffset(164, 28),
	BorderSizePixel = 0,
	Font = Enum.Font.Arcade,
	Text = isTrainingPlace() and "SAFE ZONE: TRAINING" or "LIVE ARENA: MAIN",
	TextColor3 = theme.white,
	TextSize = 10,
	Parent = root,
})
serverBadge.Visible = false
create("UICorner", {CornerRadius = UDim.new(0, 12), Parent = serverBadge})
create("UIStroke", {
	Color = isTrainingPlace() and theme.green or theme.gold,
	Transparency = 0.5,
	Thickness = 2,
	Parent = serverBadge,
})

local particleFolder = create("Folder", {
	Name = "MenuParticles",
	Parent = root,
})

local particles = {}
for index = 1, 28 do
	local size = 4 + (index % 4) * 4
	local particle = create("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale((index * 0.071) % 1, 0.42 + ((index * 0.117) % 0.58)),
		Size = UDim2.fromOffset(size, size),
		BackgroundColor3 = (index % 3 == 0) and theme.blue or theme.ember,
		BackgroundTransparency = 0.45,
		BorderSizePixel = 0,
		Parent = particleFolder,
	})
	create("UICorner", {CornerRadius = UDim.new(1, 0), Parent = particle})
	particles[index] = {
		Frame = particle,
		BaseX = particle.Position.X.Scale,
		BaseY = particle.Position.Y.Scale,
		Speed = 0.1 + index * 0.008,
		Amplitude = 0.008 + (index % 5) * 0.002,
	}
end

local function createPrimaryButton(text, position, size, parent, accentColor)
	local button = create("TextButton", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = position,
		Size = size,
		BackgroundColor3 = theme.panelDark,
		BackgroundTransparency = 0.04,
		BorderSizePixel = 0,
		Font = Enum.Font.Arcade,
		Text = text,
		TextColor3 = theme.white,
		TextSize = 34,
		AutoButtonColor = false,
		Parent = parent,
	})
	button:SetAttribute("BaseWidth", size.X.Offset)
	button:SetAttribute("BaseHeight", size.Y.Offset)
	button:SetAttribute("AccentColor", accentColor or theme.ember)
	create("UICorner", {CornerRadius = UDim.new(0, 16), Parent = button})
	create("UIStroke", {
		Name = "ButtonStroke",
		Color = theme.white,
		Transparency = 0.15,
		Thickness = 1.8,
		Parent = button,
	})

	local shell = create("Frame", {
		Name = "Shell",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(1, 10, 1, 10),
		BackgroundColor3 = accentColor or theme.ember,
		BackgroundTransparency = 0.5,
		BorderSizePixel = 0,
		ZIndex = math.max(0, button.ZIndex - 1),
		Parent = button,
	})
	create("UICorner", {CornerRadius = UDim.new(0, 18), Parent = shell})

	local shine = create("Frame", {
		Name = "Shine",
		BackgroundColor3 = theme.white,
		BackgroundTransparency = 0.9,
		BorderSizePixel = 0,
		Position = UDim2.new(0, 8, 0, 8),
		Size = UDim2.new(1, -16, 0, 8),
		Parent = button,
	})
	create("UICorner", {CornerRadius = UDim.new(1, 0), Parent = shine})

	button.MouseEnter:Connect(function()
		local baseWidth = button:GetAttribute("BaseWidth") or size.X.Offset
		local baseHeight = button:GetAttribute("BaseHeight") or size.Y.Offset
		TweenService:Create(button, TweenInfo.new(0.12), {
			BackgroundColor3 = theme.panelSoft,
			Size = UDim2.fromOffset(baseWidth + 8, baseHeight + 8),
		}):Play()
		TweenService:Create(shell, TweenInfo.new(0.12), {
			BackgroundTransparency = 0.2,
		}):Play()
	end)

	button.MouseLeave:Connect(function()
		local baseWidth = button:GetAttribute("BaseWidth") or size.X.Offset
		local baseHeight = button:GetAttribute("BaseHeight") or size.Y.Offset
		TweenService:Create(button, TweenInfo.new(0.12), {
			BackgroundColor3 = theme.panelDark,
			Size = UDim2.fromOffset(baseWidth, baseHeight),
		}):Play()
		TweenService:Create(shell, TweenInfo.new(0.12), {
			BackgroundTransparency = 0.5,
		}):Play()
	end)

	return button
end

local homePage = create("Frame", {
	Size = UDim2.fromScale(1, 1),
	BackgroundTransparency = 1,
	Parent = root,
})

local homeCard = create("Frame", {
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.74),
	Size = UDim2.fromOffset(560, 216),
	BackgroundColor3 = theme.panelGlass,
	BackgroundTransparency = 0.14,
	BorderSizePixel = 0,
	Parent = homePage,
})
homeCard.Visible = false
create("UICorner", {CornerRadius = UDim.new(0, 24), Parent = homeCard})
create("UIStroke", {
	Color = theme.ember,
	Transparency = 0.55,
	Thickness = 2,
	Parent = homeCard,
})

local homeCardGlow = create("Frame", {
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.new(1, 28, 1, 28),
	BackgroundColor3 = theme.ember,
	BackgroundTransparency = 0.9,
	BorderSizePixel = 0,
	Parent = homeCard,
})
homeCardGlow.Visible = false
create("UICorner", {CornerRadius = UDim.new(0, 30), Parent = homeCardGlow})

create("TextLabel", {
	BackgroundTransparency = 1,
	Position = UDim2.new(0, 24, 0, 22),
	Size = UDim2.new(1, -48, 0, 24),
	Font = Enum.Font.Arcade,
	Text = "Choose your mode and enter the arena.",
	TextColor3 = theme.muted,
	TextSize = 14,
	TextXAlignment = Enum.TextXAlignment.Center,
	Parent = homeCard,
})

create("TextLabel", {
	BackgroundTransparency = 1,
	Position = UDim2.new(0, 24, 1, -38),
	Size = UDim2.new(1, -48, 0, 18),
	Font = Enum.Font.Arcade,
	Text = "",
	TextColor3 = theme.muted,
	TextSize = 12,
	TextXAlignment = Enum.TextXAlignment.Center,
	Parent = homeCard,
})

local creditsPage = create("Frame", {
	Visible = false,
	Size = UDim2.fromScale(1, 1),
	BackgroundTransparency = 1,
	Parent = root,
})

local skinsPage = create("Frame", {
	Visible = false,
	Size = UDim2.fromScale(1, 1),
	BackgroundTransparency = 1,
	Parent = root,
})

local ranksPage = create("Frame", {
	Visible = false,
	Size = UDim2.fromScale(1, 1),
	BackgroundTransparency = 1,
	Parent = root,
})

local settingsPage = create("Frame", {
	Visible = false,
	Size = UDim2.fromScale(1, 1),
	BackgroundTransparency = 1,
	Parent = root,
})

local selectPage = create("Frame", {
	Visible = false,
	Size = UDim2.fromScale(1, 1),
	BackgroundTransparency = 1,
	Parent = root,
})

local pages = {
	Home = homePage,
	Credits = creditsPage,
	Skins = skinsPage,
	Ranks = ranksPage,
	Settings = settingsPage,
	Select = selectPage,
}

for _, page in pairs(pages) do
	page.ZIndex = 10
end

local homePageScale = create("UIScale", {
	Scale = 1,
	Parent = homePage,
})
local creditsPageScale = create("UIScale", {
	Scale = 1,
	Parent = creditsPage,
})
local skinsPageScale = create("UIScale", {
	Scale = 1,
	Parent = skinsPage,
})
local ranksPageScale = create("UIScale", {
	Scale = 1,
	Parent = ranksPage,
})
local settingsPageScale = create("UIScale", {
	Scale = 1,
	Parent = settingsPage,
})
local selectPageScale = create("UIScale", {
	Scale = 1,
	Parent = selectPage,
})

local playButton = createPrimaryButton("Play", UDim2.fromScale(0.5, 0.74), UDim2.fromOffset(360, 76), homePage, theme.gold)
local trainingButton = createPrimaryButton("TR", UDim2.fromScale(0.86, 0.13), UDim2.fromOffset(104, 50), homePage, theme.green)
do
	local travelTargetPlaceId, travelLabel = getTravelTarget()
	trainingButton.Text = travelLabel
	trainingButton.TextSize = travelLabel == "Main Game" and 18 or 24
	trainingButton.Visible = travelTargetPlaceId ~= nil and travelTargetPlaceId ~= 0
end
local infoButton = createPrimaryButton("?", UDim2.fromScale(0.31, 0.885), UDim2.fromOffset(74, 74), homePage, theme.blue)
local skinsButton = createPrimaryButton("SK", UDim2.fromScale(0.44, 0.885), UDim2.fromOffset(74, 74), homePage, theme.ember)
local ranksButton = createPrimaryButton("RANK", UDim2.fromScale(0.57, 0.885), UDim2.fromOffset(104, 74), homePage, theme.gold)
local settingsButton = createPrimaryButton("SET", UDim2.fromScale(0.7, 0.885), UDim2.fromOffset(74, 74), homePage, theme.red)
ranksButton.TextSize = 18
settingsButton.TextSize = 18
skinsButton.TextSize = 22

title.Position = UDim2.fromScale(0.5, 0.02)
titleGlow.Position = UDim2.fromScale(0.5, 0.035)
title.Size = UDim2.new(0, 1120, 0, 172)
titleGlow.Size = UDim2.new(0, 1120, 0, 172)
title.TextSize = 70
titleGlow.TextSize = 70
titleRule.Position = UDim2.fromScale(0.5, 0.208)
titleRule.Size = UDim2.fromOffset(0, 0)
titleRule.Visible = false
titleSub.Position = UDim2.fromScale(0.5, 0.215)
titleSub.Text = ""
titleSub.Visible = false

playButton.Position = UDim2.fromScale(0.5, 0.73)
playButton.Size = UDim2.fromOffset(388, 70)
playButton.TextSize = 36

infoButton.Position = UDim2.fromScale(0.38, 0.865)
skinsButton.Position = UDim2.fromScale(0.46, 0.865)
ranksButton.Position = UDim2.fromScale(0.54, 0.865)
settingsButton.Position = UDim2.fromScale(0.62, 0.865)
ranksButton.Visible = true

infoButton.Size = UDim2.fromOffset(72, 72)
skinsButton.Size = UDim2.fromOffset(72, 72)
ranksButton.Size = UDim2.fromOffset(72, 72)
settingsButton.Size = UDim2.fromOffset(72, 72)
infoButton.TextSize = 34
skinsButton.TextSize = 20
settingsButton.TextSize = 18
ranksButton.TextSize = 14

local function createHomeHint(text, xScale)
	return create("TextLabel", {
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(xScale, 0.955),
		Size = UDim2.fromOffset(128, 20),
		Font = Enum.Font.Arcade,
		Text = text,
		TextColor3 = theme.muted,
		TextSize = 10,
		Parent = homePage,
	})
end

local creditsHint = createHomeHint("Credits", 0.38)
local skinsHint = createHomeHint("Skins", 0.46)
local ranksHint = createHomeHint("Ranks", 0.54)
local settingsHint = createHomeHint("Settings", 0.62)
creditsHint.Position = UDim2.fromScale(0.38, 0.952)
skinsHint.Position = UDim2.fromScale(0.46, 0.952)
ranksHint.Position = UDim2.fromScale(0.54, 0.952)
settingsHint.Position = UDim2.fromScale(0.62, 0.952)

local titleBaseY = 0.02
local titleGlowBaseY = 0.035
local homeCardBaseY = 0.74

local function setButtonBaseSize(button, width, height)
	button.Size = UDim2.fromOffset(width, height)
	button:SetAttribute("BaseWidth", width)
	button:SetAttribute("BaseHeight", height)
end

local function styleMenuButton(button, compact, isPrimary)
	local shell = button:FindFirstChild("Shell")
	local shine = button:FindFirstChild("Shine")
	local stroke = button:FindFirstChild("ButtonStroke")
	local corner = button:FindFirstChildOfClass("UICorner")
	local accent = button:GetAttribute("AccentColor") or theme.ember

	if compact then
		button.BackgroundColor3 = Color3.fromRGB(18, 20, 28)
		button.BackgroundTransparency = isPrimary and 0.03 or 0.1
		button.TextStrokeTransparency = 0.78
		if corner then
			corner.CornerRadius = UDim.new(0, isPrimary and 18 or 20)
		end
		if stroke then
			stroke.Color = accent
			stroke.Transparency = isPrimary and 0.14 or 0.28
			stroke.Thickness = isPrimary and 2.2 or 1.5
		end
		if shell then
			shell.BackgroundColor3 = accent
			shell.BackgroundTransparency = isPrimary and 0.22 or 0.4
			shell.Size = UDim2.new(1, 6, 1, 6)
		end
		if shine then
			shine.Position = UDim2.new(0, 8, 0, 7)
			shine.Size = UDim2.new(1, -16, 0, 5)
			shine.BackgroundTransparency = 0.93
		end
	else
		button.BackgroundColor3 = theme.panelDark
		button.BackgroundTransparency = 0.04
		button.TextStrokeTransparency = 1
		if corner then
			corner.CornerRadius = UDim.new(0, 16)
		end
		if stroke then
			stroke.Color = theme.white
			stroke.Transparency = 0.15
			stroke.Thickness = 1.8
		end
		if shell then
			shell.BackgroundColor3 = accent
			shell.BackgroundTransparency = 0.5
			shell.Size = UDim2.new(1, 10, 1, 10)
		end
		if shine then
			shine.Position = UDim2.new(0, 8, 0, 8)
			shine.Size = UDim2.new(1, -16, 0, 8)
			shine.BackgroundTransparency = 0.9
		end
	end
end

local function showPage(name)
	homePage.Visible = name == "Home"
	creditsPage.Visible = name == "Credits"
	skinsPage.Visible = name == "Skins"
	ranksPage.Visible = name == "Ranks"
	settingsPage.Visible = name == "Settings"
	selectPage.Visible = name == "Select"
end

local activeRankPopupToken = 0
local function showRankPopup(titleText, bodyText, accentColor)
	activeRankPopupToken += 1
	local token = activeRankPopupToken
	rankPopup.Visible = true
	rankPopup.Position = UDim2.fromScale(0.5, 0.02)
	rankPopup.BackgroundTransparency = 0.08
	rankPopupTitle.TextTransparency = 0
	rankPopupBody.TextTransparency = 0
	rankPopupTitle.Text = titleText
	rankPopupBody.Text = bodyText
	rankPopupStroke.Color = accentColor or theme.gold

	TweenService:Create(rankPopup, TweenInfo.new(0.18), {
		Position = UDim2.fromScale(0.5, 0.06),
	}):Play()

	task.delay(2.6, function()
		if token ~= activeRankPopupToken then
			return
		end
		TweenService:Create(rankPopup, TweenInfo.new(0.2), {
			Position = UDim2.fromScale(0.5, 0.02),
			BackgroundTransparency = 1,
		}):Play()
		TweenService:Create(rankPopupTitle, TweenInfo.new(0.2), {
			TextTransparency = 1,
		}):Play()
		TweenService:Create(rankPopupBody, TweenInfo.new(0.2), {
			TextTransparency = 1,
		}):Play()
		task.delay(0.22, function()
			if token == activeRankPopupToken then
				rankPopup.Visible = false
			end
		end)
	end)
end

local function updateHitboxSetting(button)
	local enabled = playerGui:GetAttribute(Constants.HITBOX_ATTRIBUTE)
	button.Text = enabled and "Hitboxes: ON" or "Hitboxes: OFF"
	button.BackgroundColor3 = enabled and theme.green or theme.panelDark
end

local function openMenuHome()
	for instance, values in pairs(transparencyCache) do
		if instance and instance.Parent then
			for property, value in pairs(values) do
				instance[property] = value
			end
		end
	end
	playerGui:SetAttribute(Constants.MENU_ATTRIBUTE, true)
	gui.Enabled = playerGui:GetAttribute(Constants.LOADING_ATTRIBUTE)
	showPage("Home")
end

local function refreshMenuFromSelectionState()
	local awaitingCharacterSelect = player:GetAttribute(Constants.AWAITING_CHARACTER_ATTRIBUTE) == true
	if awaitingCharacterSelect then
		openMenuHome()
	end
end

local function tweenTransparencyRecursive(instance, alpha)
	for _, descendant in ipairs(instance:GetDescendants()) do
		if descendant:IsA("Frame") or descendant:IsA("TextButton") or descendant:IsA("TextLabel") then
			local textTransparency = nil
			if descendant:IsA("TextButton") or descendant:IsA("TextLabel") then
				textTransparency = descendant.TextTransparency
			end
			transparencyCache[descendant] = transparencyCache[descendant] or {
				BackgroundTransparency = descendant.BackgroundTransparency,
				TextTransparency = textTransparency,
			}
			TweenService:Create(descendant, TweenInfo.new(0.3), {
				BackgroundTransparency = math.clamp((transparencyCache[descendant].BackgroundTransparency or 0) + alpha, 0, 1),
			}):Play()
			if descendant:IsA("TextButton") or descendant:IsA("TextLabel") then
				TweenService:Create(descendant, TweenInfo.new(0.3), {
					TextTransparency = math.clamp((transparencyCache[descendant].TextTransparency or 0) + alpha, 0, 1),
				}):Play()
			end
		elseif descendant:IsA("UIStroke") then
			transparencyCache[descendant] = transparencyCache[descendant] or {
				Transparency = descendant.Transparency,
			}
			TweenService:Create(descendant, TweenInfo.new(0.3), {
				Transparency = math.clamp((transparencyCache[descendant].Transparency or 0) + alpha, 0, 1),
			}):Play()
		elseif descendant:IsA("ImageLabel") or descendant:IsA("ImageButton") then
			transparencyCache[descendant] = transparencyCache[descendant] or {
				ImageTransparency = descendant.ImageTransparency,
				BackgroundTransparency = descendant.BackgroundTransparency,
			}
			TweenService:Create(descendant, TweenInfo.new(0.3), {
				ImageTransparency = math.clamp((transparencyCache[descendant].ImageTransparency or 0) + alpha, 0, 1),
				BackgroundTransparency = math.clamp((transparencyCache[descendant].BackgroundTransparency or 0) + alpha, 0, 1),
			}):Play()
		end
	end
end

local function closeMenuWithFade()
	tweenTransparencyRecursive(root, 1)
	if menuMusic.IsPlaying then
		TweenService:Create(menuMusic, TweenInfo.new(0.35), {
			Volume = 0,
		}):Play()
	end

	task.delay(0.35, function()
		playerGui:SetAttribute(Constants.MENU_ATTRIBUTE, false)
		gui.Enabled = false
		if menuMusic.IsPlaying then
			menuMusic:Stop()
		end
	end)
end

local function teleportToLinkedPlace()
	local targetPlaceId, targetLabel = getTravelTarget()

	if not targetPlaceId or targetPlaceId == 0 then
		if targetLabel == "Main Game" then
			notify("No main game place ID is configured yet.")
		else
			notify("No training place ID is configured yet.")
		end
		return
	end

	closeMenuWithFade()
	task.delay(0.4, function()
		combatRequest:FireServer({
			Action = "TeleportMenuDestination",
			Destination = targetLabel == "Main Game" and "MainGame" or "Training",
		})
	end)
end

local function teleportToRankedQueue()
	if not Constants.RANKED_QUEUE_PLACE_ID or Constants.RANKED_QUEUE_PLACE_ID == 0 then
		notify("No ranked queue place ID is configured yet.")
		return
	end

	if isRankedQueuePlace() then
		notify("You are already in the ranked queue server.")
		return
	end

	closeMenuWithFade()
	task.delay(0.4, function()
		combatRequest:FireServer({
			Action = "TeleportMenuDestination",
			Destination = "RankedQueue",
		})
	end)
end

local function createPanel(page, titleText, size)
	local panel = create("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.53),
		Size = size,
		BackgroundColor3 = theme.panel,
		BackgroundTransparency = 0.08,
		BorderSizePixel = 0,
		Parent = page,
	})
	create("UICorner", {CornerRadius = UDim.new(0, 26), Parent = panel})
	create("UIStroke", {
		Color = theme.ember,
		Transparency = 0.55,
		Thickness = 2,
		Parent = panel,
	})
	create("TextLabel", {
		BackgroundTransparency = 1,
		Position = UDim2.new(0, 0, 0, 18),
		Size = UDim2.new(1, 0, 0, 48),
		Font = Enum.Font.Arcade,
		Text = titleText,
		TextColor3 = theme.white,
		TextSize = 30,
		Parent = panel,
	})
	return panel
end

local creditsPanel = createPanel(creditsPage, "Credits", UDim2.fromOffset(520, 820))

local creditsScroll = create("ScrollingFrame", {
	Position = UDim2.new(0, 20, 0, 86),
	Size = UDim2.new(1, -40, 1, -122),
	CanvasSize = UDim2.new(0, 0, 0, 0),
	Active = true,
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	ScrollingDirection = Enum.ScrollingDirection.Y,
	ScrollingEnabled = true,
	ScrollBarThickness = 6,
	ScrollBarImageColor3 = theme.white,
	Parent = creditsPanel,
})

create("UIPadding", {
	PaddingTop = UDim.new(0, 2),
	PaddingBottom = UDim.new(0, 2),
	PaddingLeft = UDim.new(0, 2),
	PaddingRight = UDim.new(0, 2),
	Parent = creditsScroll,
})

local creditsListLayout = create("UIListLayout", {
	Padding = UDim.new(0, 14),
	SortOrder = Enum.SortOrder.LayoutOrder,
	Parent = creditsScroll,
})

local function updateCreditsCanvas()
	creditsScroll.CanvasSize = UDim2.new(0, 0, 0, creditsListLayout.AbsoluteContentSize.Y + 8)
end

creditsListLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(updateCreditsCanvas)

local creditsLinkModal = create("Frame", {
	Visible = false,
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromOffset(420, 220),
	BackgroundColor3 = theme.panelDark,
	BackgroundTransparency = 0.04,
	BorderSizePixel = 0,
	ZIndex = 30,
	Parent = creditsPage,
})
create("UICorner", {CornerRadius = UDim.new(0, 18), Parent = creditsLinkModal})
create("UIStroke", {
	Color = theme.ember,
	Transparency = 0.15,
	Thickness = 1.6,
	Parent = creditsLinkModal,
})

local creditsLinkTitle = create("TextLabel", {
	BackgroundTransparency = 1,
	Position = UDim2.fromOffset(18, 16),
	Size = UDim2.new(1, -36, 0, 24),
	Font = Enum.Font.Arcade,
	Text = "External Link",
	TextColor3 = theme.white,
	TextSize = 22,
	TextXAlignment = Enum.TextXAlignment.Left,
	ZIndex = 31,
	Parent = creditsLinkModal,
})

create("TextLabel", {
	BackgroundTransparency = 1,
	Position = UDim2.fromOffset(18, 48),
	Size = UDim2.new(1, -36, 0, 42),
	Font = Enum.Font.Arcade,
	Text = "Roblox blocks direct browser opens here. Copy the link below manually.",
	TextColor3 = theme.muted,
	TextSize = 13,
	TextWrapped = true,
	TextXAlignment = Enum.TextXAlignment.Left,
	TextYAlignment = Enum.TextYAlignment.Top,
	ZIndex = 31,
	Parent = creditsLinkModal,
})

local creditsLinkUrlBox = create("TextBox", {
	Position = UDim2.fromOffset(18, 96),
	Size = UDim2.new(1, -36, 0, 58),
	BackgroundColor3 = theme.panelGlass,
	BackgroundTransparency = 0.05,
	BorderSizePixel = 0,
	ClearTextOnFocus = false,
	Font = Enum.Font.Code,
	MultiLine = true,
	Text = "",
	TextColor3 = theme.white,
	TextEditable = true,
	TextSize = 14,
	TextWrapped = true,
	TextXAlignment = Enum.TextXAlignment.Left,
	TextYAlignment = Enum.TextYAlignment.Top,
	ZIndex = 31,
	Parent = creditsLinkModal,
})
create("UICorner", {CornerRadius = UDim.new(0, 12), Parent = creditsLinkUrlBox})
create("UIStroke", {
	Color = theme.gold,
	Transparency = 0.32,
	Thickness = 1.1,
	Parent = creditsLinkUrlBox,
})

local creditsLinkClose = createPrimaryButton("Close", UDim2.new(0.5, 0, 1, -28), UDim2.fromOffset(170, 42), creditsLinkModal, theme.red)
creditsLinkClose.TextSize = 20
creditsLinkClose.ZIndex = 31

local function showCreditsLink(titleText, url)
	creditsLinkTitle.Text = titleText or "External Link"
	creditsLinkUrlBox.Text = url or ""
	creditsLinkModal.Visible = true
	creditsLinkUrlBox:CaptureFocus()
	creditsLinkUrlBox.CursorPosition = 1
	creditsLinkUrlBox.SelectionStart = 1
end

creditsLinkClose.MouseButton1Click:Connect(function()
	creditsLinkModal.Visible = false
	creditsLinkUrlBox:ReleaseFocus()
end)

for index, entry in ipairs(credits) do
	local hasLink = type(entry.LinkUrl) == "string" and entry.LinkUrl ~= ""
	local cardHeight = hasLink and 148 or 126
	local card = create("Frame", {
		LayoutOrder = index,
		Size = UDim2.new(1, -4, 0, cardHeight),
		BackgroundColor3 = theme.panelSoft,
		BackgroundTransparency = 0.1,
		BorderSizePixel = 0,
		Parent = creditsScroll,
	})
	create("UICorner", {CornerRadius = UDim.new(0, 18), Parent = card})
	create("UIStroke", {
		Color = theme.ember,
		Transparency = 0.45,
		Thickness = 1.3,
		Parent = card,
	})

	local avatarShell = create("Frame", {
		Position = UDim2.fromOffset(16, 16),
		Size = UDim2.fromOffset(94, 94),
		BackgroundColor3 = theme.panelDark,
		BorderSizePixel = 0,
		Parent = card,
	})
	create("UICorner", {CornerRadius = UDim.new(0, 18), Parent = avatarShell})
	create("UIStroke", {
		Color = theme.gold,
		Transparency = 0.25,
		Thickness = 1.5,
		Parent = avatarShell,
	})

	local avatarThumbnail = getCreditThumbnail(entry.UserId)
	local avatarImage = create("ImageLabel", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(84, 84),
		BackgroundTransparency = 1,
		Image = avatarThumbnail or "",
		ImageTransparency = avatarThumbnail and 0 or 1,
		ScaleType = Enum.ScaleType.Fit,
		Parent = avatarShell,
	})
	create("UICorner", {CornerRadius = UDim.new(0, 14), Parent = avatarImage})

	local avatarFallback = create("TextLabel", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Font = Enum.Font.Arcade,
		Text = getCreditInitials(entry.Name),
		TextColor3 = theme.white,
		TextSize = 28,
		Visible = avatarThumbnail == nil,
		Parent = avatarShell,
	})

	create("TextLabel", {
		BackgroundTransparency = 1,
		Position = UDim2.new(0, 128, 0, 18),
		Size = UDim2.new(1, -146, 0, 28),
		Font = Enum.Font.Arcade,
		Text = entry.Name,
		TextColor3 = theme.white,
		TextSize = 24,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = card,
	})

	create("TextLabel", {
		BackgroundTransparency = 1,
		Position = UDim2.new(0, 128, 0, 50),
		Size = UDim2.new(1, -146, 0, 20),
		Font = Enum.Font.Arcade,
		Text = entry.Role,
		TextColor3 = theme.gold,
		TextSize = 15,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = card,
	})

	create("TextLabel", {
		BackgroundTransparency = 1,
		Position = UDim2.new(0, 128, 0, 76),
		Size = UDim2.new(1, -146, 0, 16),
		Font = Enum.Font.Arcade,
		Text = hasLink and "External link available" or ((tonumber(entry.UserId) or 0) > 0 and "Avatar linked" or "Avatar ready for user id"),
		TextColor3 = theme.muted,
		TextSize = 11,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = card,
	})

	if hasLink then
		local linkButton = create("TextButton", {
			Position = UDim2.new(0, 128, 0, 102),
			Size = UDim2.fromOffset(188, 26),
			BackgroundColor3 = theme.red,
			BackgroundTransparency = 0.08,
			BorderSizePixel = 0,
			Font = Enum.Font.Arcade,
			Text = entry.LinkLabel or "Open Link",
			TextColor3 = theme.white,
			TextSize = 12,
			AutoButtonColor = true,
			Parent = card,
		})
		create("UICorner", {CornerRadius = UDim.new(0, 10), Parent = linkButton})
		create("UIStroke", {
			Color = theme.ember,
			Transparency = 0.18,
			Thickness = 1.1,
			Parent = linkButton,
		})

		linkButton.MouseButton1Click:Connect(function()
			showCreditsLink(entry.LinkLabel or (entry.Name .. " Link"), entry.LinkUrl)
		end)
	end
end

updateCreditsCanvas()

local backFromCredits = createPrimaryButton("Back", UDim2.fromScale(0.5, 0.94), UDim2.fromOffset(260, 70), creditsPage, theme.red)

local selectPanel = createPanel(selectPage, "Character Select", UDim2.fromOffset(900, 470))

local selectScroll = create("ScrollingFrame", {
	Position = UDim2.new(0, 34, 0, 66),
	Size = UDim2.new(1, -68, 1, -154),
	CanvasSize = UDim2.new(0, 0, 0, 332),
	AutomaticCanvasSize = Enum.AutomaticSize.None,
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	ScrollBarThickness = 6,
	ScrollBarImageColor3 = theme.white,
	Parent = selectPanel,
})

local selectIntroLabel = create("TextLabel", {
	BackgroundTransparency = 1,
	Position = UDim2.fromOffset(0, 0),
	Size = UDim2.new(1, 0, 0, 26),
	Font = Enum.Font.Arcade,
	Text = "Choose your fighter. Private tester slots unlock separately.",
	TextColor3 = theme.muted,
	TextSize = 14,
	TextXAlignment = Enum.TextXAlignment.Left,
	Parent = selectScroll,
})

local slotConfigs = {
	{Name = "Sans", Available = true, Description = "Bones / Telekinesis / Blasters"},
	{Name = "Magnus", Available = true, Description = "Sword brawler"},
	{Name = getCharacterDisplayName("Samurai"), KitId = "Samurai", Available = true, Description = "Balanced katana duelist"},
	{Name = "Naoya", Available = true, Description = "Projection sorcery speed fighter", RequiresTester = true},
}

local slotButtons = {}
local slotButtonVisuals = {}
for index, slot in ipairs(slotConfigs) do
	local col = (index - 1) % 3
	local row = math.floor((index - 1) / 3)
	local button = create("TextButton", {
		Position = UDim2.new(0, col * 274, 0, 50 + row * 142),
		Size = UDim2.fromOffset(242, 116),
		BackgroundColor3 = slot.Available and theme.panelSoft or Color3.fromRGB(54, 54, 58),
		BorderSizePixel = 0,
		Text = "",
		AutoButtonColor = false,
		Parent = selectScroll,
	})
	create("UICorner", {CornerRadius = UDim.new(0, 18), Parent = button})
	local stroke = create("UIStroke", {
		Color = slot.Available and theme.gold or Color3.fromRGB(90, 90, 95),
		Transparency = 0.45,
		Thickness = 2,
		Parent = button,
	})

	local titleLabel = create("TextLabel", {
		BackgroundTransparency = 1,
		Position = UDim2.new(0, 14, 0, 12),
		Size = UDim2.new(1, -28, 0, 28),
		Font = Enum.Font.Arcade,
		Text = slot.Name,
		TextColor3 = theme.white,
		TextSize = 20,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = button,
	})

	local descriptionLabel = create("TextLabel", {
		BackgroundTransparency = 1,
		Position = UDim2.new(0, 14, 0, 48),
		Size = UDim2.new(1, -28, 0, 42),
		Font = Enum.Font.Arcade,
		Text = slot.Description,
		TextColor3 = theme.muted,
		TextSize = 11,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		Parent = button,
	})

	slotButtons[index] = button
	slotButtonVisuals[index] = {
		Stroke = stroke,
		TitleLabel = titleLabel,
		DescriptionLabel = descriptionLabel,
	}
end

local function refreshCharacterSlots()
	for index, slot in ipairs(slotConfigs) do
		local button = slotButtons[index]
		local visuals = slotButtonVisuals[index]
		local testerLocked = slot.RequiresTester and not hasTesterAccess()
		local selectable = slot.Available and not testerLocked

		button.BackgroundColor3 = selectable and theme.panelSoft or Color3.fromRGB(54, 54, 58)
		visuals.Stroke.Color = selectable and theme.gold or Color3.fromRGB(90, 90, 95)
		visuals.DescriptionLabel.Text = testerLocked and "Tester role required" or slot.Description
		visuals.DescriptionLabel.TextColor3 = testerLocked and theme.gold or theme.muted
	end
end

refreshCharacterSlots()

local backFromSelect = createPrimaryButton("Back", UDim2.new(0.5, 0, 1, -40), UDim2.fromOffset(240, 68), selectPanel, theme.red)

local skinsPanel = createPanel(skinsPage, "Skins", UDim2.fromOffset(980, 660))

local skinCharacterTitle = create("TextLabel", {
	BackgroundTransparency = 1,
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, -42, 0, 22),
	Size = UDim2.fromOffset(300, 40),
	Font = Enum.Font.Arcade,
	Text = "Sans",
	TextColor3 = theme.white,
	TextSize = 28,
	TextXAlignment = Enum.TextXAlignment.Right,
	Parent = skinsPanel,
})

local skinKillsTitle = create("TextLabel", {
	BackgroundTransparency = 1,
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, -42, 0, 58),
	Size = UDim2.fromOffset(420, 26),
	Font = Enum.Font.Arcade,
	Text = "Career Kills: 2143",
	TextColor3 = theme.muted,
	TextSize = 15,
	TextXAlignment = Enum.TextXAlignment.Right,
	Parent = skinsPanel,
})

local rankedStatsTitle = create("TextLabel", {
	BackgroundTransparency = 1,
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, -42, 0, 84),
	Size = UDim2.fromOffset(420, 22),
	Font = Enum.Font.Arcade,
	Text = "Ranked: Bronze | 1000 | W: 0 | L: 0",
	TextColor3 = theme.muted,
	TextSize = 13,
	TextXAlignment = Enum.TextXAlignment.Right,
	Parent = skinsPanel,
})

local categoryPanel = create("Frame", {
	Position = UDim2.new(0, 20, 0, 102),
	Size = UDim2.fromOffset(306, 318),
	BackgroundTransparency = 1,
	Parent = skinsPanel,
})

local categoryButtons = {}
local selectedCategory = "Sans"
for index, category in ipairs(skinCategories) do
	local button = create("TextButton", {
		Position = UDim2.new(0, 0, 0, (index - 1) * 54),
		Size = UDim2.fromOffset(306, 44),
		BackgroundColor3 = Color3.fromRGB(82, 82, 82),
		BorderSizePixel = 0,
		Font = Enum.Font.Arcade,
		Text = getCharacterDisplayName(category),
		TextColor3 = theme.white,
		TextSize = 18,
		AutoButtonColor = false,
		Parent = categoryPanel,
	})
	create("UICorner", {CornerRadius = UDim.new(0, 12), Parent = button})
	categoryButtons[category] = button
end

local cardsContainer = create("Frame", {
	Position = UDim2.new(0, 338, 0, 102),
	Size = UDim2.new(1, -360, 1, -152),
	BackgroundTransparency = 1,
	ClipsDescendants = true,
	Parent = skinsPanel,
})

local backFromSkins = createPrimaryButton("Back", UDim2.fromScale(0.5, 0.94), UDim2.fromOffset(260, 70), skinsPage, theme.red)

local ranksPanel = createPanel(ranksPage, "Rank Tiers", UDim2.fromOffset(620, 640))
local ranksIntroLabel = create("TextLabel", {
	BackgroundTransparency = 1,
	Position = UDim2.new(0, 28, 0, 92),
	Size = UDim2.new(1, -56, 0, 44),
	Font = Enum.Font.Arcade,
	Text = "Your current rank updates as your rating changes.",
	TextColor3 = theme.muted,
	TextSize = 16,
	TextWrapped = true,
	Parent = ranksPanel,
})

local ranksCurrentStats = create("TextLabel", {
	BackgroundTransparency = 1,
	Position = UDim2.new(0, 28, 0, 136),
	Size = UDim2.new(1, -56, 0, 34),
	Font = Enum.Font.Arcade,
	Text = "Current: Bronze | 1000 | W: 0 | L: 0",
	TextColor3 = theme.gold,
	TextSize = 16,
	TextWrapped = true,
	TextXAlignment = Enum.TextXAlignment.Left,
	TextYAlignment = Enum.TextYAlignment.Top,
	Parent = ranksPanel,
})

local ranksTierScroll = create("ScrollingFrame", {
	Position = UDim2.new(0, 28, 0, 182),
	Size = UDim2.new(1, -56, 1, -274),
	CanvasSize = UDim2.new(0, 0, 0, (#Constants.RANK_TIERS * 72) - 16),
	AutomaticCanvasSize = Enum.AutomaticSize.None,
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	ScrollBarThickness = 6,
	ScrollBarImageColor3 = theme.white,
	Parent = ranksPanel,
})

local rankTierRows = {}
for index, tier in ipairs(Constants.RANK_TIERS) do
	local nextTier = Constants.RANK_TIERS[index + 1]
	local minText = tostring(tier.MinRating)
	local maxText = nextTier and tostring(nextTier.MinRating - 1) or "+"
	local row = create("Frame", {
		Position = UDim2.fromOffset(0, (index - 1) * 72),
		Size = UDim2.new(1, -8, 0, 56),
		BackgroundColor3 = index % 2 == 0 and theme.panelSoft or theme.panelDark,
		BackgroundTransparency = 0.12,
		BorderSizePixel = 0,
		Parent = ranksTierScroll,
	})
	create("UICorner", {CornerRadius = UDim.new(0, 14), Parent = row})
	local nameLabel = create("TextLabel", {
		BackgroundTransparency = 1,
		Position = UDim2.new(0, 18, 0, 10),
		Size = UDim2.new(0.52, 0, 0, 20),
		Font = Enum.Font.Arcade,
		Text = tier.Name,
		TextColor3 = theme.white,
		TextSize = 18,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = row,
	})
	local rangeLabel = create("TextLabel", {
		BackgroundTransparency = 1,
		Position = UDim2.new(0.5, 0, 0, 10),
		Size = UDim2.new(0.46, -18, 0, 20),
		Font = Enum.Font.Arcade,
		Text = nextTier and string.format("%s - %s", minText, maxText) or (minText .. "+"),
		TextColor3 = theme.gold,
		TextSize = 18,
		TextXAlignment = Enum.TextXAlignment.Right,
		Parent = row,
	})
	rankTierRows[index] = {
		Row = row,
		NameLabel = nameLabel,
		RangeLabel = rangeLabel,
	}
end

local backFromRanks = createPrimaryButton("Back", UDim2.fromScale(0.5, 0.92), UDim2.fromOffset(240, 68), ranksPage, theme.red)
local enterRankedButton = createPrimaryButton("Queue Ranked", UDim2.fromScale(0.5, 0.84), UDim2.fromOffset(286, 64), ranksPage, theme.gold)
enterRankedButton.TextSize = 24
if isRankedQueuePlace() then
	enterRankedButton.Text = "Ranked Server"
	enterRankedButton.BackgroundColor3 = theme.green
end

local function isSkinUnlocked(kitId, skin)
	if skin.RequiresTester and not hasTesterAccess() then
		return false
	end

	return currentKills >= (skin.UnlockKills or 0)
end

local function renderSkinCards()
	for _, child in ipairs(cardsContainer:GetChildren()) do
		child:Destroy()
	end

	for category, button in pairs(categoryButtons) do
		button.BackgroundColor3 = category == selectedCategory and theme.green or Color3.fromRGB(82, 82, 82)
	end

	skinCharacterTitle.Text = getCharacterDisplayName(selectedCategory)
	skinKillsTitle.Text = string.format("Kills: %d   Deaths: %d   KDR: %.2f", currentKills, currentDeaths, currentKDR)
	rankedStatsTitle.Text = string.format("Ranked: %s   %d   W: %d   L: %d", Constants.GetRankTierName(currentRankedRating), currentRankedRating, currentRankedWins, currentRankedLosses)
	ranksCurrentStats.Text = string.format("Current: %s | %d | W: %d | L: %d", Constants.GetRankTierName(currentRankedRating), currentRankedRating, currentRankedWins, currentRankedLosses)

	local containerWidth = math.max(cardsContainer.AbsoluteSize.X, 220)
	local compactCards = isTouchDevice or containerWidth < 520
	local cardWidth = compactCards and 118 or 92
	local cardHeight = compactCards and 110 or 100
	local spacingX = compactCards and 12 or 10
	local spacingY = compactCards and 12 or 10
	local columns = math.max(1, math.floor((containerWidth + spacingX) / (cardWidth + spacingX)))
	columns = compactCards and math.min(columns, 2) or math.min(columns, 6)
	local totalWidth = (columns * cardWidth) + ((columns - 1) * spacingX)
	local startX = math.max(0, math.floor((containerWidth - totalWidth) * 0.5))

	for index, skin in ipairs(SkinCatalog[selectedCategory]) do
		local col = (index - 1) % columns
		local row = math.floor((index - 1) / columns)
		local testerLocked = skin.RequiresTester and not hasTesterAccess()
		local unlocked = isSkinUnlocked(selectedCategory, skin)
		local selected = selectedSkins[selectedCategory] == skin.Id
		local card = create("TextButton", {
			Position = UDim2.new(0, startX + (col * (cardWidth + spacingX)), 0, row * (cardHeight + spacingY)),
			Size = UDim2.fromOffset(cardWidth, cardHeight),
			BackgroundColor3 = skin.CardColor,
			BorderSizePixel = 0,
			AutoButtonColor = false,
			Text = "",
			Parent = cardsContainer,
		})
		create("UICorner", {CornerRadius = UDim.new(0, 14), Parent = card})
		local stroke = create("UIStroke", {
			Color = selected and theme.green or Color3.fromRGB(245, 244, 240),
			Transparency = selected and 0.05 or 0.68,
			Thickness = selected and 2.5 or 1.5,
			Parent = card,
		})

		create("TextLabel", {
			BackgroundTransparency = 1,
			Position = UDim2.new(0, 4, 0, 6),
			Size = UDim2.new(1, -8, 0, 24),
			Font = Enum.Font.Arcade,
			Text = skin.Name,
			TextColor3 = theme.white,
			TextSize = 10,
			TextWrapped = true,
			Parent = card,
		})

		local preview = create("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.56),
			Size = UDim2.fromOffset(48, 54),
			BackgroundTransparency = 1,
			Rotation = ((index % 2 == 0) and -6 or 6),
			Parent = card,
		})

		local dummyColor = Color3.fromRGB(178, 178, 178)
		create("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.18),
			Size = UDim2.fromOffset(14, 14),
			BackgroundColor3 = dummyColor,
			BorderSizePixel = 0,
			Parent = preview,
		})

		create("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.46),
			Size = UDim2.fromOffset(20, 18),
			BackgroundColor3 = dummyColor,
			BorderSizePixel = 0,
			Parent = preview,
		})

		create("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.24, 0.44),
			Size = UDim2.fromOffset(8, 18),
			BackgroundColor3 = dummyColor,
			BorderSizePixel = 0,
			Rotation = -10,
			Parent = preview,
		})

		create("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.76, 0.44),
			Size = UDim2.fromOffset(8, 18),
			BackgroundColor3 = dummyColor,
			BorderSizePixel = 0,
			Rotation = 10,
			Parent = preview,
		})

		create("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.38, 0.8),
			Size = UDim2.fromOffset(8, 20),
			BackgroundColor3 = dummyColor,
			BorderSizePixel = 0,
			Rotation = 6,
			Parent = preview,
		})

		create("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.62, 0.8),
			Size = UDim2.fromOffset(8, 20),
			BackgroundColor3 = dummyColor,
			BorderSizePixel = 0,
			Rotation = -6,
			Parent = preview,
		})

		create("TextLabel", {
			BackgroundTransparency = 1,
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.new(0, 6, 1, -4),
			Size = UDim2.new(1, -12, 0, 16),
			Font = Enum.Font.Arcade,
			Text = selected and "Selected" or (testerLocked and "Tester only" or string.format("%d kills", skin.UnlockKills)),
			TextColor3 = theme.white,
			TextSize = 9,
			TextXAlignment = Enum.TextXAlignment.Left,
			Parent = card,
		})

		card.MouseEnter:Connect(function()
			TweenService:Create(card, TweenInfo.new(0.1), {
				Size = UDim2.fromOffset(cardWidth + 6, cardHeight + 6),
			}):Play()
			TweenService:Create(stroke, TweenInfo.new(0.1), {
				Transparency = 0.2,
			}):Play()
		end)

		card.MouseLeave:Connect(function()
			TweenService:Create(card, TweenInfo.new(0.1), {
				Size = UDim2.fromOffset(cardWidth, cardHeight),
			}):Play()
			TweenService:Create(stroke, TweenInfo.new(0.1), {
				Transparency = 0.68,
			}):Play()
		end)

		card.MouseButton1Click:Connect(function()
			if not unlocked then
				playUnavailableCardFeedback(card, stroke)
				notify(testerLocked and "Tester access required." or "That skin is unavailable.")
				return
			end

			combatRequest:FireServer({
				Action = "SelectSkin",
				KitId = selectedCategory,
				SkinId = skin.Id,
			})
		end)
	end
end

for category, button in pairs(categoryButtons) do
	button.MouseButton1Click:Connect(function()
		selectedCategory = category
		renderSkinCards()
	end)
end

local settingsPanel = createPanel(settingsPage, "Settings", UDim2.fromOffset(480, 340))

create("TextLabel", {
	BackgroundTransparency = 1,
	Position = UDim2.new(0, 28, 0, 98),
	Size = UDim2.new(1, -56, 0, 70),
	Font = Enum.Font.Arcade,
	Text = "Local visual settings.\nHitboxes only show for you.",
	TextColor3 = theme.white,
	TextSize = 18,
	TextWrapped = true,
	Parent = settingsPanel,
})

local hitboxToggle = createPrimaryButton("Hitboxes: OFF", UDim2.fromScale(0.5, 0.58), UDim2.fromOffset(300, 64), settingsPanel, theme.blue)
hitboxToggle.TextSize = 24
updateHitboxSetting(hitboxToggle)

local backFromSettings = createPrimaryButton("Back", UDim2.fromScale(0.5, 0.87), UDim2.fromOffset(230, 64), settingsPanel, theme.red)

playButton.MouseButton1Click:Connect(function()
	notify("Opening character select")
	showPage("Select")
end)

trainingButton.MouseButton1Click:Connect(teleportToLinkedPlace)

infoButton.MouseButton1Click:Connect(function()
	showPage("Credits")
end)

skinsButton.MouseButton1Click:Connect(function()
	showPage("Skins")
end)

ranksButton.MouseButton1Click:Connect(function()
	showPage("Ranks")
end)

settingsButton.MouseButton1Click:Connect(function()
	showPage("Settings")
end)

backFromCredits.MouseButton1Click:Connect(function()
	showPage("Home")
end)

backFromSkins.MouseButton1Click:Connect(function()
	showPage("Home")
end)

backFromRanks.MouseButton1Click:Connect(function()
	showPage("Home")
end)

enterRankedButton.MouseButton1Click:Connect(teleportToRankedQueue)

backFromSettings.MouseButton1Click:Connect(function()
	showPage("Home")
end)

hitboxToggle.MouseButton1Click:Connect(function()
	playerGui:SetAttribute(Constants.HITBOX_ATTRIBUTE, not playerGui:GetAttribute(Constants.HITBOX_ATTRIBUTE))
	updateHitboxSetting(hitboxToggle)
	notify(playerGui:GetAttribute(Constants.HITBOX_ATTRIBUTE) and "Hitboxes enabled" or "Hitboxes disabled")
end)

backFromSelect.MouseButton1Click:Connect(function()
	showPage("Home")
end)

for index, slot in ipairs(slotConfigs) do
	slotButtons[index].MouseButton1Click:Connect(function()
		if slot.RequiresTester and not hasTesterAccess() then
			playUnavailableCardFeedback(slotButtons[index], slotButtonVisuals[index].Stroke)
			return
		end

		if not slot.Available then
			playUnavailableCardFeedback(slotButtons[index], slotButtonVisuals[index].Stroke)
			notify("That character is not selectable yet.")
			return
		end

		combatRequest:FireServer({
			Action = "SelectKit",
			KitId = slot.KitId or slot.Name,
		})
		closeMenuWithFade()
	end)
end

player:GetAttributeChangedSignal(Constants.TESTER_ACCESS_ATTRIBUTE):Connect(refreshCharacterSlots)

local function getViewportSize()
	local camera = Workspace.CurrentCamera
	return camera and camera.ViewportSize or Vector2.new(1280, 720)
end

local function fitScale(contentWidth, contentHeight, viewportWidth, viewportHeight, paddingX, paddingY, minimum)
	local scale = math.min(
		(viewportWidth - paddingX) / contentWidth,
		(viewportHeight - paddingY) / contentHeight,
		1
	)
	return math.clamp(scale, minimum or 0.65, 1)
end

local function applyMenuLayout()
	local viewport = getViewportSize()
	local viewportWidth = math.max(viewport.X, 320)
	local viewportHeight = math.max(viewport.Y, 520)
	local compact = isTouchDevice or viewportWidth < 760

	rankPopupScale.Scale = compact and fitScale(420, 92, viewportWidth, viewportHeight, 20, 20, 0.55) or 1

	if compact then
		homePageScale.Scale = 1
		creditsPageScale.Scale = 1
		ranksPageScale.Scale = 1
		settingsPageScale.Scale = fitScale(480, 420, viewportWidth, viewportHeight, 18, 36, 0.7)
		selectPageScale.Scale = 1
		skinsPageScale.Scale = 1

		titleBaseY = 0.04
		titleGlowBaseY = 0.054
		homeCardBaseY = 0.72
		title.Position = UDim2.fromScale(0.5, titleBaseY)
		titleGlow.Position = UDim2.fromScale(0.5, titleGlowBaseY)
		title.Size = UDim2.new(0, 520, 0, 104)
		titleGlow.Size = UDim2.new(0, 520, 0, 104)
		title.TextSize = 40
		titleGlow.TextSize = 40

		trainingButton.Position = UDim2.fromScale(0.875, 0.12)
		setButtonBaseSize(trainingButton, 92, 40)
		trainingButton.TextSize = trainingButton.Text == "Main Game" and 12 or 20
		playButton.Position = UDim2.fromScale(0.5, 0.56)
		setButtonBaseSize(playButton, 292, 64)
		playButton.TextSize = 30

		infoButton.Text = "INFO"
		skinsButton.Text = "SKINS"
		ranksButton.Text = "RANK"
		settingsButton.Text = "SET"
		infoButton.Position = UDim2.fromScale(0.42, 0.72)
		skinsButton.Position = UDim2.fromScale(0.58, 0.72)
		ranksButton.Position = UDim2.fromScale(0.42, 0.86)
		settingsButton.Position = UDim2.fromScale(0.58, 0.86)
		setButtonBaseSize(infoButton, 112, 46)
		setButtonBaseSize(skinsButton, 112, 46)
		setButtonBaseSize(ranksButton, 112, 46)
		setButtonBaseSize(settingsButton, 112, 46)
		infoButton.TextSize = 15
		skinsButton.TextSize = 15
		ranksButton.TextSize = 15
		settingsButton.TextSize = 15
		creditsHint.Visible = false
		skinsHint.Visible = false
		ranksHint.Visible = false
		settingsHint.Visible = false

		local creditsPanelWidth = math.min(viewportWidth - 24, 400)
		local creditsPanelHeight = math.min(viewportHeight - 88, 420)
		creditsPanel.Size = UDim2.fromOffset(creditsPanelWidth, creditsPanelHeight)
		creditsPanel.Position = UDim2.fromScale(0.5, 0.5)
		creditsScroll.Position = UDim2.fromOffset(18, 74)
		creditsScroll.Size = UDim2.new(1, -36, 1, -144)
		creditsScroll.ScrollBarThickness = 4
		backFromCredits.Parent = creditsPanel
		backFromCredits.Position = UDim2.new(0.5, 0, 1, -28)
		setButtonBaseSize(backFromCredits, 156, 42)
		backFromCredits.TextSize = 20

		local selectPanelWidth = math.min(viewportWidth - 24, 400)
		local selectPanelHeight = math.min(viewportHeight - 88, 500)
		selectPanel.Size = UDim2.fromOffset(selectPanelWidth, selectPanelHeight)
		selectPanel.Position = UDim2.fromScale(0.5, 0.5)
		selectScroll.Position = UDim2.fromOffset(18, 74)
		selectScroll.Size = UDim2.new(1, -36, 1, -132)
		selectScroll.ScrollBarThickness = 4
		selectIntroLabel.Position = UDim2.fromOffset(0, 0)
		selectIntroLabel.Size = UDim2.new(1, 0, 0, 34)
		selectIntroLabel.TextSize = 12
		selectIntroLabel.TextWrapped = true
		local selectButtonWidth = 150
		local selectButtonHeight = 94
		local selectGapX = 14
		local selectGapY = 12
		local selectStartX = 0
		local selectStartY = 46
		for index, button in ipairs(slotButtons) do
			local row = math.floor((index - 1) / 2)
			local col = (index - 1) % 2
			local x = selectStartX + (col * (selectButtonWidth + selectGapX))
			local y = selectStartY + (row * (selectButtonHeight + selectGapY))
			button.Position = UDim2.fromOffset(x, y)
			button.Size = UDim2.fromOffset(selectButtonWidth, selectButtonHeight)
			for _, child in ipairs(button:GetChildren()) do
				if child:IsA("TextLabel") then
					child.TextSize = child.Position.Y.Offset < 20 and 16 or 9
				end
			end
		end
		local selectRows = math.max(1, math.ceil(#slotButtons / 2))
		selectScroll.CanvasSize = UDim2.new(0, 0, 0, selectStartY + ((selectRows - 1) * (selectButtonHeight + selectGapY)) + selectButtonHeight + 8)
		backFromSelect.Parent = selectPanel
		backFromSelect.Position = UDim2.new(0.5, 0, 1, -44)
		setButtonBaseSize(backFromSelect, 156, 42)
		backFromSelect.TextSize = 20

		local skinsPanelWidth = math.min(viewportWidth - 24, 400)
		skinsPanel.Size = UDim2.fromOffset(skinsPanelWidth, math.min(viewportHeight - 64, 600))
		skinCharacterTitle.AnchorPoint = Vector2.new(0, 0)
		skinCharacterTitle.Position = UDim2.fromOffset(22, 22)
		skinCharacterTitle.Size = UDim2.new(1, -44, 0, 32)
		skinCharacterTitle.TextSize = 24
		skinCharacterTitle.TextXAlignment = Enum.TextXAlignment.Left
		skinKillsTitle.AnchorPoint = Vector2.new(0, 0)
		skinKillsTitle.Position = UDim2.fromOffset(22, 54)
		skinKillsTitle.Size = UDim2.new(1, -44, 0, 22)
		skinKillsTitle.TextSize = 11
		skinKillsTitle.TextXAlignment = Enum.TextXAlignment.Left
		rankedStatsTitle.AnchorPoint = Vector2.new(0, 0)
		rankedStatsTitle.Position = UDim2.fromOffset(22, 76)
		rankedStatsTitle.Size = UDim2.new(1, -44, 0, 22)
		rankedStatsTitle.TextSize = 10
		rankedStatsTitle.TextXAlignment = Enum.TextXAlignment.Left
		categoryPanel.Position = UDim2.fromOffset(22, 108)
		categoryPanel.Size = UDim2.new(1, -44, 0, 44)
		local categoryCount = #skinCategories
		local categoryGap = 8
		local categoryWidth = math.floor((skinsPanelWidth - 44 - (categoryGap * math.max(0, categoryCount - 1))) / math.max(1, categoryCount))
		for index, category in ipairs(skinCategories) do
			local button = categoryButtons[category]
			button.Position = UDim2.new(0, (index - 1) * (categoryWidth + categoryGap), 0, 0)
			button.Size = UDim2.fromOffset(categoryWidth, 40)
			button.TextSize = 16
		end
		cardsContainer.Position = UDim2.fromOffset(22, 166)
		cardsContainer.Size = UDim2.new(1, -44, 1, -246)
		backFromSkins.Position = UDim2.new(0.5, 0, 1, -30)
		setButtonBaseSize(backFromSkins, 180, 56)
		backFromSkins.TextSize = 24

		local ranksPanelWidth = math.min(viewportWidth - 24, 400)
		local ranksPanelHeight = math.min(viewportHeight - 88, 500)
		ranksPanel.Size = UDim2.fromOffset(ranksPanelWidth, ranksPanelHeight)
		ranksPanel.Position = UDim2.fromScale(0.5, 0.5)
		ranksIntroLabel.Position = UDim2.fromOffset(20, 86)
		ranksIntroLabel.Size = UDim2.new(1, -40, 0, 30)
		ranksIntroLabel.TextSize = 12
		ranksCurrentStats.Position = UDim2.fromOffset(20, 116)
		ranksCurrentStats.Size = UDim2.new(1, -40, 0, 28)
		ranksCurrentStats.TextSize = 12
		ranksTierScroll.Position = UDim2.fromOffset(20, 150)
		ranksTierScroll.Size = UDim2.new(1, -40, 1, -238)
		ranksTierScroll.ScrollBarThickness = 4
		ranksTierScroll.CanvasPosition = Vector2.zero
		for index, rowInfo in ipairs(rankTierRows) do
			local y = (index - 1) * 42
			rowInfo.Row.Position = UDim2.fromOffset(0, y)
			rowInfo.Row.Size = UDim2.new(1, -6, 0, 34)
			rowInfo.NameLabel.Position = UDim2.new(0, 12, 0, 8)
			rowInfo.NameLabel.Size = UDim2.new(0.56, 0, 0, 16)
			rowInfo.NameLabel.TextSize = 12
			rowInfo.RangeLabel.Position = UDim2.new(0.48, 0, 0, 8)
			rowInfo.RangeLabel.Size = UDim2.new(0.48, -12, 0, 16)
			rowInfo.RangeLabel.TextSize = 11
		end
		ranksTierScroll.CanvasSize = UDim2.new(0, 0, 0, (#rankTierRows * 42) - 8)
		enterRankedButton.Parent = ranksPanel
		backFromRanks.Parent = ranksPanel
		enterRankedButton.Position = UDim2.new(0.32, 0, 1, -52)
		backFromRanks.Position = UDim2.new(0.68, 0, 1, -52)
		setButtonBaseSize(enterRankedButton, 126, 38)
		setButtonBaseSize(backFromRanks, 104, 38)
		enterRankedButton.TextSize = 18
		backFromRanks.TextSize = 18
	else
		homePageScale.Scale = 1
		creditsPageScale.Scale = 1
		skinsPageScale.Scale = 1
		ranksPageScale.Scale = 1
		settingsPageScale.Scale = 1
		selectPageScale.Scale = 1

		titleBaseY = 0.02
		titleGlowBaseY = 0.035
		homeCardBaseY = 0.74
		title.Position = UDim2.fromScale(0.5, titleBaseY)
		titleGlow.Position = UDim2.fromScale(0.5, titleGlowBaseY)
		title.Size = UDim2.new(0, 1120, 0, 172)
		titleGlow.Size = UDim2.new(0, 1120, 0, 172)
		title.TextSize = 70
		titleGlow.TextSize = 70

		trainingButton.Position = UDim2.fromScale(0.86, 0.13)
		setButtonBaseSize(trainingButton, 104, 50)
		trainingButton.TextSize = trainingButton.Text == "Main Game" and 18 or 24
		playButton.Position = UDim2.fromScale(0.5, 0.73)
		setButtonBaseSize(playButton, 388, 70)
		playButton.TextSize = 36

		infoButton.Text = "?"
		skinsButton.Text = "SK"
		ranksButton.Text = "RANK"
		settingsButton.Text = "SET"
		infoButton.Position = UDim2.fromScale(0.38, 0.865)
		skinsButton.Position = UDim2.fromScale(0.46, 0.865)
		ranksButton.Position = UDim2.fromScale(0.54, 0.865)
		settingsButton.Position = UDim2.fromScale(0.62, 0.865)
		setButtonBaseSize(infoButton, 72, 72)
		setButtonBaseSize(skinsButton, 72, 72)
		setButtonBaseSize(ranksButton, 72, 72)
		setButtonBaseSize(settingsButton, 72, 72)
		infoButton.TextSize = 34
		skinsButton.TextSize = 20
		ranksButton.TextSize = 14
		settingsButton.TextSize = 18
		creditsHint.Visible = true
		skinsHint.Visible = true
		ranksHint.Visible = true
		settingsHint.Visible = true

		local desktopCreditsPanelWidth = math.min(viewportWidth - 40, 520)
		local desktopCreditsPanelHeight = math.min(viewportHeight - 72, 760)
		creditsPanel.Size = UDim2.fromOffset(desktopCreditsPanelWidth, desktopCreditsPanelHeight)
		creditsPanel.Position = UDim2.fromScale(0.5, 0.5)
		creditsScroll.Position = UDim2.new(0, 20, 0, 86)
		creditsScroll.Size = UDim2.new(1, -40, 1, -150)
		creditsScroll.ScrollBarThickness = 6
		backFromCredits.Parent = creditsPanel
		backFromCredits.Position = UDim2.new(0.5, 0, 1, -38)
		setButtonBaseSize(backFromCredits, 260, 70)
		backFromCredits.TextSize = 34

		selectPanel.Size = UDim2.fromOffset(900, 470)
		selectPanel.Position = UDim2.fromScale(0.5, 0.53)
		selectScroll.Position = UDim2.new(0, 34, 0, 66)
		selectScroll.Size = UDim2.new(1, -68, 1, -154)
		selectScroll.ScrollBarThickness = 6
		selectIntroLabel.Position = UDim2.fromOffset(0, 0)
		selectIntroLabel.Size = UDim2.new(1, 0, 0, 26)
		selectIntroLabel.TextSize = 14
		selectIntroLabel.TextWrapped = false
		for index, button in ipairs(slotButtons) do
			local col = (index - 1) % 3
			local row = math.floor((index - 1) / 3)
			button.Position = UDim2.fromOffset(col * 274, 50 + row * 142)
			button.Size = UDim2.fromOffset(242, 116)
			for _, child in ipairs(button:GetChildren()) do
				if child:IsA("TextLabel") then
					child.TextSize = child.Position.Y.Offset < 20 and 20 or 11
				end
			end
		end
		local selectRows = math.max(1, math.ceil(#slotButtons / 3))
		selectScroll.CanvasSize = UDim2.new(0, 0, 0, 50 + ((selectRows - 1) * 142) + 116 + 8)
		backFromSelect.Parent = selectPanel
		backFromSelect.Position = UDim2.new(0.5, 0, 1, -40)
		setButtonBaseSize(backFromSelect, 240, 68)
		backFromSelect.TextSize = 34

		skinsPanel.Size = UDim2.fromOffset(980, 660)
		skinCharacterTitle.AnchorPoint = Vector2.new(1, 0)
		skinCharacterTitle.Position = UDim2.new(1, -42, 0, 22)
		skinCharacterTitle.Size = UDim2.fromOffset(300, 40)
		skinCharacterTitle.TextSize = 28
		skinCharacterTitle.TextXAlignment = Enum.TextXAlignment.Right
		skinKillsTitle.AnchorPoint = Vector2.new(1, 0)
		skinKillsTitle.Position = UDim2.new(1, -42, 0, 58)
		skinKillsTitle.Size = UDim2.fromOffset(420, 26)
		skinKillsTitle.TextSize = 15
		skinKillsTitle.TextXAlignment = Enum.TextXAlignment.Right
		rankedStatsTitle.AnchorPoint = Vector2.new(1, 0)
		rankedStatsTitle.Position = UDim2.new(1, -42, 0, 84)
		rankedStatsTitle.Size = UDim2.fromOffset(420, 22)
		rankedStatsTitle.TextSize = 13
		rankedStatsTitle.TextXAlignment = Enum.TextXAlignment.Right
		categoryPanel.Position = UDim2.new(0, 20, 0, 102)
		categoryPanel.Size = UDim2.fromOffset(306, 318)
		for index, category in ipairs(skinCategories) do
			local button = categoryButtons[category]
			button.Position = UDim2.new(0, 0, 0, (index - 1) * 54)
			button.Size = UDim2.fromOffset(306, 44)
			button.TextSize = 18
		end
		cardsContainer.Position = UDim2.new(0, 338, 0, 102)
		cardsContainer.Size = UDim2.new(1, -360, 1, -152)
		backFromSkins.Position = UDim2.fromScale(0.5, 0.94)
		setButtonBaseSize(backFromSkins, 260, 70)
		backFromSkins.TextSize = 34

		ranksPanel.Size = UDim2.fromOffset(620, 640)
		ranksPanel.Position = UDim2.fromScale(0.5, 0.53)
		ranksIntroLabel.Position = UDim2.new(0, 28, 0, 92)
		ranksIntroLabel.Size = UDim2.new(1, -56, 0, 44)
		ranksIntroLabel.TextSize = 16
		ranksCurrentStats.Position = UDim2.new(0, 28, 0, 136)
		ranksCurrentStats.Size = UDim2.new(1, -56, 0, 34)
		ranksCurrentStats.TextSize = 16
		ranksTierScroll.Position = UDim2.new(0, 28, 0, 188)
		ranksTierScroll.Size = UDim2.new(1, -56, 1, -292)
		ranksTierScroll.ScrollBarThickness = 6
		for index, rowInfo in ipairs(rankTierRows) do
			rowInfo.Row.Position = UDim2.fromOffset(0, (index - 1) * 72)
			rowInfo.Row.Size = UDim2.new(1, -8, 0, 56)
			rowInfo.NameLabel.Position = UDim2.new(0, 18, 0, 10)
			rowInfo.NameLabel.Size = UDim2.new(0.52, 0, 0, 20)
			rowInfo.NameLabel.TextSize = 18
			rowInfo.RangeLabel.Position = UDim2.new(0.5, 0, 0, 10)
			rowInfo.RangeLabel.Size = UDim2.new(0.46, -18, 0, 20)
			rowInfo.RangeLabel.TextSize = 18
		end
		ranksTierScroll.CanvasSize = UDim2.new(0, 0, 0, (#rankTierRows * 72) - 16)
		enterRankedButton.Parent = ranksPage
		backFromRanks.Parent = ranksPage
		enterRankedButton.Position = UDim2.fromScale(0.5, 0.84)
		backFromRanks.Position = UDim2.fromScale(0.5, 0.92)
		setButtonBaseSize(enterRankedButton, 286, 64)
		setButtonBaseSize(backFromRanks, 240, 68)
		enterRankedButton.TextSize = 24
		backFromRanks.TextSize = 34
	end

	for _, button in ipairs({
		playButton,
		trainingButton,
		infoButton,
		skinsButton,
		ranksButton,
		settingsButton,
		backFromCredits,
		backFromSelect,
		backFromSkins,
		backFromRanks,
		enterRankedButton,
		hitboxToggle,
		backFromSettings,
	}) do
		styleMenuButton(button, compact, button == playButton or button == trainingButton or button == enterRankedButton)
	end

	task.defer(renderSkinCards)
end

renderSkinCards()
applyMenuLayout()

local function bindMenuViewport(camera)
	if menuViewportConnection then
		menuViewportConnection:Disconnect()
		menuViewportConnection = nil
	end

	if camera then
		menuViewportConnection = camera:GetPropertyChangedSignal("ViewportSize"):Connect(applyMenuLayout)
	end
end

bindMenuViewport(Workspace.CurrentCamera)
Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
	bindMenuViewport(Workspace.CurrentCamera)
	applyMenuLayout()
end)

local startTime = os.clock()
RunService.RenderStepped:Connect(function()
	local elapsed = os.clock() - startTime
	titleGlow.Position = UDim2.fromScale(0.5, titleGlowBaseY + math.sin(elapsed * 0.6) * 0.003)
	floorGlow.Size = UDim2.new(1.28 + math.sin(elapsed * 0.5) * 0.03, 0, 0.42, 0)
	homeCard.Position = UDim2.fromScale(0.5, homeCardBaseY + math.sin(elapsed * 0.45) * 0.002)
	homeCardGlow.BackgroundTransparency = 0.9 - (math.sin(elapsed * 0.9) * 0.03)

	for index, particle in ipairs(particles) do
		local y = particle.BaseY - ((elapsed * particle.Speed) % 0.28)
		if y < 0.34 then
			particle.BaseY = 1.02 + (index % 4) * 0.03
			y = particle.BaseY
		end

		local x = particle.BaseX + math.sin(elapsed * (0.8 + index * 0.03)) * particle.Amplitude
		particle.Frame.Position = UDim2.fromScale(x, y)
	end
end)

local function hookCharacter(character)
	local humanoid = character:FindFirstChildOfClass("Humanoid") or character:WaitForChild("Humanoid")
	humanoid.Died:Connect(function()
		refreshMenuFromSelectionState()
	end)
end

player.CharacterAdded:Connect(hookCharacter)
if player.Character then
	hookCharacter(player.Character)
end

player:GetAttributeChangedSignal(Constants.AWAITING_CHARACTER_ATTRIBUTE):Connect(refreshMenuFromSelectionState)
refreshMenuFromSelectionState()

local function refreshMenuVisibility()
	gui.Enabled = playerGui:GetAttribute(Constants.LOADING_ATTRIBUTE) and playerGui:GetAttribute(Constants.MENU_ATTRIBUTE)
	local globalMusicOverrideActive = playerGui:GetAttribute(Constants.GLOBAL_MUSIC_OVERRIDE_ATTRIBUTE) == true
	if gui.Enabled and not globalMusicOverrideActive and menuMusic.SoundId ~= "" then
		if not menuMusic.IsPlaying then
			menuMusic:Play()
		end
		TweenService:Create(menuMusic, TweenInfo.new(0.4), {
			Volume = Constants.MENU_MUSIC_VOLUME,
		}):Play()
	else
		if menuMusic.IsPlaying then
			local fadeOut = TweenService:Create(menuMusic, TweenInfo.new(0.25), {
				Volume = 0,
			})
			fadeOut:Play()
			fadeOut.Completed:Once(function()
				if (not gui.Enabled or globalMusicOverrideActive) and menuMusic.IsPlaying then
					menuMusic:Stop()
				end
			end)
		end
	end
end

playerGui:GetAttributeChangedSignal(Constants.LOADING_ATTRIBUTE):Connect(refreshMenuVisibility)
playerGui:GetAttributeChangedSignal(Constants.MENU_ATTRIBUTE):Connect(refreshMenuVisibility)
playerGui:GetAttributeChangedSignal(Constants.GLOBAL_MUSIC_OVERRIDE_ATTRIBUTE):Connect(refreshMenuVisibility)
refreshMenuVisibility()

combatState.OnClientEvent:Connect(function(payload)
	if typeof(payload) ~= "table" then
		return
	end

	if payload.Type == "Profile" then
		local previousTier = Constants.GetRankTierName(currentRankedRating)
		local previousRating = currentRankedRating
		currentKills = payload.Kills or 0
		currentDeaths = payload.Deaths or 0
		currentKDR = payload.KDR or 0
		currentRankedRating = payload.RankedRating or Constants.RANKED_START_RATING
		currentRankedWins = payload.RankedWins or 0
		currentRankedLosses = payload.RankedLosses or 0
		selectedSkins = payload.SelectedSkins or selectedSkins
		local newTier = Constants.GetRankTierName(currentRankedRating)
		if hasLoadedProfile and newTier ~= previousTier and currentRankedRating ~= previousRating then
			if currentRankedRating > previousRating then
				showRankPopup("Promotion", string.format("%s -> %s", previousTier, newTier), theme.green)
			else
				showRankPopup("Demotion", string.format("%s -> %s", previousTier, newTier), theme.red)
			end
		end
		hasLoadedProfile = true
		renderSkinCards()
	end
end)

combatRequest:FireServer({Action = "RequestProfile"})
