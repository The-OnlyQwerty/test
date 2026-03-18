local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local CharacterKits = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("CharacterKits"))
local Constants = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Constants"))

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local combatRequest = remotes:WaitForChild("CombatRequest")
local combatState = remotes:WaitForChild("CombatState")

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
}

local function isAdmin()
	for _, userId in ipairs(Constants.ADMIN_USER_IDS) do
		if userId == player.UserId then
			return true
		end
	end
	return false
end

local function create(instanceType, props)
	local instance = Instance.new(instanceType)
	for key, value in pairs(props) do
		instance[key] = value
	end
	return instance
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

local resourcesPanel = create("Frame", {
	Name = "Resources",
	AnchorPoint = Vector2.new(0, 1),
	Position = UDim2.new(0, 18, 1, -116),
	Size = UDim2.new(0, 370, 0, 134),
	BackgroundColor3 = theme.panel,
	BorderSizePixel = 0,
	Parent = root,
})
create("UICorner", {CornerRadius = UDim.new(0, 16), Parent = resourcesPanel})

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

local selectorPanel = create("Frame", {
	Name = "Selector",
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, -18, 0, 18),
	Size = UDim2.new(0, 236, 0, 156),
	BackgroundColor3 = theme.panel,
	BorderSizePixel = 0,
	Parent = root,
})
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
create("UICorner", {CornerRadius = UDim.new(0, 12), Parent = modeButton})

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

local adminPanel = create("Frame", {
	Name = "AdminPanel",
	Visible = false,
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.fromScale(0.5, 0.02),
	Size = UDim2.fromOffset(520, 154),
	BackgroundColor3 = theme.panel,
	BorderSizePixel = 0,
	Parent = root,
})
create("UICorner", {CornerRadius = UDim.new(0, 16), Parent = adminPanel})

create("TextLabel", {
	BackgroundTransparency = 1,
	Position = UDim2.new(0, 16, 0, 10),
	Size = UDim2.new(1, -32, 0, 24),
	Font = Enum.Font.GothamBold,
	Text = "Admin Commands",
	TextColor3 = theme.text,
	TextSize = 20,
	TextXAlignment = Enum.TextXAlignment.Left,
	Parent = adminPanel,
})

create("TextLabel", {
	BackgroundTransparency = 1,
	Position = UDim2.new(0, 16, 0, 38),
	Size = UDim2.new(1, -32, 1, -48),
	Font = Enum.Font.Gotham,
	Text = table.concat({
		"/setkills <player> <amount>",
		"/setdeaths <player> <amount>",
		"/setrating <player> <amount>",
		"/buff <player> Attack <amount>",
		"/buff <player> Defense <amount>",
		"/buff <player> Health <amount>",
		"/buff <player> Mana <amount>",
		"/buff <player> Stamina <amount>",
	}, "\n"),
	TextColor3 = theme.subtle,
	TextSize = 14,
	TextWrapped = true,
	TextXAlignment = Enum.TextXAlignment.Left,
	TextYAlignment = Enum.TextYAlignment.Top,
	Parent = adminPanel,
})

local abilityPanel = create("Frame", {
	Name = "Abilities",
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, -18),
	Size = UDim2.new(0, 640, 0, 90),
	BackgroundColor3 = theme.panel,
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
		BackgroundColor3 = theme.panelAlt,
		BorderSizePixel = 0,
		Parent = abilityPanel,
	})
	create("UICorner", {CornerRadius = UDim.new(0, 14), Parent = cell})

	local keyLabel = create("TextLabel", {
		BackgroundTransparency = 1,
		Position = UDim2.new(0, 10, 0, 8),
		Size = UDim2.new(0, 20, 0, 18),
		Font = Enum.Font.GothamBold,
		Text = displayKey,
		TextColor3 = theme.gold,
		TextSize = 16,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = cell,
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
		Parent = cell,
	})

	local cooldownShade = create("Frame", {
		Visible = false,
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.35,
		Size = UDim2.fromScale(1, 1),
		BorderSizePixel = 0,
		Parent = cell,
	})
	create("UICorner", {CornerRadius = UDim.new(0, 14), Parent = cooldownShade})

	local cooldownLabel = create("TextLabel", {
		Visible = false,
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Font = Enum.Font.GothamBold,
		Text = "",
		TextColor3 = theme.text,
		TextSize = 20,
		Parent = cell,
	})

	abilitySlots[key] = {
		Cell = cell,
		Name = nameLabel,
		CooldownShade = cooldownShade,
		CooldownLabel = cooldownLabel,
	}
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

