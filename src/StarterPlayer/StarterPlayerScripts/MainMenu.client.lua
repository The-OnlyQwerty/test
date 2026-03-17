local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")
local TeleportService = game:GetService("TeleportService")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Constants = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Constants"))
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

local theme = {
	skyTop = Color3.fromRGB(107, 8, 8),
	skyMid = Color3.fromRGB(175, 67, 11),
	skyBottom = Color3.fromRGB(13, 14, 28),
	panel = Color3.fromRGB(64, 14, 16),
	panelSoft = Color3.fromRGB(96, 28, 20),
	panelDark = Color3.fromRGB(17, 18, 24),
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

local credits = {
	{"The_OnlyQwerty", "Owner"},
	{"Cavespider07", "Animator"},
	{"Friday1234g", "Map Builder"},
}

local currentKills = 0
local selectedSkins = {
	Sans = "Default",
	Magnus = "Default",
}

local function create(instanceType, props)
	local instance = Instance.new(instanceType)
	for key, value in pairs(props) do
		instance[key] = value
	end
	return instance
end

local function notify(text)
	pcall(function()
		StarterGui:SetCore("SendNotification", {
			Title = "Judgement Divided",
			Text = text,
			Duration = 1.5,
		})
	end)
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
	local shell = create("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = position,
		Size = size + UDim2.fromOffset(10, 10),
		BackgroundColor3 = accentColor or theme.ember,
		BackgroundTransparency = 0.5,
		BorderSizePixel = 0,
		Parent = parent,
	})
	create("UICorner", {CornerRadius = UDim.new(0, 18), Parent = shell})

	local button = create("TextButton", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = position,
		Size = size,
		BackgroundColor3 = theme.panelDark,
		BorderColor3 = theme.white,
		BorderSizePixel = 2,
		Font = Enum.Font.Arcade,
		Text = text,
		TextColor3 = theme.white,
		TextSize = 34,
		AutoButtonColor = false,
		Parent = parent,
	})
	create("UICorner", {CornerRadius = UDim.new(0, 16), Parent = button})

	local shine = create("Frame", {
		BackgroundColor3 = theme.white,
		BackgroundTransparency = 0.9,
		BorderSizePixel = 0,
		Position = UDim2.new(0, 8, 0, 8),
		Size = UDim2.new(1, -16, 0, 8),
		Parent = button,
	})
	create("UICorner", {CornerRadius = UDim.new(1, 0), Parent = shine})

	button.MouseEnter:Connect(function()
		TweenService:Create(button, TweenInfo.new(0.12), {
			BackgroundColor3 = theme.panelSoft,
			Size = size + UDim2.fromOffset(8, 8),
		}):Play()
		TweenService:Create(shell, TweenInfo.new(0.12), {
			BackgroundTransparency = 0.2,
		}):Play()
	end)

	button.MouseLeave:Connect(function()
		TweenService:Create(button, TweenInfo.new(0.12), {
			BackgroundColor3 = theme.panelDark,
			Size = size,
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
	Settings = settingsPage,
	Select = selectPage,
}

for _, page in pairs(pages) do
	page.ZIndex = 10
end

local playButton = createPrimaryButton("Play", UDim2.fromScale(0.5, 0.75), UDim2.fromOffset(410, 82), homePage, theme.gold)
local trainingButton = createPrimaryButton("TR", UDim2.fromScale(0.88, 0.12), UDim2.fromOffset(120, 62), homePage, theme.green)
trainingButton.Text = isTrainingPlace() and "Main Game" or "TR"
trainingButton.TextSize = isTrainingPlace() and 18 or 24
local infoButton = createPrimaryButton("?", UDim2.fromScale(0.39, 0.9), UDim2.fromOffset(84, 84), homePage, theme.blue)
local skinsButton = createPrimaryButton("SK", UDim2.fromScale(0.5, 0.9), UDim2.fromOffset(84, 84), homePage, theme.ember)
local settingsButton = createPrimaryButton("SET", UDim2.fromScale(0.61, 0.9), UDim2.fromOffset(84, 84), homePage, theme.red)

local function showPage(name)
	homePage.Visible = name == "Home"
	creditsPage.Visible = name == "Credits"
	skinsPage.Visible = name == "Skins"
	settingsPage.Visible = name == "Settings"
	selectPage.Visible = name == "Select"
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
	local targetPlaceId
	if isTrainingPlace() then
		targetPlaceId = Constants.MAIN_GAME_PLACE_ID
	else
		targetPlaceId = Constants.TRAINING_SERVER_PLACE_IDS[1]
	end

	if not targetPlaceId or targetPlaceId == 0 then
		notify(isTrainingPlace() and "No main game place ID is configured yet." or "No training place ID is configured yet.")
		return
	end

	closeMenuWithFade()
	task.delay(0.4, function()
		TeleportService:Teleport(targetPlaceId, player)
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
	CanvasSize = UDim2.new(0, 0, 0, #credits * 104),
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	ScrollBarThickness = 6,
	ScrollBarImageColor3 = theme.white,
	Parent = creditsPanel,
})

for index, entry in ipairs(credits) do
	local y = (index - 1) * 104
	create("TextLabel", {
		BackgroundTransparency = 1,
		Position = UDim2.new(0, 0, 0, y),
		Size = UDim2.new(1, 0, 0, 42),
		Font = Enum.Font.Arcade,
		Text = entry[1],
		TextColor3 = theme.white,
		TextSize = 24,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = creditsScroll,
	})

	create("TextLabel", {
		BackgroundTransparency = 1,
		Position = UDim2.new(0, 0, 0, y + 42),
		Size = UDim2.new(1, 0, 0, 24),
		Font = Enum.Font.Arcade,
		Text = entry[2],
		TextColor3 = theme.muted,
		TextSize = 16,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = creditsScroll,
	})
end

local backFromCredits = createPrimaryButton("Back", UDim2.fromScale(0.5, 0.94), UDim2.fromOffset(260, 70), creditsPage, theme.red)

local selectPanel = createPanel(selectPage, "Character Select", UDim2.fromOffset(900, 470))

create("TextLabel", {
	BackgroundTransparency = 1,
	Position = UDim2.new(0, 34, 0, 66),
	Size = UDim2.new(1, -68, 0, 26),
	Font = Enum.Font.Arcade,
	Text = "Choose your fighter. More slots are coming later.",
	TextColor3 = theme.muted,
	TextSize = 14,
	TextXAlignment = Enum.TextXAlignment.Left,
	Parent = selectPanel,
})

local slotConfigs = {
	{Name = "Sans", Available = true, Description = "Bones / Telekinesis / Blasters"},
	{Name = "Magnus", Available = true, Description = "Sword brawler"},
	{Name = "Slot 3", Available = false, Description = "Not available yet"},
	{Name = "Slot 4", Available = false, Description = "Not available yet"},
	{Name = "Slot 5", Available = false, Description = "Not available yet"},
}

local slotButtons = {}
for index, slot in ipairs(slotConfigs) do
	local col = (index - 1) % 3
	local row = math.floor((index - 1) / 3)
	local button = create("TextButton", {
		Position = UDim2.new(0, 34 + col * 274, 0, 116 + row * 142),
		Size = UDim2.fromOffset(242, 116),
		BackgroundColor3 = slot.Available and theme.panelSoft or Color3.fromRGB(54, 54, 58),
		BorderSizePixel = 0,
		Text = "",
		AutoButtonColor = false,
		Parent = selectPanel,
	})
	create("UICorner", {CornerRadius = UDim.new(0, 18), Parent = button})
	create("UIStroke", {
		Color = slot.Available and theme.gold or Color3.fromRGB(90, 90, 95),
		Transparency = 0.45,
		Thickness = 2,
		Parent = button,
	})

	create("TextLabel", {
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

	create("TextLabel", {
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
end

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

local categoryPanel = create("Frame", {
	Position = UDim2.new(0, 20, 0, 102),
	Size = UDim2.fromOffset(306, 318),
	BackgroundTransparency = 1,
	Parent = skinsPanel,
})

local categoryButtons = {}
local selectedCategory = "Sans"
for index, category in ipairs({"Sans", "Magnus"}) do
	local button = create("TextButton", {
		Position = UDim2.new(0, 0, 0, (index - 1) * 54),
		Size = UDim2.fromOffset(306, 44),
		BackgroundColor3 = Color3.fromRGB(82, 82, 82),
		BorderSizePixel = 0,
		Font = Enum.Font.Arcade,
		Text = category,
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
	Parent = skinsPanel,
})

local backFromSkins = createPrimaryButton("Back", UDim2.fromScale(0.5, 0.94), UDim2.fromOffset(260, 70), skinsPage, theme.red)

local function isSkinUnlocked(kitId, skin)
	return currentKills >= (skin.UnlockKills or 0)
end

local function renderSkinCards()
	for _, child in ipairs(cardsContainer:GetChildren()) do
		child:Destroy()
	end

	for category, button in pairs(categoryButtons) do
		button.BackgroundColor3 = category == selectedCategory and theme.green or Color3.fromRGB(82, 82, 82)
	end

	skinCharacterTitle.Text = selectedCategory
	skinKillsTitle.Text = string.format("Career Kills: %d", currentKills)

	for index, skin in ipairs(SkinCatalog[selectedCategory]) do
		local col = (index - 1) % 6
		local row = math.floor((index - 1) / 6)
		local unlocked = isSkinUnlocked(selectedCategory, skin)
		local selected = selectedSkins[selectedCategory] == skin.Id
		local card = create("TextButton", {
			Position = UDim2.new(0, col * 102, 0, row * 110),
			Size = UDim2.fromOffset(92, 100),
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
			Text = selected and "Selected" or string.format("%d kills", skin.UnlockKills),
			TextColor3 = theme.white,
			TextSize = 9,
			TextXAlignment = Enum.TextXAlignment.Left,
			Parent = card,
		})

		card.MouseEnter:Connect(function()
			TweenService:Create(card, TweenInfo.new(0.1), {
				Size = UDim2.fromOffset(98, 106),
			}):Play()
			TweenService:Create(stroke, TweenInfo.new(0.1), {
				Transparency = 0.2,
			}):Play()
		end)

		card.MouseLeave:Connect(function()
			TweenService:Create(card, TweenInfo.new(0.1), {
				Size = UDim2.fromOffset(92, 100),
			}):Play()
			TweenService:Create(stroke, TweenInfo.new(0.1), {
				Transparency = 0.68,
			}):Play()
		end)

		card.MouseButton1Click:Connect(function()
			if not unlocked then
				playUnavailableCardFeedback(card, stroke)
				notify("That skin is unavailable.")
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

settingsButton.MouseButton1Click:Connect(function()
	showPage("Settings")
end)

backFromCredits.MouseButton1Click:Connect(function()
	showPage("Home")
end)

backFromSkins.MouseButton1Click:Connect(function()
	showPage("Home")
end)

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
		if not slot.Available then
			notify("That character is not selectable yet.")
			return
		end

		combatRequest:FireServer({
			Action = "SelectKit",
			KitId = slot.Name,
		})
		closeMenuWithFade()
	end)
end

renderSkinCards()

local startTime = os.clock()
RunService.RenderStepped:Connect(function()
	local elapsed = os.clock() - startTime
	titleGlow.Position = UDim2.fromScale(0.5, 0.05 + math.sin(elapsed * 0.6) * 0.004)
	floorGlow.Size = UDim2.new(1.28 + math.sin(elapsed * 0.5) * 0.03, 0, 0.42, 0)

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
	openMenuHome()
	local humanoid = character:FindFirstChildOfClass("Humanoid") or character:WaitForChild("Humanoid")
	humanoid.Died:Connect(openMenuHome)
end

player.CharacterAdded:Connect(hookCharacter)
if player.Character then
	hookCharacter(player.Character)
end

local function refreshMenuVisibility()
	gui.Enabled = playerGui:GetAttribute(Constants.LOADING_ATTRIBUTE) and playerGui:GetAttribute(Constants.MENU_ATTRIBUTE)
	if gui.Enabled and menuMusic.SoundId ~= "" then
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
				if not gui.Enabled and menuMusic.IsPlaying then
					menuMusic:Stop()
				end
			end)
		end
	end
end

playerGui:GetAttributeChangedSignal(Constants.LOADING_ATTRIBUTE):Connect(refreshMenuVisibility)
playerGui:GetAttributeChangedSignal(Constants.MENU_ATTRIBUTE):Connect(refreshMenuVisibility)
refreshMenuVisibility()

combatState.OnClientEvent:Connect(function(payload)
	if typeof(payload) ~= "table" then
		return
	end

	if payload.Type == "Profile" then
		currentKills = payload.Kills or 0
		selectedSkins = payload.SelectedSkins or selectedSkins
		renderSkinCards()
	end
end)

combatRequest:FireServer({Action = "RequestProfile"})
