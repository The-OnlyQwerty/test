local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")
local Workspace = game:GetService("Workspace")

local CharacterKits = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("CharacterKits"))
local Constants = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Constants"))

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local combatRequest = remotes:WaitForChild("CombatRequest")
local combatState = remotes:WaitForChild("CombatState")
local hudAssetResolver = remotes:FindFirstChild("HudAssetResolver")

local cooldowns = {}
local profileStats = {
	RankedRating = Constants.RANKED_START_RATING,
	RankedWins = 0,
	RankedLosses = 0,
}
local rankedQueued = false
local theme = {
	bg = Color3.fromRGB(12, 14, 18),
	panel = Color3.fromRGB(24, 28, 36),
	panelAlt = Color3.fromRGB(31, 36, 46),
	text = Color3.fromRGB(238, 240, 245),
	subtle = Color3.fromRGB(158, 167, 181),
	accent = Color3.fromRGB(224, 72, 72),
	accent2 = Color3.fromRGB(83, 166, 255),
	gold = Color3.fromRGB(236, 198, 87),
	red = Color3.fromRGB(207, 73, 73),
	white = Color3.fromRGB(245, 247, 252),
}
local isTouchDevice = UserInputService.TouchEnabled
local DAMAGE_COUNTER_LIFETIME = 1.8
local COMBAT_CUE_LIFETIME = 0.95
local viewportConnection
local naoyaMarkIndicators = {}
local samuraiBleedIndicators = {}
local naoyaFrozenVisuals = {}
local function uiAssetImage(assetId)
	local numericId = tostring(assetId):match("%d+")
	return numericId and ("rbxthumb://type=Asset&id=" .. numericId .. "&w=420&h=420") or ""
end

local MAGNUS_WHITE_SHIELD_DECAL_ID = 134443559446640
local MAGNUS_BLACK_SHIELD_DECAL_ID = 92058835636666
local MAGNUS_BLACK_BAR_DECAL_ID = 98661191382059
local MAGNUS_SHIELD_POSITION = UDim2.fromScale(0.5, 0.515)
local MAGNUS_SHIELD_SIZE = UDim2.fromScale(0.94, 0.94)
local MAGNUS_LABEL_POSITION = UDim2.fromScale(0.5, 0.5)
local MAGNUS_TEXT_POSITION = UDim2.fromScale(0.532, 0.375)
local MAGNUS_TEXT_SIZE = UDim2.fromScale(0.72, 0.5)
local MAGNUS_BLACK_SHIELD_RECT_OFFSET = Vector2.new(0, 127)
local MAGNUS_BLACK_SHIELD_RECT_SIZE = Vector2.new(1012, 898)
local MAGNUS_WHITE_SHIELD_RECT_OFFSET = Vector2.new(120, 183)
local MAGNUS_WHITE_SHIELD_RECT_SIZE = Vector2.new(792, 702)
local MAGNUS_STATS_BAR_SIZE_DESKTOP = UDim2.new(1, 44, 1, 34)
local MAGNUS_STATS_BAR_SIZE_TOUCH = UDim2.new(1, 24, 1, 18)
local MAGNUS_STATS_BAR_RECT_OFFSET = Vector2.new(149, 298)
local MAGNUS_STATS_BAR_RECT_SIZE = Vector2.new(736, 328)
local magnusAssetImages = {
	WhiteShield = uiAssetImage(MAGNUS_WHITE_SHIELD_DECAL_ID),
	BlackShield = uiAssetImage(MAGNUS_BLACK_SHIELD_DECAL_ID),
	BlackBar = uiAssetImage(MAGNUS_BLACK_BAR_DECAL_ID),
}
local damageCounterState = {
	Direct = 0,
	Karmic = 0,
	ExpiresAt = 0,
}
local combatCueState = {
	Text = "",
	Color = theme.text,
	ExpiresAt = 0,
}
local updateTouchPanels

local function isRankedQueuePlace()
	return Constants.RANKED_QUEUE_PLACE_ID ~= 0 and game.PlaceId == Constants.RANKED_QUEUE_PLACE_ID
end

local function isAdmin()
	for _, userId in ipairs(Constants.ADMIN_USER_IDS) do
		if userId == player.UserId then
			return true
		end
	end
	return false
end

local adminCommandEntries = {
	{
		Command = "setkills",
		Usage = "/setkills <player> <amount>",
		Description = "Set a player's kill count.",
	},
	{
		Command = "setdeaths",
		Usage = "/setdeaths <player> <amount>",
		Description = "Set a player's death count.",
	},
	{
		Command = "setrating",
		Usage = "/setrating <player> <amount>",
		Description = "Set a player's ranked rating.",
	},
	{
		Command = "buff",
		Usage = "/buff <player> Attack <amount>",
		Description = "Set one buffed stat value on a player.",
	},
	{
		Command = "theme",
		Usage = "/theme <character|off|list>",
		Description = "Play or clear a global character theme.",
	},
}

local function create(instanceType, props)
	local instance = Instance.new(instanceType)
	for key, value in pairs(props) do
		instance[key] = value
	end
	return instance
end

local function getCharacterParts(character)
	local parts = {}
	if not character then
		return parts
	end

	for _, descendant in ipairs(character:GetDescendants()) do
		if descendant:IsA("BasePart") then
			table.insert(parts, descendant)
		end
	end

	return parts
end

local function getControls()
	return _G.JudgementDividedControls
end

local function getLockOn()
	return _G.JudgementDividedLockOn
end

local function buildBeveledBackdrop(parent, padding, color, zIndex)
	local backdrop = create("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Parent = parent,
		ZIndex = zIndex,
	})

	local function makePart(position, size, rotation)
		local part = create("Frame", {
			Position = position,
			Size = size,
			BackgroundColor3 = color,
			BorderSizePixel = 0,
			Rotation = rotation or 0,
			Parent = backdrop,
			ZIndex = zIndex,
		})
		return part
	end

	makePart(UDim2.new(0, padding, 0, 0), UDim2.new(1, -(padding * 2), 1, 0))
	makePart(UDim2.new(0, 0, 0, padding), UDim2.new(1, 0, 1, -(padding * 2)))

	local cornerSize = padding * 2
	makePart(UDim2.new(0, 0, 0, 0), UDim2.fromOffset(cornerSize, cornerSize), 45)
	makePart(UDim2.new(1, -cornerSize, 0, 0), UDim2.fromOffset(cornerSize, cornerSize), 45)
	makePart(UDim2.new(0, 0, 1, -cornerSize), UDim2.fromOffset(cornerSize, cornerSize), 45)
	makePart(UDim2.new(1, -cornerSize, 1, -cornerSize), UDim2.fromOffset(cornerSize, cornerSize), 45)

	return backdrop
end

local function styleModeSwitcherButton(button)
	button.BackgroundTransparency = 1
	button.AutoButtonColor = false
	local backdropZ = math.max(0, (button.ZIndex or 1) - 1)

	buildBeveledBackdrop(button, 6, Color3.fromRGB(10, 12, 16), backdropZ)
	buildBeveledBackdrop(button, 5, theme.panelAlt, backdropZ)
	buildBeveledBackdrop(button, 7, theme.panel, backdropZ)

	local shine = create("Frame", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.12),
		Size = UDim2.new(0.4, 0, 0, 3),
		BackgroundColor3 = Color3.fromRGB(78, 84, 94),
		BorderSizePixel = 0,
		Parent = button,
		ZIndex = backdropZ,
	})
	create("UICorner", {
		CornerRadius = UDim.new(1, 0),
		Parent = shine,
	})

	button.TextColor3 = theme.text
	button.TextStrokeTransparency = 0.75
end

local gui = create("ScreenGui", {
	Name = "CombatHud",
	ResetOnSpawn = false,
	IgnoreGuiInset = true,
})
gui.Parent = playerGui
gui.Enabled = not playerGui:GetAttribute(Constants.MENU_ATTRIBUTE)

local root = create("Frame", {
	Name = "Root",
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.fromScale(0.5, 1),
	Size = UDim2.fromScale(1, 1),
	BackgroundTransparency = 1,
	Parent = gui,
})

local damageCounterPanel = create("Frame", {
	Name = "DamageCounter",
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.fromScale(0.5, 0.1),
	Size = UDim2.fromOffset(260, 86),
	BackgroundTransparency = 1,
	Visible = false,
	Parent = root,
})

local karmicDamageLabel = create("TextLabel", {
	BackgroundTransparency = 1,
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.fromScale(0.5, 0),
	Size = UDim2.new(1, 0, 0, 20),
	Font = Enum.Font.Arcade,
	Text = "",
	TextColor3 = theme.gold,
	TextSize = 16,
	TextStrokeColor3 = Color3.fromRGB(12, 14, 18),
	TextStrokeTransparency = 0.35,
	TextXAlignment = Enum.TextXAlignment.Center,
	Parent = damageCounterPanel,
})

local damageCounterLabel = create("TextLabel", {
	BackgroundTransparency = 1,
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.fromScale(0.5, 0.18),
	Size = UDim2.new(1, 0, 0, 52),
	Font = Enum.Font.Arcade,
	Text = "0",
	TextColor3 = theme.text,
	TextSize = 34,
	TextStrokeColor3 = Color3.fromRGB(12, 14, 18),
	TextStrokeTransparency = 0.2,
	TextXAlignment = Enum.TextXAlignment.Center,
	Parent = damageCounterPanel,
})

local damageCounterCaption = create("TextLabel", {
	BackgroundTransparency = 1,
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.fromScale(0.5, 1),
	Size = UDim2.new(1, 0, 0, 18),
	Font = Enum.Font.GothamBold,
	Text = "Damage",
	TextColor3 = theme.subtle,
	TextSize = 12,
	TextXAlignment = Enum.TextXAlignment.Center,
	Parent = damageCounterPanel,
})

local combatCuePanel = create("Frame", {
	Name = "CombatCue",
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.fromScale(0.5, 0.2),
	Size = UDim2.fromOffset(240, 34),
	BackgroundColor3 = theme.panel,
	BackgroundTransparency = 0.16,
	BorderSizePixel = 0,
	Visible = false,
	Parent = root,
})
create("UICorner", {
	CornerRadius = UDim.new(0, 12),
	Parent = combatCuePanel,
})
create("UIStroke", {
	Color = Color3.fromRGB(72, 78, 92),
	Transparency = 0.28,
	Thickness = 1.1,
	Parent = combatCuePanel,
})

local combatCueLabel = create("TextLabel", {
	BackgroundTransparency = 1,
	Size = UDim2.fromScale(1, 1),
	Font = Enum.Font.Arcade,
	Text = "",
	TextColor3 = theme.text,
	TextSize = 18,
	TextStrokeColor3 = Color3.fromRGB(12, 14, 18),
	TextStrokeTransparency = 0.35,
	TextXAlignment = Enum.TextXAlignment.Center,
	TextYAlignment = Enum.TextYAlignment.Center,
	Parent = combatCuePanel,
})

local dodgeDebugLabel = create("TextLabel", {
	Visible = false,
	BackgroundColor3 = Color3.fromRGB(10, 10, 14),
	BackgroundTransparency = 0.18,
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.fromScale(0.5, 0.02),
	Size = UDim2.fromOffset(420, 28),
	Font = Enum.Font.GothamBold,
	Text = "",
	TextColor3 = Color3.fromRGB(255, 240, 120),
	TextSize = 14,
	TextStrokeTransparency = 0.55,
	Parent = gui,
})
create("UICorner", {
	CornerRadius = UDim.new(0, 10),
	Parent = dodgeDebugLabel,
})

local resourcesPanel = create("Frame", {
	Name = "Resources",
	AnchorPoint = Vector2.new(0, 1),
	Position = UDim2.new(0, 18, 1, -116),
	Size = UDim2.new(0, 370, 0, 134),
	BackgroundColor3 = theme.panel,
	BorderSizePixel = 0,
	Parent = root,
})
local resourcesPanelCorner = create("UICorner", {CornerRadius = UDim.new(0, 16), Parent = resourcesPanel})
local resourcesPanelStroke = create("UIStroke", {
	Color = Color3.fromRGB(42, 44, 52),
	Transparency = 1,
	Thickness = 1.2,
	Parent = resourcesPanel,
})