local function updateSelectorState()
	local kit = getCurrentKit()
	modeButton.Visible = kit ~= nil and kit.Modes ~= nil
	modeButton.Text = string.format("Switch Mode%s", kit and kit.Modes and (" [" .. (getMode() or "") .. "]") or "")
	rankedButton.Text = rankedQueued and "Leave Ranked Queue" or "Join Ranked Queue"
	rankedButton.BackgroundColor3 = rankedQueued and theme.red or theme.gold
	rankedButton.TextColor3 = rankedQueued and theme.white or theme.bg
	rankedStatus.Text = string.format("Ranked %d | W %d | L %d%s", profileStats.RankedRating or Constants.RANKED_START_RATING, profileStats.RankedWins or 0, profileStats.RankedLosses or 0, rankedQueued and " | Queued" or "")
end

local function updateAbilityLabels()
	local abilities = getCurrentAbilities()
	for _, slotInfo in ipairs(slotOrder) do
		local key = slotInfo[1]
		local ability = abilities[key]
		abilitySlots[key].Name.Text = ability and ability.Name or "-"
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
	subtitle.Text = kit.Modes and ("Mode: " .. (getMode() or kit.Modes[1])) or "Mode: Base"
	stats.Text = string.format("ATK %s   DEF %s", tostring(kit.Stats.Attack or 0), tostring(kit.Stats.Defense or 0))

	local hpCurrent = math.floor(humanoid.Health)
	local hpMax = math.max(1, humanoid.MaxHealth)
	bars.HP.Fill.Size = UDim2.new(math.clamp(hpCurrent / hpMax, 0, 1), 0, 1, 0)
	bars.HP.Value.Text = string.format("%d/%d", hpCurrent, hpMax)

	local manaMax = kit.Stats.Mana or 0
	local manaCurrent = character:GetAttribute("Mana") or 0
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
	bars.Stamina.Track.Visible = staminaMax > 0
	bars.Stamina.Fill.Visible = staminaMax > 0
	bars.Stamina.Label.Visible = staminaMax > 0
	bars.Stamina.Value.Visible = staminaMax > 0
	if staminaMax > 0 then
		bars.Stamina.Fill.Size = UDim2.new(math.clamp(staminaCurrent / staminaMax, 0, 1), 0, 1, 0)
		bars.Stamina.Value.Text = string.format("%d/%d", staminaCurrent, staminaMax)
	end
end

local function getCooldownKey(slot)
	local kitId = getKitId() or "Unknown"
	local mode = getMode() or "Base"
	return string.format("%s:%s:%s", kitId, mode, slot)
end

local function updateCooldownVisuals()
	local timeNow = os.clock()
	for key, slot in pairs(abilitySlots) do
		local readyAt = cooldowns[getCooldownKey(key)] or 0
		local remaining = readyAt - timeNow
		local active = remaining > 0
		slot.CooldownShade.Visible = active
		slot.CooldownLabel.Visible = active
		if active then
			slot.CooldownLabel.Text = string.format("%.1f", remaining)
		end
	end
end

local function refreshAll()
	updateSelectorState()
	updateAbilityLabels()
	updateResourceBars()
end

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
	end
end)

local function hookCharacter(character)
	for _, attributeName in ipairs({"KitId", "Mode", "Mana", "Stamina", "Blocking", "ActiveBlasters"}) do
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

RunService.RenderStepped:Connect(function()
	updateResourceBars()
	updateCooldownVisuals()
end)

refreshAll()

playerGui:GetAttributeChangedSignal(Constants.MENU_ATTRIBUTE):Connect(function()
	gui.Enabled = not playerGui:GetAttribute(Constants.MENU_ATTRIBUTE)
end)

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed or not isAdmin() or playerGui:GetAttribute(Constants.MENU_ATTRIBUTE) then
		return
	end

	if input.KeyCode == Constants.ADMIN_PANEL_KEY then
		adminPanel.Visible = not adminPanel.Visible
	end
end)