local magnusStatsBackdrop = create("ImageLabel", {
	Name = "MagnusStatsBackdrop",
	BackgroundTransparency = 1,
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = MAGNUS_STATS_BAR_SIZE_DESKTOP,
	Image = magnusAssetImages.BlackBar,
	ImageTransparency = 1,
	ScaleType = Enum.ScaleType.Stretch,
	ImageRectOffset = MAGNUS_STATS_BAR_RECT_OFFSET,
	ImageRectSize = MAGNUS_STATS_BAR_RECT_SIZE,
	Visible = false,
	Parent = resourcesPanel,
})

local title = create("TextLabel", {
	BackgroundTransparency = 1,
	Position = UDim2.new(0, 16, 0, 10),
	Size = UDim2.new(1, -32, 0, 24),
	Font = Enum.Font.GothamBold,
	Text = "Character",
	TextColor3 = theme.text,
	TextSize = 22,
	TextXAlignment = Enum.TextXAlignment.Left,
	Parent = resourcesPanel,
})

local subtitle = create("TextLabel", {
	BackgroundTransparency = 1,
	Position = UDim2.new(0, 16, 0, 34),
	Size = UDim2.new(1, -32, 0, 18),
	Font = Enum.Font.Gotham,
	Text = "Mode",
	TextColor3 = theme.subtle,
	TextSize = 13,
	TextXAlignment = Enum.TextXAlignment.Left,
	Parent = resourcesPanel,
})

local stats = create("TextLabel", {
	BackgroundTransparency = 1,
	Position = UDim2.new(0, 16, 0, 54),
	Size = UDim2.new(1, -32, 0, 18),
	Font = Enum.Font.Gotham,
	Text = "",
	TextColor3 = theme.subtle,
	TextSize = 12,
	TextXAlignment = Enum.TextXAlignment.Left,
	Parent = resourcesPanel,
})

local touchLockButton
local touchModeButton
if isTouchDevice then
	touchLockButton = create("TextButton", {
		BackgroundColor3 = theme.panelAlt,
		BorderSizePixel = 0,
		Font = Enum.Font.GothamBold,
		Text = "LOCK",
		TextColor3 = theme.text,
		TextSize = 11,
		AutoButtonColor = true,
		Parent = root,
	})
	create("UICorner", {CornerRadius = UDim.new(0, 10), Parent = touchLockButton})

	touchModeButton = create("TextButton", {
		BackgroundColor3 = theme.panelAlt,
		BorderSizePixel = 0,
		Font = Enum.Font.GothamBold,
		Text = "MODE",
		TextColor3 = theme.text,
		TextSize = 11,
		AutoButtonColor = true,
		Parent = root,
	})
	styleModeSwitcherButton(touchModeButton)
end

local bars = {}
local function makeBar(name, order, color)
	local y = 78 + (order - 1) * 18
	local label = create("TextLabel", {
		BackgroundTransparency = 1,
		Position = UDim2.new(0, 16, 0, y),
		Size = UDim2.new(0, 70, 0, 14),
		Font = Enum.Font.GothamMedium,
		Text = name,
		TextColor3 = theme.subtle,
		TextSize = 12,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = resourcesPanel,
	})

	local track = create("Frame", {
		Position = UDim2.new(0, 92, 0, y + 1),
		Size = UDim2.new(0, 208, 0, 12),
		BackgroundColor3 = theme.panelAlt,
		BorderSizePixel = 0,
		Parent = resourcesPanel,
	})
	create("UICorner", {CornerRadius = UDim.new(1, 0), Parent = track})

	local fill = create("Frame", {
		Size = UDim2.new(1, 0, 1, 0),
		BackgroundColor3 = color,
		BorderSizePixel = 0,
		Parent = track,
	})
	create("UICorner", {CornerRadius = UDim.new(1, 0), Parent = fill})

	local value = create("TextLabel", {
		BackgroundTransparency = 1,
		Position = UDim2.new(0, 308, 0, y - 2),
		Size = UDim2.new(0, 50, 0, 18),
		Font = Enum.Font.GothamMedium,
		Text = "0/0",
		TextColor3 = theme.text,
		TextSize = 12,
		TextXAlignment = Enum.TextXAlignment.Right,
		Parent = resourcesPanel,
	})

	bars[name] = {
		Label = label,
		Track = track,
		Fill = fill,
		Value = value,
	}
end

makeBar("HP", 1, theme.accent)
makeBar("Mana", 2, theme.accent2)
makeBar("Stamina", 3, theme.gold)

local opponentPanel = create("Frame", {
	Name = "OpponentResources",
	AnchorPoint = Vector2.new(0, 0.5),
	Position = UDim2.new(0, 18, 0.5, 0),
	Size = UDim2.fromOffset(180, 86),
	BackgroundColor3 = theme.panel,
	BackgroundTransparency = 0.08,
	BorderSizePixel = 0,
	Visible = false,
	Parent = root,
})
create("UICorner", {CornerRadius = UDim.new(0, 14), Parent = opponentPanel})

local opponentTitle = create("TextLabel", {
	BackgroundTransparency = 1,
	Position = UDim2.fromOffset(10, 8),
	Size = UDim2.new(1, -20, 0, 16),
	Font = Enum.Font.GothamBold,
	Text = "Target",
	TextColor3 = theme.text,
	TextSize = 14,
	TextTruncate = Enum.TextTruncate.AtEnd,
	TextXAlignment = Enum.TextXAlignment.Left,
	Parent = opponentPanel,
})

local opponentBars = {}
local function makeOpponentBar(name, order, color)
	local y = 26 + ((order - 1) * 18)
	local label = create("TextLabel", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(10, y),
		Size = UDim2.fromOffset(32, 12),
		Font = Enum.Font.GothamMedium,
		Text = name,
		TextColor3 = theme.subtle,
		TextSize = 10,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = opponentPanel,
	})

	local track = create("Frame", {
		Position = UDim2.fromOffset(42, y + 1),
		Size = UDim2.fromOffset(92, 8),
		BackgroundColor3 = theme.panelAlt,
		BorderSizePixel = 0,
		Parent = opponentPanel,
	})
	create("UICorner", {CornerRadius = UDim.new(1, 0), Parent = track})

	local fill = create("Frame", {
		Size = UDim2.new(1, 0, 1, 0),
		BackgroundColor3 = color,
		BorderSizePixel = 0,
		Parent = track,
	})
	create("UICorner", {CornerRadius = UDim.new(1, 0), Parent = fill})

	local value = create("TextLabel", {
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -10, 0, y - 3),
		Size = UDim2.fromOffset(34, 14),
		Font = Enum.Font.GothamMedium,
		Text = "0/0",
		TextColor3 = theme.text,
		TextSize = 10,
		TextXAlignment = Enum.TextXAlignment.Right,
		Parent = opponentPanel,
	})

	opponentBars[name] = {
		Label = label,
		Track = track,
		Fill = fill,
		Value = value,
	}
end

makeOpponentBar("HP", 1, theme.accent)
makeOpponentBar("Mana", 2, theme.accent2)

local opponentMarksLabel = create("TextLabel", {
	BackgroundTransparency = 1,
	Position = UDim2.fromOffset(10, 62),
	Size = UDim2.new(1, -20, 0, 12),
	Font = Enum.Font.GothamBold,
	Text = "Frames: 0/3",
	TextColor3 = theme.gold,
	TextSize = 10,
	TextXAlignment = Enum.TextXAlignment.Left,
	Visible = false,
	Parent = opponentPanel,
})

local function getHealthDisplayColor(ratio)
	if ratio >= 0.95 then
		return Color3.fromRGB(76, 214, 104)
	elseif ratio >= 0.65 then
		return Color3.fromRGB(239, 214, 83)
	elseif ratio >= 0.35 then
		return Color3.fromRGB(240, 158, 66)
	end

	return Color3.fromRGB(217, 76, 76)
end

local function formatStatusMarkCount(count)
	local rounded = math.floor((count + 0.0001) * 4 + 0.5) / 4
	local whole = math.floor(rounded + 0.0001)
	if math.abs(rounded - whole) < 0.001 then
		return tostring(whole)
	end

	local halfRounded = math.floor((rounded * 2) + 0.5) / 2
	if math.abs(rounded - halfRounded) < 0.001 then
		return string.format("%.1f", rounded)
	end

	local text = string.format("%.2f", rounded)
	if string.sub(text, -1) == "0" then
		text = string.sub(text, 1, -2)
	end
	return text
end

local function getNaoyaFrameMarkColor(count, isFrozen)
	if isFrozen then
		return Color3.fromRGB(170, 235, 255)
	end
	if count >= (Constants.NAOYA_FRAME_MARK_MAX or 3) then
		return Color3.fromRGB(255, 120, 120)
	end
	return theme.gold
end

local function getSamuraiBleedColor(count, isBleeding)
	if isBleeding then
		return Color3.fromRGB(255, 120, 120)
	end
	if count >= (Constants.SAMURAI_BLEED_MARK_MAX or 3) then
		return Color3.fromRGB(255, 84, 84)
	end
	return Color3.fromRGB(214, 92, 92)
end

local function getOpponentStatusText(target, frameMarks, isFrozen, samuraiBleedMarks, isSamuraiBleeding)
	local primaryText = ""
	local primaryColor = theme.subtle

	if frameMarks > 0 or isFrozen then
		primaryText = string.format("Frames: %s/%d%s", formatStatusMarkCount(frameMarks), Constants.NAOYA_FRAME_MARK_MAX or 3, isFrozen and "  FROZEN" or "")
		primaryColor = getNaoyaFrameMarkColor(frameMarks, isFrozen)
	elseif samuraiBleedMarks > 0 or isSamuraiBleeding then
		primaryText = string.format("Bleed: %s/%d%s", formatStatusMarkCount(samuraiBleedMarks), Constants.SAMURAI_BLEED_MARK_MAX or 3, isSamuraiBleeding and "  BLEEDING" or "")
		primaryColor = getSamuraiBleedColor(samuraiBleedMarks, isSamuraiBleeding)
	end

	local states = {}
	if target:GetAttribute("Blocking") == true then
		table.insert(states, "BLOCK")
	end
	if target:GetAttribute("Stunned") == true and not isFrozen then
		table.insert(states, "STUN")
	end
	if target:GetAttribute("Dodging") == true then
		table.insert(states, "DODGE")
	end

	local statusText = table.concat(states, " | ")
	if primaryText ~= "" and statusText ~= "" then
		return primaryText .. " | " .. statusText, primaryColor
	elseif primaryText ~= "" then
		return primaryText, primaryColor
	elseif statusText ~= "" then
		local statusColor = target:GetAttribute("Blocking") == true and Color3.fromRGB(170, 215, 255)
			or (target:GetAttribute("Stunned") == true and Color3.fromRGB(240, 120, 120))
			or theme.subtle
		return statusText, statusColor
	end

	return "", theme.subtle
end

local selectorPanel = create("Frame", {
	Name = "Selector",
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, -18, 0, 18),
	Size = UDim2.new(0, 236, 0, 156),
	BackgroundColor3 = theme.panel,
	BorderSizePixel = 0,
	Parent = root,
})
selectorPanel.Visible = false
create("UICorner", {CornerRadius = UDim.new(0, 16), Parent = selectorPanel})

create("TextLabel", {
	BackgroundTransparency = 1,
	Position = UDim2.new(0, 16, 0, 12),
	Size = UDim2.new(1, -32, 0, 22),
	Font = Enum.Font.GothamBold,
	Text = "Combat",
	TextColor3 = theme.text,
	TextSize = 20,
	TextXAlignment = Enum.TextXAlignment.Left,
	Parent = selectorPanel,
})

create("TextLabel", {
	BackgroundTransparency = 1,
	Position = UDim2.new(0, 16, 0, 34),
	Size = UDim2.new(1, -32, 0, 16),
	Font = Enum.Font.Gotham,
	Text = "Character swap is menu-only.",
	TextColor3 = theme.subtle,
	TextSize = 12,
	TextXAlignment = Enum.TextXAlignment.Left,
	Parent = selectorPanel,
})

local modeButton = create("TextButton", {
	Position = UDim2.new(0, 16, 0, 60),
	Size = UDim2.new(1, -32, 0, 34),
	BackgroundColor3 = theme.accent2,
	BorderSizePixel = 0,
	Font = Enum.Font.GothamBold,
	Text = "Switch Mode",
	TextColor3 = theme.text,
	TextSize = 15,
	Parent = selectorPanel,
})
styleModeSwitcherButton(modeButton)

local rankedButton = create("TextButton", {
	Position = UDim2.new(0, 16, 0, 100),
	Size = UDim2.new(1, -32, 0, 30),
	BackgroundColor3 = theme.gold,
	BorderSizePixel = 0,
	Font = Enum.Font.GothamBold,
	Text = "Join Ranked",
	TextColor3 = theme.bg,
	TextSize = 14,
	Parent = selectorPanel,
})
create("UICorner", {CornerRadius = UDim.new(0, 10), Parent = rankedButton})

local rankedStatus = create("TextLabel", {
	BackgroundTransparency = 1,
	Position = UDim2.new(0, 16, 0, 132),
	Size = UDim2.new(1, -32, 0, 16),
	Font = Enum.Font.Gotham,
	Text = "Ranked 1000 | W 0 | L 0",
	TextColor3 = theme.subtle,
	TextSize = 11,
	TextXAlignment = Enum.TextXAlignment.Left,
	Parent = selectorPanel,
})

local hotkeys = create("TextLabel", {
	BackgroundTransparency = 1,
	AnchorPoint = Vector2.new(1, 1),
	Position = UDim2.new(1, -18, 1, -18),
	Size = UDim2.new(0, 340, 0, 22),
	Font = Enum.Font.Gotham,
	Text = "Q/E Mode   Shift Dash   MMB Lock   X Relock   1-5 Abilities   Y/N Duel",
	TextColor3 = theme.subtle,
	TextSize = 12,
	TextXAlignment = Enum.TextXAlignment.Right,
	Parent = root,
})
hotkeys.Visible = not isTouchDevice

local adminPanel = create("Frame", {
	Name = "AdminPanel",
	Visible = false,
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.fromScale(0.5, 0.02),
	Size = UDim2.fromOffset(560, 250),
	BackgroundColor3 = theme.panel,
	BorderSizePixel = 0,
	Parent = root,
})
create("UICorner", {CornerRadius = UDim.new(0, 16), Parent = adminPanel})
create("UIStroke", {
	Color = Color3.fromRGB(54, 60, 72),
	Transparency = 0.15,
	Thickness = 1.2,
	Parent = adminPanel,
})

create("TextLabel", {
	BackgroundTransparency = 1,
	Position = UDim2.new(0, 16, 0, 10),
	Size = UDim2.new(1, -32, 0, 24),
	Font = Enum.Font.GothamBold,
	Text = "Admin Command Bar",
	TextColor3 = theme.text,
	TextSize = 20,
	TextXAlignment = Enum.TextXAlignment.Left,
	Parent = adminPanel,
})

create("TextLabel", {
	BackgroundTransparency = 1,
	Position = UDim2.new(0, 16, 0, 34),
	Size = UDim2.new(1, -32, 0, 18),
	Font = Enum.Font.GothamMedium,
	Text = "Type a command, then press Enter. Suggestions update as you type.",
	TextColor3 = theme.subtle,
	TextSize = 13,
	TextXAlignment = Enum.TextXAlignment.Left,
	Parent = adminPanel,
})

local adminCommandBar = create("TextBox", {
	Name = "AdminCommandBar",
	Position = UDim2.new(0, 16, 0, 58),
	Size = UDim2.new(1, -32, 0, 38),
	BackgroundColor3 = theme.panelAlt,
	BorderSizePixel = 0,
	Font = Enum.Font.GothamMedium,
	Text = "",
	TextColor3 = theme.text,
	TextSize = 16,
	TextXAlignment = Enum.TextXAlignment.Left,
	PlaceholderText = "theme Sans",
	PlaceholderColor3 = Color3.fromRGB(134, 142, 156),
	ClearTextOnFocus = false,
	Parent = adminPanel,
})
create("UICorner", {CornerRadius = UDim.new(0, 12), Parent = adminCommandBar})
create("UIPadding", {
	PaddingLeft = UDim.new(0, 12),
	PaddingRight = UDim.new(0, 12),
	Parent = adminCommandBar,
})

local adminHint = create("TextLabel", {
	BackgroundTransparency = 1,
	Position = UDim2.new(0, 16, 0, 100),
	Size = UDim2.new(1, -32, 0, 16),
	Font = Enum.Font.Gotham,
	Text = "Enter to run  â¢  Esc to close  â¢  Click a suggestion to fill",
	TextColor3 = theme.subtle,
	TextSize = 12,
	TextXAlignment = Enum.TextXAlignment.Left,
	Parent = adminPanel,
})

local adminSuggestionsFrame = create("Frame", {
	Name = "AdminSuggestions",
	Position = UDim2.new(0, 16, 0, 122),
	Size = UDim2.new(1, -32, 0, 112),
	BackgroundTransparency = 1,
	Parent = adminPanel,
})

local adminSuggestionRows = {}
for index = 1, 4 do
	local row = create("TextButton", {
		Name = "Suggestion" .. tostring(index),
		Visible = false,
		Position = UDim2.new(0, 0, 0, (index - 1) * 28),
		Size = UDim2.new(1, 0, 0, 24),
		BackgroundColor3 = theme.panelAlt,
		BackgroundTransparency = 0.08,
		BorderSizePixel = 0,
		Text = "",
		AutoButtonColor = true,
		Parent = adminSuggestionsFrame,
	})
	create("UICorner", {CornerRadius = UDim.new(0, 10), Parent = row})

	local usageLabel = create("TextLabel", {
		BackgroundTransparency = 1,
		Position = UDim2.new(0, 10, 0, 2),
		Size = UDim2.new(0.62, -10, 1, -4),
		Font = Enum.Font.GothamMedium,
		Text = "",
		TextColor3 = theme.text,
		TextSize = 12,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = row,
	})

	local descriptionLabel = create("TextLabel", {
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -10, 0, 2),
		Size = UDim2.new(0.36, 0, 1, -4),
		Font = Enum.Font.Gotham,
		Text = "",
		TextColor3 = theme.subtle,
		TextSize = 11,
		TextTruncate = Enum.TextTruncate.AtEnd,
		TextXAlignment = Enum.TextXAlignment.Right,
		Parent = row,
	})

	adminSuggestionRows[index] = {
		Button = row,
		Usage = usageLabel,
		Description = descriptionLabel,
	}
end

local function trimText(text)
	if type(text) ~= "string" then
		return ""
	end

	return text:match("^%s*(.-)%s*$") or ""
end

local function getAdminSuggestions(inputText)
	local trimmed = string.lower(trimText(inputText))
	if string.sub(trimmed, 1, 1) == "/" then
		trimmed = string.sub(trimmed, 2)
	end

	local firstToken = trimmed:match("^(%S+)") or ""
	local matches = {}
	for _, entry in ipairs(adminCommandEntries) do
		local usageText = string.lower(entry.Usage)
		local descriptionText = string.lower(entry.Description)
		local commandText = string.lower(entry.Command)
		local matchesEntry = false

		if firstToken == "" then
			matchesEntry = true
		elseif string.sub(commandText, 1, #firstToken) == firstToken then
			matchesEntry = true
		elseif trimmed ~= "" and (string.find(usageText, trimmed, 1, true) or string.find(descriptionText, trimmed, 1, true)) then
			matchesEntry = true
		end

		if matchesEntry then
			table.insert(matches, entry)
		end

		if #matches >= #adminSuggestionRows then
			break
		end
	end

	return matches
end

local function updateAdminSuggestions()
	local matches = getAdminSuggestions(adminCommandBar.Text)
	for index, row in ipairs(adminSuggestionRows) do
		local entry = matches[index]
		row.Button.Visible = entry ~= nil
		row.Button:SetAttribute("SuggestionUsage", entry and entry.Usage or "")
		row.Usage.Text = entry and entry.Usage or ""
		row.Description.Text = entry and entry.Description or ""
	end

	adminHint.Text = (#matches > 0)
		and "Enter to run  â¢  Esc to close  â¢  Click a suggestion to fill"
		or "No matching admin commands"
end

local function closeAdminPanel()
	adminPanel.Visible = false
	if adminCommandBar:IsFocused() then
		adminCommandBar:ReleaseFocus(false)
	end
end

local function openAdminPanel()
	adminPanel.Visible = true
	updateAdminSuggestions()
	task.defer(function()
		if adminPanel.Visible then
			adminCommandBar:CaptureFocus()
			adminCommandBar.CursorPosition = #adminCommandBar.Text + 1
		end
	end)
end

local function submitAdminCommand()
	local commandText = trimText(adminCommandBar.Text)
	if commandText == "" then
		return
	end

	if string.sub(commandText, 1, 1) ~= "/" then
		commandText = "/" .. commandText
	end

	combatRequest:FireServer({
		Action = "AdminCommand",
		CommandText = commandText,
	})
	adminCommandBar.Text = ""
	updateAdminSuggestions()
	closeAdminPanel()
end

for _, row in ipairs(adminSuggestionRows) do
	row.Button.MouseButton1Click:Connect(function()
		local usage = row.Button:GetAttribute("SuggestionUsage")
		if type(usage) ~= "string" or usage == "" then
			return
		end

		adminCommandBar.Text = usage
		updateAdminSuggestions()
		task.defer(function()
			if adminPanel.Visible then
				adminCommandBar:CaptureFocus()
				adminCommandBar.CursorPosition = #adminCommandBar.Text + 1
			end
		end)
	end)
end

adminCommandBar:GetPropertyChangedSignal("Text"):Connect(updateAdminSuggestions)
adminCommandBar.FocusLost:Connect(function(enterPressed)
	if adminPanel.Visible and enterPressed then
		submitAdminCommand()
	end
end)
updateAdminSuggestions()

local abilityPanel = create("Frame", {
	Name = "Abilities",
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, -18),
	Size = UDim2.new(0, 640, 0, 90),
	BackgroundColor3 = theme.panel,
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	Parent = root,
})
create("UICorner", {CornerRadius = UDim.new(0, 18), Parent = abilityPanel})

local abilitySlots = {}
local slotOrder = {
	{"Z", "1"},
	{"X", "2"},
	{"C", "3"},
	{"V", "4"},
	{"G", "5"},
}
for index, slotInfo in ipairs(slotOrder) do
	local key = slotInfo[1]
	local displayKey = slotInfo[2]
	local cell = create("Frame", {
		Position = UDim2.new(0, 14 + (index - 1) * 122, 0, 12),
		Size = UDim2.new(0, 108, 0, 66),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Parent = abilityPanel,
	})

	local diamondShadow = create("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.8, 0.8),
		BackgroundColor3 = Color3.fromRGB(8, 10, 14),
		BorderSizePixel = 0,
		Rotation = 45,
		Parent = cell,
		ZIndex = 0,
	})
	create("UICorner", {CornerRadius = UDim.new(0, 10), Parent = diamondShadow})

	local diamond = create("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.72, 0.72),
		BackgroundColor3 = theme.panelAlt,
		BorderSizePixel = 0,
		Rotation = 45,
		Parent = cell,
		ZIndex = 1,
	})
	create("UICorner", {CornerRadius = UDim.new(0, 8), Parent = diamond})
	local diamondStroke = create("UIStroke", {
		Color = theme.gold,
		Transparency = 0.28,
		Thickness = 1.4,
		Parent = diamond,
	})

	local circle = create("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.58, 0.58),
		BackgroundColor3 = theme.panel,
		BorderSizePixel = 0,
		Parent = cell,
		ZIndex = 2,
	})
	create("UICorner", {CornerRadius = UDim.new(1, 0), Parent = circle})
	local circleStroke = create("UIStroke", {
		Color = theme.gold,
		Transparency = 0.15,
		Thickness = 1.6,
		Parent = circle,
	})

	local magnusShieldBase = create("ImageLabel", {
		Name = "MagnusShieldBase",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = MAGNUS_SHIELD_POSITION,
	Size = MAGNUS_SHIELD_SIZE,
	Image = magnusAssetImages.BlackShield,
	ImageTransparency = 1,
	ScaleType = Enum.ScaleType.Stretch,
	ImageRectOffset = MAGNUS_BLACK_SHIELD_RECT_OFFSET,
	ImageRectSize = MAGNUS_BLACK_SHIELD_RECT_SIZE,
	Visible = false,
	Parent = cell,
	ZIndex = 1,
	})

	local magnusShieldCooldown = create("ImageLabel", {
		Name = "MagnusShieldCooldown",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = MAGNUS_SHIELD_POSITION,
	Size = MAGNUS_SHIELD_SIZE,
	Image = magnusAssetImages.WhiteShield,
	ImageTransparency = 1,
	ScaleType = Enum.ScaleType.Stretch,
	ImageRectOffset = MAGNUS_WHITE_SHIELD_RECT_OFFSET,
	ImageRectSize = MAGNUS_WHITE_SHIELD_RECT_SIZE,
	Visible = false,
	Parent = cell,
	ZIndex = 6,
	})

	local keyLabel = create("TextLabel", {
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1, 1),
		Font = Enum.Font.GothamBold,
		Text = displayKey,
		TextColor3 = theme.gold,
		TextSize = 26,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextYAlignment = Enum.TextYAlignment.Center,
		Parent = circle,
		ZIndex = 5,
	})

	local nameLabel = create("TextLabel", {
		BackgroundTransparency = 1,
		Position = UDim2.new(0, 10, 0, 24),
		Size = UDim2.new(1, -20, 0, 24),
		Font = Enum.Font.GothamMedium,
		TextWrapped = true,
		Text = "-",
		TextColor3 = theme.text,
		TextSize = 12,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		Visible = false,
		Parent = cell,
	})

	local cooldownShade = create("Frame", {
		Visible = false,
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.28,
		Size = UDim2.fromScale(1, 1),
		BorderSizePixel = 0,
		Parent = circle,
		ZIndex = 6,
	})
	create("UICorner", {CornerRadius = UDim.new(1, 0), Parent = cooldownShade})

	local cooldownLabel = create("TextLabel", {
		Visible = false,
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1, 1),
		Font = Enum.Font.GothamBold,
		Text = "",
		TextColor3 = theme.text,
		TextSize = 20,
		Parent = circle,
		ZIndex = 7,
	})

	local readyFlash = create("Frame", {
		Visible = false,
		BackgroundColor3 = theme.gold,
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		BorderSizePixel = 0,
		Parent = circle,
		ZIndex = 4,
	})
	create("UICorner", {CornerRadius = UDim.new(1, 0), Parent = readyFlash})

	abilitySlots[key] = {
		Cell = cell,
		DiamondShadow = diamondShadow,
		Diamond = diamond,
		DiamondStroke = diamondStroke,
		Circle = circle,
		CircleStroke = circleStroke,
		Key = keyLabel,
		Name = nameLabel,
		CooldownShade = cooldownShade,
		CooldownLabel = cooldownLabel,
		ReadyFlash = readyFlash,
		MagnusShieldBase = magnusShieldBase,
		MagnusShieldCooldown = magnusShieldCooldown,
		MagnusCooldownFade = 1,
		WasCoolingDown = false,
		ReadyFlashAlpha = 1,
	}

	if isTouchDevice then
		local touchButton = create("TextButton", {
			BackgroundTransparency = 1,
			Size = UDim2.fromScale(1, 1),
			Text = "",
			AutoButtonColor = false,
			Parent = cell,
		})
		touchButton.InputBegan:Connect(function(input)
			if input.UserInputType ~= Enum.UserInputType.Touch and input.UserInputType ~= Enum.UserInputType.MouseButton1 then
				return
			end
			local controls = getControls()
			if controls and controls.BeginAbilityInput then
				controls.BeginAbilityInput(key)
			end
		end)
		touchButton.InputEnded:Connect(function(input)
			if input.UserInputType ~= Enum.UserInputType.Touch and input.UserInputType ~= Enum.UserInputType.MouseButton1 then
				return
			end
			local controls = getControls()
			if controls and controls.EndAbilityInput then
				controls.EndAbilityInput(key)
			end
		end)
		touchButton.MouseLeave:Connect(function()
			local controls = getControls()
			if controls and controls.EndAbilityInput then
				controls.EndAbilityInput(key)
			end
		end)
		abilitySlots[key].TouchButton = touchButton
	end
end

local function applyMagnusHudImages()
	magnusStatsBackdrop.Image = magnusAssetImages.BlackBar
	for _, slot in pairs(abilitySlots) do
		slot.MagnusShieldBase.Image = magnusAssetImages.BlackShield
		slot.MagnusShieldCooldown.Image = magnusAssetImages.WhiteShield
	end
end

applyMagnusHudImages()

task.spawn(function()
	if not hudAssetResolver or not hudAssetResolver:IsA("RemoteFunction") then
		return
	end

	local ok, resolved = pcall(function()
		return hudAssetResolver:InvokeServer("ResolveUiAssetTextures", {
			WhiteShield = MAGNUS_WHITE_SHIELD_DECAL_ID,
			BlackShield = MAGNUS_BLACK_SHIELD_DECAL_ID,
			BlackBar = MAGNUS_BLACK_BAR_DECAL_ID,
		})
	end)
	if not ok or typeof(resolved) ~= "table" then
		return
	end

	local changed = false
	for key, image in pairs(resolved) do
		if typeof(image) == "string" and image ~= "" then
			magnusAssetImages[key] = image
			changed = true
		end
	end

	if changed then
		applyMagnusHudImages()
	end
end)

local mobileDashButton
local mobileBlockButton
local telePanel
local duelPromptPanel
local duelPromptLabel
if isTouchDevice then
	local function createMobileButton(parent, text, x, y, width, height, color, textColor)
		local button = create("TextButton", {
			Position = UDim2.fromOffset(x, y),
			Size = UDim2.fromOffset(width, height),
			BackgroundColor3 = color,
			BackgroundTransparency = 0.12,
			BorderSizePixel = 0,
			Font = Enum.Font.GothamBold,
			Text = text,
			TextColor3 = textColor or theme.text,
			TextSize = 16,
			AutoButtonColor = true,
			Parent = parent,
		})
		create("UICorner", {CornerRadius = UDim.new(0, 12), Parent = button})
		return button
	end

	mobileDashButton = createMobileButton(root, "DASH", 0, 0, 76, 42, theme.accent2)
	mobileDashButton.AnchorPoint = Vector2.new(1, 1)
	mobileBlockButton = createMobileButton(root, "BLOCK", 0, 0, 150, 42, theme.gold, theme.bg)
	mobileBlockButton.AnchorPoint = Vector2.new(1, 1)

	telePanel = create("Frame", {
		Name = "TelePanel",
		Visible = false,
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -18, 1, -372),
		Size = UDim2.fromOffset(150, 132),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Parent = root,
	})

	local teleForwardButton = createMobileButton(telePanel, "W", 50, 0, 50, 32, theme.panelAlt)
	local teleLeftButton = createMobileButton(telePanel, "A", 0, 38, 46, 32, theme.panelAlt)
	local teleDownButton = createMobileButton(telePanel, "S", 52, 38, 46, 32, theme.panelAlt)
	local teleRightButton = createMobileButton(telePanel, "D", 104, 38, 46, 32, theme.panelAlt)
	local teleUpButton = createMobileButton(telePanel, "UP", 24, 78, 102, 36, theme.accent2)

	duelPromptPanel = create("Frame", {
		Name = "DuelPrompt",
		Visible = false,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.045),
		Size = UDim2.fromOffset(286, 114),
		BackgroundColor3 = theme.panel,
		BorderSizePixel = 0,
		Parent = root,
	})
	create("UICorner", {CornerRadius = UDim.new(0, 18), Parent = duelPromptPanel})

	create("TextLabel", {
		BackgroundTransparency = 1,
		Position = UDim2.new(0, 14, 0, 10),
		Size = UDim2.new(1, -28, 0, 20),
		Font = Enum.Font.GothamBold,
		Text = "DUEL REQUEST",
		TextColor3 = theme.text,
		TextSize = 16,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = duelPromptPanel,
	})

	duelPromptLabel = create("TextLabel", {
		BackgroundTransparency = 1,
		Position = UDim2.new(0, 14, 0, 34),
		Size = UDim2.new(1, -28, 0, 30),
		Font = Enum.Font.Gotham,
		Text = "Opponent challenged you.",
		TextColor3 = theme.subtle,
		TextSize = 13,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		Parent = duelPromptPanel,
	})

	local acceptButton = createMobileButton(duelPromptPanel, "ACCEPT", 14, 72, 122, 28, theme.accent2)
	local declineButton = createMobileButton(duelPromptPanel, "DECLINE", 150, 72, 122, 28, theme.red)

	mobileDashButton.MouseButton1Click:Connect(function()
		local controls = getControls()
		if controls and controls.Dash then
			controls.Dash()
		end
	end)

	local blockHeldByTouch = false
	local blockTouchInput = nil
	local function startBlock(input)
		if blockHeldByTouch then
			return
		end
		blockHeldByTouch = true
		blockTouchInput = input
		local controls = getControls()
		if controls and controls.BlockStart then
			controls.BlockStart()
		end
	end

	local function endBlock(input)
		if not blockHeldByTouch then
			return
		end
		if blockTouchInput and input and input ~= blockTouchInput then
			return
		end
		blockHeldByTouch = false
		blockTouchInput = nil
		local controls = getControls()
		if controls and controls.BlockEnd then
			controls.BlockEnd()
		end
	end

	mobileBlockButton.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
			startBlock(input)
		end
	end)
	mobileBlockButton.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
			endBlock(input)
		end
	end)
	mobileBlockButton.MouseLeave:Connect(function()
		endBlock()
	end)
	UserInputService.TouchEnded:Connect(function(input)
		if blockHeldByTouch then
			endBlock(input)
		end
	end)

	touchLockButton.MouseButton1Click:Connect(function()
		local lockOn = getLockOn()
		if not lockOn then
			return
		end
		if lockOn.GetLockedModel and lockOn.GetLockedModel() then
			if lockOn.ClearLock then
				lockOn.ClearLock(true)
			end
		elseif lockOn.LockNearest then
			lockOn.LockNearest()
		end
		task.defer(updateTouchPanels)
	end)

	touchModeButton.MouseButton1Click:Connect(function()
		local controls = getControls()
		if controls and controls.SwitchModeNext then
			controls.SwitchModeNext()
		end
	end)

	local function sendTeleMove(direction)
		local controls = getControls()
		if controls and controls.TelekinesisMove then
			controls.TelekinesisMove(direction)
		end
	end

	teleForwardButton.MouseButton1Click:Connect(function()
		sendTeleMove("W")
	end)
	teleLeftButton.MouseButton1Click:Connect(function()
		sendTeleMove("A")
	end)
	teleDownButton.MouseButton1Click:Connect(function()
		sendTeleMove("S")
	end)
	teleRightButton.MouseButton1Click:Connect(function()
		sendTeleMove("D")
	end)
	teleUpButton.MouseButton1Click:Connect(function()
		sendTeleMove("Space")
	end)

	local function respondToDuel(accepted)
		local controls = getControls()
		if controls and controls.RespondToDuel then
			controls.RespondToDuel(accepted)
		end
		duelPromptPanel.Visible = false
	end

	acceptButton.MouseButton1Click:Connect(function()
		respondToDuel(true)
	end)
	declineButton.MouseButton1Click:Connect(function()
		respondToDuel(false)
	end)
end

local function getCharacter()
	return player.Character
end

local function getKitId()
	local character = getCharacter()
	return character and character:GetAttribute("KitId")
end

local function getMode()
	local character = getCharacter()
	return character and character:GetAttribute("Mode")
end

local function getCurrentKit()
	local kitId = getKitId()
	return kitId and CharacterKits[kitId]
end

local function isMagnusKit(kit)
	return kit and kit.DisplayName == "Magnus"
end

local function getKitForCharacter(character)
	local kitId = character and character:GetAttribute("KitId")
	return kitId and CharacterKits[kitId]
end

local function getIndicatorAnchor(character)
	if not character then
		return nil
	end

	return character:FindFirstChild("Head") or character:FindFirstChild("HumanoidRootPart")
end

local function setFrozenCharacterVisibility(character, hidden)
	for _, part in ipairs(getCharacterParts(character)) do
		part.LocalTransparencyModifier = hidden and 1 or 0
	end
end

local function createFrozenSegment(parent, position, size, color, zIndex)
	local outline = create("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = position,
		Size = size,
		BackgroundColor3 = Color3.fromRGB(18, 26, 40),
		BorderSizePixel = 0,
		Parent = parent,
		ZIndex = zIndex,
	})
	create("UICorner", {
		CornerRadius = UDim.new(0, math.max(2, math.floor(math.min(size.X.Offset, size.Y.Offset) * 0.12))),
		Parent = outline,
	})

	local fill = create("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(1, -4, 1, -4),
		BackgroundColor3 = color,
		BorderSizePixel = 0,
		Parent = outline,
		ZIndex = zIndex + 1,
	})
	create("UICorner", {
		CornerRadius = UDim.new(0, math.max(2, math.floor(math.min(size.X.Offset, size.Y.Offset) * 0.1))),
		Parent = fill,
	})

	return outline
end

local function createNaoyaFrozenVisual(character)
	local anchor = character and character:FindFirstChild("HumanoidRootPart")
	if not anchor then
		return nil
	end

	local billboard = create("BillboardGui", {
		Name = "NaoyaFrozenVisual",
		Adornee = anchor,
		Size = UDim2.fromOffset(120, 188),
		StudsOffsetWorldSpace = Vector3.new(0, 2.8, 0),
		AlwaysOnTop = false,
		LightInfluence = 0,
		Enabled = true,
		Parent = gui,
	})

	local container = create("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Parent = billboard,
	})

	local silhouetteColor = Color3.fromRGB(218, 236, 255)
	local accentColor = Color3.fromRGB(142, 205, 255)
	local glow = create("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(96, 166),
		BackgroundColor3 = Color3.fromRGB(120, 205, 255),
		BackgroundTransparency = 0.78,
		BorderSizePixel = 0,
		Parent = container,
		ZIndex = 0,
	})
	create("UICorner", {
		CornerRadius = UDim.new(0, 24),
		Parent = glow,
	})

	createFrozenSegment(container, UDim2.fromOffset(60, 26), UDim2.fromOffset(30, 30), silhouetteColor, 1)
	createFrozenSegment(container, UDim2.fromOffset(60, 76), UDim2.fromOffset(46, 60), silhouetteColor, 1)
	createFrozenSegment(container, UDim2.fromOffset(32, 78), UDim2.fromOffset(18, 58), accentColor, 1)
	createFrozenSegment(container, UDim2.fromOffset(88, 78), UDim2.fromOffset(18, 58), accentColor, 1)
	createFrozenSegment(container, UDim2.fromOffset(48, 136), UDim2.fromOffset(18, 60), silhouetteColor, 1)
	createFrozenSegment(container, UDim2.fromOffset(72, 136), UDim2.fromOffset(18, 60), silhouetteColor, 1)

	for index = 1, 5 do
		local stripe = create("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(60, 42 + (index * 22)),
			Size = UDim2.fromOffset(64 - (index * 4), 2),
			BackgroundColor3 = Color3.fromRGB(120, 200, 255),
			BackgroundTransparency = 0.35 + (index * 0.08),
			BorderSizePixel = 0,
			Rotation = -8,
			Parent = container,
			ZIndex = 3,
		})
		create("UICorner", {
			CornerRadius = UDim.new(1, 0),
			Parent = stripe,
		})
	end

	return {
		Gui = billboard,
	}
end

local function clearNaoyaFrozenVisual(character)
	local visual = naoyaFrozenVisuals[character]
	if visual then
		visual.Gui:Destroy()
		naoyaFrozenVisuals[character] = nil
	end
	setFrozenCharacterVisibility(character, false)
end

local function updateNaoyaFrozenVisualForCharacter(character)
	if not character then
		return
	end

	if character == player.Character then
		if naoyaFrozenVisuals[character] then
			clearNaoyaFrozenVisual(character)
		end
		return
	end

	local isFrozen = character:GetAttribute("NaoyaFrozen") == true
	local rootPart = character:FindFirstChild("HumanoidRootPart")
	local visual = naoyaFrozenVisuals[character]

	if not isFrozen or not rootPart then
		if visual then
			clearNaoyaFrozenVisual(character)
		end
		return
	end

	if not visual then
		visual = createNaoyaFrozenVisual(character)
		if not visual then
			return
		end
		naoyaFrozenVisuals[character] = visual
	end

	visual.Gui.Adornee = rootPart
	setFrozenCharacterVisibility(character, true)
end

local function updateNaoyaFrozenVisuals()
	for character, visual in pairs(naoyaFrozenVisuals) do
		if not character.Parent or not character:FindFirstChild("HumanoidRootPart") then
			visual.Gui:Destroy()
			naoyaFrozenVisuals[character] = nil
		end
	end

	for _, otherPlayer in ipairs(Players:GetPlayers()) do
		if otherPlayer.Character then
			updateNaoyaFrozenVisualForCharacter(otherPlayer.Character)
		end
	end

	local npcFolder = Workspace:FindFirstChild("CombatNPCs")
	if npcFolder then
		for _, npc in ipairs(npcFolder:GetChildren()) do
			if npc:IsA("Model") then
				updateNaoyaFrozenVisualForCharacter(npc)
			end
		end
	end
end

local function createNaoyaFrameIndicator(character)
	local anchor = getIndicatorAnchor(character)
	if not anchor then
		return nil
	end

	local billboard = create("BillboardGui", {
		Name = "NaoyaFrameIndicator",
		Adornee = anchor,
		Size = UDim2.fromOffset(84, 24),
		StudsOffsetWorldSpace = Vector3.new(0, 3.4, 0),
		AlwaysOnTop = true,
		LightInfluence = 0,
		Enabled = false,
		Parent = gui,
	})

	local holder = create("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(84, 24),
		BackgroundTransparency = 1,
		Parent = billboard,
	})

	local marks = {}
	for index = 1, (Constants.NAOYA_FRAME_MARK_MAX or 3) do
		local mark = create("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0, 18 + ((index - 1) * 24), 0.5, 0),
			Size = UDim2.fromOffset(12, 12),
			Rotation = 45,
			BackgroundColor3 = theme.gold,
			BackgroundTransparency = 0.05,
			BorderSizePixel = 0,
			Parent = holder,
		})
		create("UICorner", {
			CornerRadius = UDim.new(0, 2),
			Parent = mark,
		})
		marks[index] = mark
	end

	return {
		Gui = billboard,
		Marks = marks,
	}
end

local function updateNaoyaFrameIndicatorForCharacter(character)
	if not character then
		return
	end

	local count = tonumber(character:GetAttribute("NaoyaFrameMarks")) or 0
	local isFrozen = character:GetAttribute("NaoyaFrozen") == true
	local indicator = naoyaMarkIndicators[character]

	if count <= 0 and not isFrozen then
		if indicator then
			indicator.Gui:Destroy()
			naoyaMarkIndicators[character] = nil
		end
		return
	end

	if not indicator then
		indicator = createNaoyaFrameIndicator(character)
		if not indicator then
			return
		end
		naoyaMarkIndicators[character] = indicator
	end

	local color = getNaoyaFrameMarkColor(count, isFrozen)
	indicator.Gui.Adornee = getIndicatorAnchor(character)
	indicator.Gui.Enabled = true

	local fullMarks = math.floor(count + 0.0001)
	local partialMark = math.clamp(count - fullMarks, 0, 1)

	for index, mark in ipairs(indicator.Marks) do
		local isFull = index <= fullMarks
		local isPartial = not isFull and partialMark > 0.001 and index == (fullMarks + 1)
		if isFull then
			mark.BackgroundTransparency = 0.02
			mark.BackgroundColor3 = color
		elseif isPartial then
			mark.BackgroundTransparency = math.clamp(0.72 - (0.62 * partialMark), 0.12, 0.72)
			mark.BackgroundColor3 = color
		else
			mark.BackgroundTransparency = 0.72
			mark.BackgroundColor3 = theme.panelAlt
		end
	end
end

local function updateNaoyaFrameIndicators()
	for character, indicator in pairs(naoyaMarkIndicators) do
		if not character.Parent or not getIndicatorAnchor(character) then
			indicator.Gui:Destroy()
			naoyaMarkIndicators[character] = nil
		end
	end

	for _, otherPlayer in ipairs(Players:GetPlayers()) do
		if otherPlayer.Character then
			updateNaoyaFrameIndicatorForCharacter(otherPlayer.Character)
		end
	end

	local npcFolder = Workspace:FindFirstChild("CombatNPCs")
	if npcFolder then
		for _, npc in ipairs(npcFolder:GetChildren()) do
			if npc:IsA("Model") then
				updateNaoyaFrameIndicatorForCharacter(npc)
			end
		end
	end
end

local function createSamuraiBleedIndicator(character)
	local anchor = getIndicatorAnchor(character)
	if not anchor then
		return nil
	end

	local billboard = create("BillboardGui", {
		Name = "SamuraiBleedIndicator",
		Adornee = anchor,
		Size = UDim2.fromOffset(84, 24),
		StudsOffsetWorldSpace = Vector3.new(0, 3.9, 0),
		AlwaysOnTop = true,
		LightInfluence = 0,
		Enabled = false,
		Parent = gui,
	})

	local holder = create("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(84, 24),
		BackgroundTransparency = 1,
		Parent = billboard,
	})

	local marks = {}
	for index = 1, (Constants.SAMURAI_BLEED_MARK_MAX or 3) do
		local mark = create("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0, 18 + ((index - 1) * 24), 0.5, 0),
			Size = UDim2.fromOffset(12, 12),
			Rotation = 45,
			BackgroundColor3 = Color3.fromRGB(214, 92, 92),
			BackgroundTransparency = 0.05,
			BorderSizePixel = 0,
			Parent = holder,
		})
		create("UICorner", {
			CornerRadius = UDim.new(0, 2),
			Parent = mark,
		})
		marks[index] = mark
	end

	return {
		Gui = billboard,
		Marks = marks,
	}
end

local function updateSamuraiBleedIndicatorForCharacter(character)
	if not character then
		return
	end

	local count = tonumber(character:GetAttribute("SamuraiBleedMarks")) or 0
	local isBleeding = character:GetAttribute("SamuraiBleeding") == true
	local indicator = samuraiBleedIndicators[character]

	if count <= 0 and not isBleeding then
		if indicator then
			indicator.Gui:Destroy()
			samuraiBleedIndicators[character] = nil
		end
		return
	end

	if not indicator then
		indicator = createSamuraiBleedIndicator(character)
		if not indicator then
			return
		end
		samuraiBleedIndicators[character] = indicator
	end

	local color = getSamuraiBleedColor(count, isBleeding)
	indicator.Gui.Adornee = getIndicatorAnchor(character)
	indicator.Gui.Enabled = true

	local fullMarks = math.floor(count + 0.0001)
	local partialMark = math.clamp(count - fullMarks, 0, 1)

	for index, mark in ipairs(indicator.Marks) do
		local isFull = index <= fullMarks
		local isPartial = not isFull and partialMark > 0.001 and index == (fullMarks + 1)
		if isFull then
			mark.BackgroundTransparency = 0.02
			mark.BackgroundColor3 = color
		elseif isPartial then
			mark.BackgroundTransparency = math.clamp(0.72 - (0.62 * partialMark), 0.12, 0.72)
			mark.BackgroundColor3 = color
		else
			mark.BackgroundTransparency = 0.72
			mark.BackgroundColor3 = theme.panelAlt
		end
	end
end

local function updateSamuraiBleedIndicators()
	for character, indicator in pairs(samuraiBleedIndicators) do
		if not character.Parent or not getIndicatorAnchor(character) then
			indicator.Gui:Destroy()
			samuraiBleedIndicators[character] = nil
		end
	end

	for _, otherPlayer in ipairs(Players:GetPlayers()) do
		if otherPlayer.Character then
			updateSamuraiBleedIndicatorForCharacter(otherPlayer.Character)
		end
	end

	local npcFolder = Workspace:FindFirstChild("CombatNPCs")
	if npcFolder then
		for _, npc in ipairs(npcFolder:GetChildren()) do
			if npc:IsA("Model") then
				updateSamuraiBleedIndicatorForCharacter(npc)
			end
		end
	end
end

local function getCurrentAbilities()
	local kit = getCurrentKit()
	local mode = getMode()
	if not kit then
		return {}
	end

	if kit.Modes then
		return kit.Abilities[mode] or {}
	end

	return kit.Abilities.Base or kit.Abilities
end

local function getActiveAbilityKeys()
	local abilities = getCurrentAbilities()
	local activeKeys = {}
	for _, slotInfo in ipairs(slotOrder) do
		local key = slotInfo[1]
		if abilities[key] then
			table.insert(activeKeys, key)
		end
	end
	return activeKeys
end

updateTouchPanels = function()
	if not isTouchDevice then
		return
	end

	if telePanel then
		telePanel.Visible = getKitId() == "Sans" and getMode() == "Telekinesis"
	end
	if touchModeButton then
		local kit = getCurrentKit()
		touchModeButton.Visible = kit ~= nil and kit.Modes ~= nil
	end
	if touchLockButton then
		local lockOn = getLockOn()
		local hasTarget = lockOn and lockOn.GetLockedModel and lockOn.GetLockedModel()
		touchLockButton.Text = hasTarget and "UNLOCK" or "LOCK"
	end
end

local function layoutAbilitySlots(panelWidth, panelHeight, isCompactLayout)
	local activeKeys = getActiveAbilityKeys()
	local count = #activeKeys
	abilityPanel.Visible = count > 0
	if count == 0 then
		return
	end

	local spacing = isCompactLayout and 8 or 12
	local preferredSize = isCompactLayout and 52 or 60
	local cellSize = math.max(40, math.min(preferredSize, math.floor((panelWidth - ((count - 1) * spacing)) / count)))
	local totalWidth = (count * cellSize) + ((count - 1) * spacing)
	local startX = math.floor((panelWidth - totalWidth) * 0.5)
	local y = math.floor((panelHeight - cellSize) * 0.5)

	for index, key in ipairs(activeKeys) do
		local slot = abilitySlots[key]
		slot.Cell.Position = UDim2.fromOffset(startX + ((index - 1) * (cellSize + spacing)), y)
		slot.Cell.Size = UDim2.fromOffset(cellSize, cellSize)
		slot.Cell.BackgroundTransparency = 1
		slot.Key.TextSize = cellSize < 50 and 18 or (isCompactLayout and 20 or 24)
		slot.CooldownLabel.TextSize = isCompactLayout and 16 or 18
	end
end

local function applyResponsiveLayout()
	local camera = Workspace.CurrentCamera
	local viewport = camera and camera.ViewportSize or Vector2.new(1280, 720)
	local viewportWidth = math.max(viewport.X, 320)
	local viewportHeight = math.max(viewport.Y, 520)
	local inset = isTouchDevice and math.max(10, math.floor(math.min(viewportWidth, viewportHeight) * 0.02)) or 18
	local topLeftInset = GuiService:GetGuiInset()
	local safeTopInset = isTouchDevice and math.max(inset, math.floor(topLeftInset.Y) + 8) or inset
	local activeAbilityCount = #getActiveAbilityKeys()

	if isTouchDevice then
		local topOffset = safeTopInset
		local resourceWidth = math.clamp(math.floor(viewportWidth * 0.31), 144, 176)
		local resourceHeight = 74
		resourcesPanel.AnchorPoint = Vector2.new(0, 0)
		resourcesPanel.Position = UDim2.fromOffset(inset, topOffset)
		resourcesPanel.Size = UDim2.fromOffset(resourceWidth, resourceHeight)
		resourcesPanel.BackgroundTransparency = 0.24
		title.Position = UDim2.fromOffset(8, 6)
		title.Size = UDim2.new(1, -16, 0, 14)
		title.TextSize = 12
		subtitle.Position = UDim2.fromOffset(8, 18)
		subtitle.Size = UDim2.new(1, -16, 0, 10)
		subtitle.TextSize = 8
		stats.Visible = false
		if touchLockButton and touchModeButton then
			local touchButtonX = math.min(viewportWidth - inset - 54, inset + resourceWidth + 6)
			touchLockButton.Size = UDim2.fromOffset(54, 20)
			touchLockButton.Position = UDim2.fromOffset(touchButtonX, topOffset + 4)
			touchLockButton.TextSize = 9
			touchLockButton.BackgroundTransparency = 0.14
			touchModeButton.Size = UDim2.fromOffset(54, 20)
			touchModeButton.Position = UDim2.fromOffset(touchButtonX, topOffset + 28)
			touchModeButton.TextSize = 9
			touchModeButton.BackgroundTransparency = 0.04
		end

		local barTrackX = 28
		local barTrackWidth = math.max(66, resourceWidth - 64)
		local barValueWidth = 28
		local barLayout = {
			HP = 30,
			Mana = 42,
			Stamina = 54,
		}
		for barName, y in pairs(barLayout) do
			local bar = bars[barName]
			bar.Label.Position = UDim2.fromOffset(8, y)
			bar.Label.Size = UDim2.fromOffset(18, 10)
			bar.Label.TextSize = 7
			bar.Track.Position = UDim2.fromOffset(barTrackX, y + 1)
			bar.Track.Size = UDim2.fromOffset(barTrackWidth, 7)
			bar.Value.AnchorPoint = Vector2.new(1, 0)
			bar.Value.Position = UDim2.new(1, -6, 0, y - 4)
			bar.Value.Size = UDim2.fromOffset(barValueWidth, 16)
			bar.Value.TextSize = 7
		end

		damageCounterPanel.Position = UDim2.new(0.5, 0, 0, topOffset + resourceHeight + 6)
		damageCounterPanel.Size = UDim2.fromOffset(math.clamp(math.floor(viewportWidth * 0.46), 156, 208), 56)
		karmicDamageLabel.TextSize = 11
		damageCounterLabel.TextSize = 22
		damageCounterCaption.TextSize = 9
		combatCuePanel.Position = UDim2.new(0.5, 0, 0, topOffset + resourceHeight + 64)
		combatCuePanel.Size = UDim2.fromOffset(math.clamp(math.floor(viewportWidth * 0.42), 150, 196), 28)
		combatCueLabel.TextSize = 13

		local opponentWidth = math.clamp(math.floor(viewportWidth * 0.22), 112, 128)
		local opponentTrackWidth = math.max(42, opponentWidth - 68)
		opponentPanel.Position = UDim2.new(0, inset, 0.57, 0)
		opponentPanel.Size = UDim2.fromOffset(opponentWidth, 58)
		opponentPanel.BackgroundTransparency = 0.24
		opponentTitle.Position = UDim2.fromOffset(8, 6)
		opponentTitle.Size = UDim2.new(1, -16, 0, 12)
		opponentTitle.TextSize = 9
		local opponentMobileLayout = {
			HP = 18,
			Mana = 28,
		}
		for barName, y in pairs(opponentMobileLayout) do
			local bar = opponentBars[barName]
			bar.Label.Position = UDim2.fromOffset(8, y)
			bar.Label.Size = UDim2.fromOffset(18, 10)
			bar.Label.TextSize = 7
			bar.Track.Position = UDim2.fromOffset(28, y + 1)
			bar.Track.Size = UDim2.fromOffset(opponentTrackWidth, 7)
			bar.Value.Position = UDim2.new(1, -6, 0, y - 4)
			bar.Value.Size = UDim2.fromOffset(24, 12)
			bar.Value.TextSize = 7
		end
		opponentMarksLabel.Position = UDim2.fromOffset(8, 39)
		opponentMarksLabel.Size = UDim2.new(1, -16, 0, 10)
		opponentMarksLabel.TextSize = 7

		local touchSpacing = 5
		local touchCellSize = 44
		local abilityPanelWidth = math.min(
			math.clamp(viewportWidth - (inset * 2), 200, 320),
			math.max(0, (activeAbilityCount * touchCellSize) + (math.max(0, activeAbilityCount - 1) * touchSpacing))
		)
		if abilityPanelWidth <= 0 then
			abilityPanelWidth = 200
		end
		local abilityPanelHeight = 44
		abilityPanel.AnchorPoint = Vector2.new(0.5, 1)
		abilityPanel.Position = UDim2.new(0.5, 0, 1, -(inset + 26))
		abilityPanel.Size = UDim2.fromOffset(abilityPanelWidth, abilityPanelHeight)
		abilityPanel.BackgroundTransparency = 1
		layoutAbilitySlots(abilityPanelWidth, abilityPanelHeight, true)

		local actionBottomOffset = abilityPanelHeight + inset + 36
		if mobileDashButton and mobileBlockButton then
			mobileDashButton.Size = UDim2.fromOffset(78, 34)
			mobileDashButton.Position = UDim2.new(1, -(inset + 14), 1, -actionBottomOffset - 38)
			mobileDashButton.TextSize = 12
			mobileBlockButton.Size = UDim2.fromOffset(118, 36)
			mobileBlockButton.Position = UDim2.new(1, -(inset + 14), 1, -actionBottomOffset)
			mobileBlockButton.TextSize = 13
		end

		if telePanel then
			local teleBottomOffset = actionBottomOffset + 76
			telePanel.Position = UDim2.new(1, -(inset + 14), 1, -teleBottomOffset)
			telePanel.Size = UDim2.fromOffset(150, 114)
		end

		if duelPromptPanel then
			duelPromptPanel.Size = UDim2.fromOffset(math.clamp(viewportWidth - (inset * 2), 224, 280), 108)
			duelPromptPanel.Position = UDim2.new(0.5, 0, 0, safeTopInset)
		end
	else
		resourcesPanel.AnchorPoint = Vector2.new(0, 1)
		resourcesPanel.Position = UDim2.new(0, 18, 1, -116)
		resourcesPanel.Size = UDim2.new(0, 370, 0, 134)
		resourcesPanel.BackgroundTransparency = 0
		title.TextSize = 22
		subtitle.TextSize = 13
		stats.Visible = true
		stats.TextSize = 12
		local desktopBarLayout = {
			HP = 78,
			Mana = 96,
			Stamina = 114,
		}
		for barName, y in pairs(desktopBarLayout) do
			local bar = bars[barName]
			bar.Label.Position = UDim2.new(0, 16, 0, y)
			bar.Label.Size = UDim2.new(0, 70, 0, 14)
			bar.Label.TextSize = 12
			bar.Track.Position = UDim2.new(0, 92, 0, y + 1)
			bar.Track.Size = UDim2.new(0, 208, 0, 12)
			bar.Value.AnchorPoint = Vector2.new(0, 0)
			bar.Value.Position = UDim2.new(0, 308, 0, y - 2)
			bar.Value.Size = UDim2.new(0, 50, 0, 18)
			bar.Value.TextSize = 12
		end

		damageCounterPanel.Position = UDim2.fromScale(0.5, 0.1)
		damageCounterPanel.Size = UDim2.fromOffset(260, 86)
		karmicDamageLabel.TextSize = 16
		damageCounterLabel.TextSize = 34
		damageCounterCaption.TextSize = 12
		combatCuePanel.Position = UDim2.fromScale(0.5, 0.2)
		combatCuePanel.Size = UDim2.fromOffset(240, 34)
		combatCueLabel.TextSize = 18

		local opponentWidth = 188
		local opponentTrackWidth = 98
		opponentPanel.Position = UDim2.new(0, 18, 0.5, 0)
		opponentPanel.Size = UDim2.fromOffset(opponentWidth, 88)
		opponentTitle.Position = UDim2.fromOffset(12, 8)
		opponentTitle.Size = UDim2.new(1, -24, 0, 16)
		opponentTitle.TextSize = 14
		local opponentDesktopLayout = {
			HP = 28,
			Mana = 46,
		}
		for barName, y in pairs(opponentDesktopLayout) do
			local bar = opponentBars[barName]
			bar.Label.Position = UDim2.fromOffset(12, y)
			bar.Label.Size = UDim2.fromOffset(34, 12)
			bar.Label.TextSize = 10
			bar.Track.Position = UDim2.fromOffset(46, y + 1)
			bar.Track.Size = UDim2.fromOffset(opponentTrackWidth, 8)
			bar.Value.Position = UDim2.new(1, -10, 0, y - 3)
			bar.Value.Size = UDim2.fromOffset(36, 14)
			bar.Value.TextSize = 10
		end
		opponentMarksLabel.Position = UDim2.fromOffset(12, 64)
		opponentMarksLabel.Size = UDim2.new(1, -24, 0, 14)
		opponentMarksLabel.TextSize = 10

		local desktopSpacing = 12
		local desktopCellSize = 60
		local abilityPanelWidth = math.max(0, (activeAbilityCount * desktopCellSize) + (math.max(0, activeAbilityCount - 1) * desktopSpacing))
		if abilityPanelWidth <= 0 then
			abilityPanelWidth = 60
		end
		local abilityPanelHeight = 60
		abilityPanel.AnchorPoint = Vector2.new(0.5, 1)
		abilityPanel.Position = UDim2.new(0.5, 0, 1, -18)
		abilityPanel.Size = UDim2.fromOffset(abilityPanelWidth, abilityPanelHeight)
		abilityPanel.BackgroundTransparency = 1
		layoutAbilitySlots(abilityPanelWidth, abilityPanelHeight, false)
	end
end

local function updateSelectorState()
	local kit = getCurrentKit()
	modeButton.Visible = kit ~= nil and kit.Modes ~= nil
	modeButton.Text = string.format("Switch Mode%s", kit and kit.Modes and (" [" .. (getMode() or "") .. "]") or "")
	local rating = profileStats.RankedRating or Constants.RANKED_START_RATING
	local rankedAvailableHere = RunService:IsStudio() or isRankedQueuePlace()
	rankedButton.Visible = rankedAvailableHere
	rankedButton.Active = rankedAvailableHere
	rankedButton.Text = rankedQueued and "Leave Ranked Queue" or "Join Ranked Queue"
	rankedButton.BackgroundColor3 = rankedQueued and theme.red or theme.gold
	rankedButton.TextColor3 = rankedQueued and theme.white or theme.bg
	if rankedAvailableHere then
		rankedStatus.Text = string.format("%s | %d | W %d | L %d%s", Constants.GetRankTierName(rating), rating, profileStats.RankedWins or 0, profileStats.RankedLosses or 0, rankedQueued and " | Queued" or "")
	else
		rankedStatus.Text = string.format("%s | %d | W %d | L %d | Use ranked server", Constants.GetRankTierName(rating), rating, profileStats.RankedWins or 0, profileStats.RankedLosses or 0)
	end
end

local function updateAbilityLabels()
	local kit = getCurrentKit()
	local useMagnusStyle = isMagnusKit(kit)
	local activeKeyMap = {}
	for _, key in ipairs(getActiveAbilityKeys()) do
		activeKeyMap[key] = true
	end

	for _, slotInfo in ipairs(slotOrder) do
		local key = slotInfo[1]
		local slot = abilitySlots[key]
		local isActiveSlot = activeKeyMap[key] == true
		slot.Cell.Visible = isActiveSlot
		slot.Name.Visible = false
		slot.DiamondShadow.Visible = not useMagnusStyle
		slot.Diamond.Visible = not useMagnusStyle
		slot.DiamondStroke.Enabled = not useMagnusStyle
		slot.CircleStroke.Enabled = not useMagnusStyle
		if useMagnusStyle then
			slot.Circle.Position = MAGNUS_LABEL_POSITION
			slot.Circle.Size = MAGNUS_SHIELD_SIZE
			slot.Circle.BackgroundColor3 = Color3.fromRGB(10, 10, 14)
			slot.Circle.BackgroundTransparency = 1
			slot.Key.Position = MAGNUS_TEXT_POSITION
			slot.Key.Size = MAGNUS_TEXT_SIZE
			slot.CooldownLabel.Position = MAGNUS_TEXT_POSITION
			slot.CooldownLabel.Size = MAGNUS_TEXT_SIZE
		else
			slot.Circle.Position = UDim2.fromScale(0.5, 0.5)
			slot.Circle.Size = UDim2.fromScale(0.58, 0.58)
			slot.DiamondShadow.BackgroundColor3 = Color3.fromRGB(8, 10, 14)
			slot.DiamondShadow.BackgroundTransparency = 0
			slot.Diamond.BackgroundColor3 = theme.panelAlt
			slot.Diamond.BackgroundTransparency = 0
			slot.DiamondStroke.Color = theme.gold
			slot.DiamondStroke.Transparency = 0.28
			slot.Circle.BackgroundColor3 = theme.panel
			slot.Circle.BackgroundTransparency = 0
			slot.CircleStroke.Color = theme.gold
			slot.CircleStroke.Transparency = 0.15
			slot.Key.Position = UDim2.fromScale(0.5, 0.5)
			slot.Key.Size = UDim2.fromScale(1, 1)
			slot.CooldownLabel.Position = UDim2.fromScale(0.5, 0.5)
			slot.CooldownLabel.Size = UDim2.fromScale(1, 1)
		end
		slot.MagnusShieldBase.Visible = isActiveSlot and useMagnusStyle
		slot.MagnusShieldBase.ImageTransparency = useMagnusStyle and 0 or 1
		slot.MagnusShieldCooldown.Visible = useMagnusStyle and slot.MagnusCooldownFade < 0.99
		slot.Key.TextColor3 = useMagnusStyle and theme.white or theme.gold
		slot.CooldownLabel.TextColor3 = useMagnusStyle and theme.bg or theme.text
	end
end

local function updateResourceBars()
	local character = getCharacter()
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local kit = getCurrentKit()
	if not character or not humanoid or not kit then
		title.Text = "Character"
		subtitle.Text = "Mode"
		stats.Text = ""
		return
	end

	title.Text = kit.DisplayName
	subtitle.Text = isTouchDevice and (getMode() or (kit.Modes and kit.Modes[1]) or "Base") or (kit.Modes and ("Mode: " .. (getMode() or kit.Modes[1])) or "Mode: Base")
	stats.Text = string.format("ATK %s   DEF %s", tostring(kit.Stats.Attack or 0), tostring(kit.Stats.Defense or 0))
	local useMagnusStyle = isMagnusKit(kit)
	local useMagnusBarImage = useMagnusStyle and magnusAssetImages.BlackBar ~= nil and magnusAssetImages.BlackBar ~= ""
	magnusStatsBackdrop.Visible = useMagnusBarImage
	magnusStatsBackdrop.ImageTransparency = useMagnusBarImage and 0 or 1
	magnusStatsBackdrop.ScaleType = Enum.ScaleType.Stretch
	magnusStatsBackdrop.ImageRectOffset = useMagnusBarImage and MAGNUS_STATS_BAR_RECT_OFFSET or Vector2.new(0, 0)
	magnusStatsBackdrop.ImageRectSize = useMagnusBarImage and MAGNUS_STATS_BAR_RECT_SIZE or Vector2.new(0, 0)
	magnusStatsBackdrop.Size = useMagnusBarImage
		and (isTouchDevice and MAGNUS_STATS_BAR_SIZE_TOUCH or MAGNUS_STATS_BAR_SIZE_DESKTOP)
		or UDim2.fromScale(1, 1)
	resourcesPanel.BackgroundColor3 = useMagnusStyle and Color3.fromRGB(10, 10, 14) or theme.panel
	resourcesPanel.BackgroundTransparency = useMagnusBarImage and 1 or (useMagnusStyle and 0.08 or (isTouchDevice and 0.24 or 0))
	resourcesPanelCorner.CornerRadius = useMagnusBarImage and UDim.new(0, 0) or (useMagnusStyle and UDim.new(0, 10) or UDim.new(0, 16))
	resourcesPanelStroke.Transparency = useMagnusBarImage and 1 or (useMagnusStyle and 0.18 or 1)
	title.TextColor3 = useMagnusStyle and theme.white or theme.text
	subtitle.TextColor3 = useMagnusStyle and Color3.fromRGB(198, 198, 198) or theme.subtle
	stats.TextColor3 = useMagnusStyle and Color3.fromRGB(224, 224, 224) or theme.subtle

	local isSans = kit.DisplayName == "Sans"
	local hpCurrent = isSans and math.floor(character:GetAttribute("Dodge") or humanoid.Health) or math.floor(humanoid.Health)
	local hpMax = isSans and math.max(1, math.floor(character:GetAttribute("MaxDodge") or humanoid.MaxHealth)) or math.max(1, humanoid.MaxHealth)
	bars.HP.Label.Text = isTouchDevice and (isSans and "DG" or "HP") or (isSans and "Dodge" or "HP")
	bars.HP.Fill.Size = UDim2.new(math.clamp(hpCurrent / hpMax, 0, 1), 0, 1, 0)
	bars.HP.Value.Text = string.format("%d/%d", hpCurrent, hpMax)

	local manaMax = kit.Stats.Mana or 0
	local manaCurrent = character:GetAttribute("Mana") or 0
	bars.Mana.Label.Text = isTouchDevice and "MP" or "Mana"
	bars.Mana.Track.Visible = manaMax > 0
	bars.Mana.Fill.Visible = manaMax > 0
	bars.Mana.Label.Visible = manaMax > 0
	bars.Mana.Value.Visible = manaMax > 0
	if manaMax > 0 then
		bars.Mana.Fill.Size = UDim2.new(math.clamp(manaCurrent / manaMax, 0, 1), 0, 1, 0)
		bars.Mana.Value.Text = string.format("%d/%d", manaCurrent, manaMax)
	end

	local staminaMax = kit.Stats.Stamina or 0
	local staminaCurrent = character:GetAttribute("Stamina") or 0
	bars.Stamina.Label.Text = isTouchDevice and "ST" or "Stamina"
	bars.Stamina.Track.Visible = staminaMax > 0
	bars.Stamina.Fill.Visible = staminaMax > 0
	bars.Stamina.Label.Visible = staminaMax > 0
	bars.Stamina.Value.Visible = staminaMax > 0
	if staminaMax > 0 then
		bars.Stamina.Fill.Size = UDim2.new(math.clamp(staminaCurrent / staminaMax, 0, 1), 0, 1, 0)
		bars.Stamina.Value.Text = string.format("%d/%d", staminaCurrent, staminaMax)
	end
end

local function updateOpponentPanel()
	local lockOn = getLockOn()
	local target = lockOn and lockOn.GetLockedModel and lockOn.GetLockedModel()
	local humanoid = target and target:FindFirstChildOfClass("Humanoid")
	if not target or not humanoid or humanoid.Health <= 0 then
		opponentPanel.Visible = false
		return
	end

	local targetPlayer = Players:GetPlayerFromCharacter(target)
	local targetKit = getKitForCharacter(target)
	local targetName = targetPlayer and targetPlayer.DisplayName or target.Name
	opponentTitle.Text = targetName

	local isSans = targetKit and targetKit.DisplayName == "Sans"
	local hpCurrent = isSans and math.floor(target:GetAttribute("Dodge") or humanoid.Health) or math.floor(humanoid.Health)
	local hpMax = isSans and math.max(1, math.floor(target:GetAttribute("MaxDodge") or humanoid.MaxHealth)) or math.max(1, math.floor(humanoid.MaxHealth))
	local hpRatio = math.clamp(hpCurrent / hpMax, 0, 1)
	local hpColor = getHealthDisplayColor(hpRatio)
	opponentBars.HP.Label.Text = isTouchDevice and (isSans and "DG" or "HP") or (isSans and "Dodge" or "HP")
	opponentBars.HP.Fill.Size = UDim2.new(hpRatio, 0, 1, 0)
	opponentBars.HP.Fill.BackgroundColor3 = hpColor
	opponentBars.HP.Value.Text = string.format("%d/%d", hpCurrent, hpMax)
	opponentBars.HP.Value.TextColor3 = hpColor

	local manaMax = targetKit and targetKit.Stats and targetKit.Stats.Mana or 0
	local manaCurrent = tonumber(target:GetAttribute("Mana")) or 0
	local showMana = manaMax > 0
	opponentBars.Mana.Label.Text = isTouchDevice and "MP" or "Mana"
	opponentBars.Mana.Label.Visible = showMana
	opponentBars.Mana.Track.Visible = showMana
	opponentBars.Mana.Fill.Visible = showMana
	opponentBars.Mana.Value.Visible = showMana
	if showMana then
		opponentBars.Mana.Fill.Size = UDim2.new(math.clamp(manaCurrent / manaMax, 0, 1), 0, 1, 0)
		opponentBars.Mana.Value.Text = string.format("%d/%d", manaCurrent, manaMax)
	end

	local frameMarks = tonumber(target:GetAttribute("NaoyaFrameMarks")) or 0
	local isFrozen = target:GetAttribute("NaoyaFrozen") == true
	local samuraiBleedMarks = tonumber(target:GetAttribute("SamuraiBleedMarks")) or 0
	local isSamuraiBleeding = target:GetAttribute("SamuraiBleeding") == true
	local statusText, statusColor = getOpponentStatusText(target, frameMarks, isFrozen, samuraiBleedMarks, isSamuraiBleeding)
	opponentMarksLabel.Visible = statusText ~= ""
	opponentMarksLabel.Text = statusText
	opponentMarksLabel.TextColor3 = statusColor

	opponentPanel.Visible = true
end

local function getCooldownKey(slot)
	local kitId = getKitId() or "Unknown"
	local mode = getMode() or "Base"
	return string.format("%s:%s:%s", kitId, mode, slot)
end

local function updateCooldownVisuals()
	local timeNow = os.clock()
	local kit = getCurrentKit()
	local useMagnusStyle = isMagnusKit(kit)
	for key, slot in pairs(abilitySlots) do
		if not slot.Cell.Visible then
			slot.CooldownShade.Visible = false
			slot.CooldownLabel.Visible = false
			slot.ReadyFlash.Visible = false
			slot.ReadyFlash.BackgroundTransparency = 1
			slot.MagnusShieldCooldown.Visible = false
			slot.MagnusShieldCooldown.ImageTransparency = 1
			slot.MagnusCooldownFade = 1
			slot.Key.TextTransparency = 0
			slot.WasCoolingDown = false
			slot.ReadyFlashAlpha = 1
			continue
		end

		local readyAt = cooldowns[getCooldownKey(key)] or 0
		local remaining = readyAt - timeNow
		local active = remaining > 0
		if slot.WasCoolingDown and not active then
			slot.ReadyFlashAlpha = 0
		end
		slot.CooldownShade.Visible = active and not useMagnusStyle
		slot.CooldownLabel.Visible = active
		if active then
			slot.CooldownLabel.Text = string.format("%.1f", remaining)
		end
		if slot.ReadyFlashAlpha < 1 then
			slot.ReadyFlashAlpha = math.min(1, slot.ReadyFlashAlpha + 0.13)
			slot.ReadyFlash.Visible = true
			slot.ReadyFlash.BackgroundTransparency = 0.45 + (slot.ReadyFlashAlpha * 0.55)
		else
			slot.ReadyFlash.Visible = false
			slot.ReadyFlash.BackgroundTransparency = 1
		end
		if useMagnusStyle then
			if active then
				slot.MagnusCooldownFade = math.max(0.02, slot.MagnusCooldownFade - 0.18)
			else
				slot.MagnusCooldownFade = math.min(1, slot.MagnusCooldownFade + 0.12)
			end
			slot.MagnusShieldCooldown.ImageTransparency = slot.MagnusCooldownFade
			slot.MagnusShieldCooldown.Visible = slot.MagnusCooldownFade < 0.99
			slot.CooldownShade.Visible = false
			slot.CooldownShade.BackgroundColor3 = Color3.new(0, 0, 0)
			slot.CooldownShade.BackgroundTransparency = 1
			slot.Key.TextTransparency = active and 1 or 0
		else
			slot.MagnusShieldCooldown.Visible = false
			slot.MagnusShieldCooldown.ImageTransparency = 1
			slot.MagnusCooldownFade = 1
			slot.CooldownShade.BackgroundColor3 = Color3.new(0, 0, 0)
			slot.CooldownShade.BackgroundTransparency = 0.28
			slot.Key.TextTransparency = 0
		end
		slot.WasCoolingDown = active
	end
end

local function refreshAll()
	updateSelectorState()
	updateAbilityLabels()
	updateResourceBars()
	updateOpponentPanel()
	updateNaoyaFrameIndicators()
	updateSamuraiBleedIndicators()
	updateNaoyaFrozenVisuals()
	updateTouchPanels()
	applyResponsiveLayout()
end

local function resetDamageCounter()
	damageCounterState.Direct = 0
	damageCounterState.Karmic = 0
	damageCounterState.ExpiresAt = 0
end

local function updateDamageCounterVisuals()
	local remaining = damageCounterState.ExpiresAt - os.clock()
	local active = remaining > 0 and (damageCounterState.Direct > 0 or damageCounterState.Karmic > 0)
	damageCounterPanel.Visible = active
	if not active then
		damageCounterLabel.Text = "0"
		karmicDamageLabel.Text = ""
		return
	end

	local fadeAlpha = math.clamp(remaining / DAMAGE_COUNTER_LIFETIME, 0, 1)
	damageCounterLabel.Text = tostring(damageCounterState.Direct)
	karmicDamageLabel.Text = damageCounterState.Karmic > 0 and string.format("KR +%d", damageCounterState.Karmic) or ""
	damageCounterLabel.TextTransparency = 1 - fadeAlpha
	damageCounterLabel.TextStrokeTransparency = 0.2 + ((1 - fadeAlpha) * 0.6)
	karmicDamageLabel.TextTransparency = 1 - fadeAlpha
	karmicDamageLabel.TextStrokeTransparency = 0.35 + ((1 - fadeAlpha) * 0.5)
	damageCounterCaption.TextTransparency = 0.15 + ((1 - fadeAlpha) * 0.7)
end

local function registerDamage(amount, isKarmic)
	if type(amount) ~= "number" or amount <= 0 then
		return
	end

	if damageCounterState.ExpiresAt <= os.clock() then
		resetDamageCounter()
	end

	if isKarmic then
		damageCounterState.Karmic += amount
	else
		damageCounterState.Direct += amount
	end

	damageCounterState.ExpiresAt = os.clock() + DAMAGE_COUNTER_LIFETIME
	updateDamageCounterVisuals()
end

local function showCombatCue(text, color)
	if type(text) ~= "string" or text == "" then
		return
	end

	combatCueState.Text = text
	combatCueState.Color = color or theme.text
	combatCueState.ExpiresAt = os.clock() + COMBAT_CUE_LIFETIME
end

local function updateCombatCueVisuals()
	local remaining = combatCueState.ExpiresAt - os.clock()
	local active = remaining > 0 and combatCueState.Text ~= ""
	combatCuePanel.Visible = active
	if not active then
		combatCueLabel.Text = ""
		return
	end

	local fadeAlpha = math.clamp(remaining / COMBAT_CUE_LIFETIME, 0, 1)
	combatCueLabel.Text = combatCueState.Text
	combatCueLabel.TextColor3 = combatCueState.Color
	combatCueLabel.TextTransparency = 1 - fadeAlpha
	combatCueLabel.TextStrokeTransparency = 0.35 + ((1 - fadeAlpha) * 0.45)
	combatCuePanel.BackgroundTransparency = 0.34 + ((1 - fadeAlpha) * 0.5)
end

local dodgeDebugNonce = 0
local function showDodgeDebug(text)
	if not Constants.SANS_DODGE_DEBUG or type(text) ~= "string" or text == "" then
		return
	end

	dodgeDebugNonce += 1
	local localNonce = dodgeDebugNonce
	dodgeDebugLabel.Text = text
	dodgeDebugLabel.Visible = true
	task.delay(2.25, function()
		if dodgeDebugNonce == localNonce then
			dodgeDebugLabel.Visible = false
		end
	end)
end

_G.JudgementDividedDodgeDebug = showDodgeDebug

modeButton.MouseButton1Click:Connect(function()
	combatRequest:FireServer({
		Action = "SwitchMode",
		Direction = "Next",
	})
end)

rankedButton.MouseButton1Click:Connect(function()
	combatRequest:FireServer({
		Action = "ToggleRankedQueue",
	})
end)

combatState.OnClientEvent:Connect(function(payload)
	if typeof(payload) ~= "table" then
		return
	end

	if payload.Type == "Ability" and payload.Player == player.UserId then
		cooldowns[payload.CooldownKey or getCooldownKey(payload.Slot)] = os.clock() + payload.Cooldown
	elseif payload.Type == "CooldownSet" and payload.Player == player.UserId then
		cooldowns[payload.CooldownKey or getCooldownKey(payload.Slot)] = os.clock() + payload.Cooldown
	elseif payload.Type == "HitConfirm" and payload.Attacker == player.UserId then
		registerDamage(payload.Damage, payload.IsKarmic == true)
	elseif payload.Type == "PerfectBlock" then
		if payload.Player == player.UserId then
			showCombatCue("PERFECT BLOCK", Color3.fromRGB(170, 215, 255))
		elseif payload.Target == player.UserId then
			showCombatCue("PARRIED", Color3.fromRGB(255, 140, 140))
		end
	elseif payload.Type == "BlockBreak" then
		if payload.Attacker == player.UserId then
			showCombatCue("BLOCK BREAK", theme.gold)
		elseif payload.Target == player.UserId then
			showCombatCue("GUARD BROKEN", Color3.fromRGB(255, 132, 132))
		end
	elseif payload.Type == "CounterTriggered" then
		if payload.Player == player.UserId then
			showCombatCue("COUNTER!", Color3.fromRGB(255, 230, 150))
		elseif payload.Target == player.UserId then
			showCombatCue("COUNTERED", Color3.fromRGB(255, 132, 132))
		end
	elseif payload.Type == "DodgeDebug" then
		showDodgeDebug(payload.Text)
	elseif payload.Type == "Profile" then
		profileStats.RankedRating = payload.RankedRating or Constants.RANKED_START_RATING
		profileStats.RankedWins = payload.RankedWins or 0
		profileStats.RankedLosses = payload.RankedLosses or 0
		task.defer(refreshAll)
	elseif payload.Type == "RankedQueueStatus" then
		rankedQueued = payload.InQueue == true
		task.defer(refreshAll)
	elseif payload.Type == "KitChanged" and payload.KitId then
		table.clear(cooldowns)
		task.defer(refreshAll)
	elseif payload.Type == "ModeChanged" then
		task.defer(refreshAll)
	elseif payload.Type == "DuelRequested" and duelPromptPanel and duelPromptLabel then
		duelPromptLabel.Text = string.format("%s challenged you to a duel.", payload.From or "A player")
		duelPromptPanel.Visible = true
	elseif (payload.Type == "DuelCountdown" or payload.Type == "DuelEnded") and duelPromptPanel then
		duelPromptPanel.Visible = false
	end
end)

local function hookCharacter(character)
	resetDamageCounter()
	updateDamageCounterVisuals()
	for _, attributeName in ipairs({"KitId", "Mode", "Mana", "Stamina", "Blocking", "ActiveBlasters", "Dodge", "MaxDodge"}) do
		character:GetAttributeChangedSignal(attributeName):Connect(refreshAll)
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid") or character:WaitForChild("Humanoid")
	humanoid.HealthChanged:Connect(updateResourceBars)
	refreshAll()
end

player.CharacterAdded:Connect(hookCharacter)
if player.Character then
	hookCharacter(player.Character)
end

local function bindViewport(camera)
	if viewportConnection then
		viewportConnection:Disconnect()
		viewportConnection = nil
	end

	if camera then
		viewportConnection = camera:GetPropertyChangedSignal("ViewportSize"):Connect(applyResponsiveLayout)
	end
end

bindViewport(Workspace.CurrentCamera)
Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
	bindViewport(Workspace.CurrentCamera)
	applyResponsiveLayout()
end)

RunService.RenderStepped:Connect(function()
	updateResourceBars()
	updateOpponentPanel()
	updateNaoyaFrameIndicators()
	updateSamuraiBleedIndicators()
	updateNaoyaFrozenVisuals()
	updateCooldownVisuals()
	updateCombatCueVisuals()
	updateDamageCounterVisuals()
end)

refreshAll()

playerGui:GetAttributeChangedSignal(Constants.MENU_ATTRIBUTE):Connect(function()
	gui.Enabled = not playerGui:GetAttribute(Constants.MENU_ATTRIBUTE)
end)

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if not isAdmin() or playerGui:GetAttribute(Constants.MENU_ATTRIBUTE) then
		return
	end

	if input.KeyCode == Enum.KeyCode.Escape and adminPanel.Visible then
		closeAdminPanel()
		return
	end

	if input.KeyCode ~= Constants.ADMIN_PANEL_KEY then
		return
	end

	if adminCommandBar:IsFocused() then
		return
	end

	if gameProcessed then
		return
	end

	if adminPanel.Visible then
		closeAdminPanel()
	else
		openAdminPanel()
	end
end)
