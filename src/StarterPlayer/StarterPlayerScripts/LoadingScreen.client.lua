local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ContentProvider = game:GetService("ContentProvider")
local TweenService = game:GetService("TweenService")
local StarterPlayer = game:GetService("StarterPlayer")

local Constants = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Constants"))
local CharacterKits = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("CharacterKits"))

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
playerGui:SetAttribute(Constants.LOADING_ATTRIBUTE, false)

local function create(instanceType, props)
	local instance = Instance.new(instanceType)
	for key, value in pairs(props) do
		instance[key] = value
	end
	return instance
end

local gui = create("ScreenGui", {
	Name = "LoadingScreen",
	IgnoreGuiInset = true,
	ResetOnSpawn = false,
	Parent = playerGui,
})

local root = create("Frame", {
	Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = Color3.fromRGB(9, 10, 18),
	BorderSizePixel = 0,
	Parent = gui,
})

create("UIGradient", {
	Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(84, 10, 10)),
		ColorSequenceKeypoint.new(0.45, Color3.fromRGB(179, 77, 12)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(10, 11, 20)),
	}),
	Rotation = 90,
	Parent = root,
})

local title = create("TextLabel", {
	BackgroundTransparency = 1,
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.38),
	Size = UDim2.fromOffset(760, 120),
	Font = Enum.Font.Arcade,
	Text = "JUDGEMENT DIVIDED",
	TextColor3 = Color3.fromRGB(245, 244, 240),
	TextSize = 44,
	Parent = root,
})

local status = create("TextLabel", {
	BackgroundTransparency = 1,
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.58),
	Size = UDim2.fromOffset(520, 34),
	Font = Enum.Font.Arcade,
	Text = "Loading menu visuals...",
	TextColor3 = Color3.fromRGB(224, 204, 188),
	TextSize = 15,
	Parent = root,
})

local barBack = create("Frame", {
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.65),
	Size = UDim2.fromOffset(420, 18),
	BackgroundColor3 = Color3.fromRGB(18, 18, 24),
	BorderSizePixel = 0,
	Parent = root,
})
create("UICorner", {CornerRadius = UDim.new(1, 0), Parent = barBack})

local barFill = create("Frame", {
	Size = UDim2.new(0, 0, 1, 0),
	BackgroundColor3 = Color3.fromRGB(255, 170, 45),
	BorderSizePixel = 0,
	Parent = barBack,
})
create("UICorner", {CornerRadius = UDim.new(1, 0), Parent = barFill})

local percentLabel = create("TextLabel", {
	BackgroundTransparency = 1,
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.new(1, -10, 1, 0),
	Font = Enum.Font.Arcade,
	Text = "0%",
	TextColor3 = Color3.fromRGB(26, 16, 10),
	TextSize = 10,
	ZIndex = 3,
	Parent = barBack,
})

local hint = create("TextLabel", {
	BackgroundTransparency = 1,
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.73),
	Size = UDim2.fromOffset(560, 28),
	Font = Enum.Font.Arcade,
	Text = "Preparing combat scripts, menu UI, and character data",
	TextColor3 = Color3.fromRGB(245, 244, 240),
	TextTransparency = 0.2,
	TextSize = 12,
	Parent = root,
})

local detail = create("TextLabel", {
	BackgroundTransparency = 1,
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.79),
	Size = UDim2.fromOffset(620, 24),
	Font = Enum.Font.Arcade,
	Text = "Building asset list...",
	TextColor3 = Color3.fromRGB(224, 204, 188),
	TextTransparency = 0.12,
	TextSize = 10,
	Parent = root,
})

local PRELOADABLE_CLASS_NAMES = {
	Animation = true,
	Sound = true,
	Decal = true,
	Texture = true,
	ImageLabel = true,
	ImageButton = true,
	MeshPart = true,
	SpecialMesh = true,
	SurfaceAppearance = true,
	ShirtGraphic = true,
	Shirt = true,
	Pants = true,
}

local generatedInstances = {}

local function addUniqueTarget(list, seen, instance)
	if instance and not seen[instance] then
		seen[instance] = true
		table.insert(list, instance)
	end
end

local function collectPreloadTargets(rootInstance, list, seen)
	if not rootInstance then
		return
	end

	for _, descendant in ipairs(rootInstance:GetDescendants()) do
		if PRELOADABLE_CLASS_NAMES[descendant.ClassName] then
			addUniqueTarget(list, seen, descendant)
		end
	end
end

local function clonePath(parts)
	local copy = {}
	for index, value in ipairs(parts) do
		copy[index] = value
	end
	return copy
end

local function collectAnimationTargets(value, pathParts, list, seenIds)
	if type(value) == "number" then
		if value == 0 then
			return
		end

		local id = tostring(value)
		if seenIds[id] then
			return
		end

		seenIds[id] = true
		local animation = Instance.new("Animation")
		animation.Name = table.concat(pathParts, " ")
		animation.AnimationId = "rbxassetid://" .. id
		table.insert(generatedInstances, animation)
		table.insert(list, animation)
		return
	end

	if type(value) ~= "table" then
		return
	end

	for key, child in pairs(value) do
		local nextPath = clonePath(pathParts)
		table.insert(nextPath, tostring(key))
		collectAnimationTargets(child, nextPath, list, seenIds)
	end
end

local mapTargets = {}
local replicatedTargets = {}
local animationTargets = {}
local audioTargets = {}
local mapSeen = {}
local replicatedSeen = {}
local seenAnimationIds = {}

collectPreloadTargets(workspace, mapTargets, mapSeen)
collectPreloadTargets(ReplicatedStorage, replicatedTargets, replicatedSeen)

for kitId, kit in pairs(CharacterKits) do
	if kit.AnimationIds then
		collectAnimationTargets(kit.AnimationIds, {tostring(kit.DisplayName or kitId), "Animations"}, animationTargets, seenAnimationIds)
	end
end

collectAnimationTargets({
	AirKnockback = Constants.KNOCKBACK_AIR_ANIMATION_ID,
	KnockbackSlide = Constants.KNOCKBACK_SLIDE_ANIMATION_ID,
}, {"Shared", "Knockback Animations"}, animationTargets, seenAnimationIds)

local preloadAudioIds = {
	{"Menu Music", Constants.MENU_MUSIC_ID},
	{"Battle Music", Constants.BATTLE_MUSIC_ID},
	{"Tense Battle Music", Constants.TENSE_BATTLE_MUSIC_ID},
	{"Training Music", Constants.TRAINING_MUSIC_ID},
}

local seenPreloadAudioIds = {}
for _, audioInfo in ipairs(preloadAudioIds) do
	local audioId = tonumber(audioInfo[2]) or 0
	if audioId ~= 0 then
		seenPreloadAudioIds[audioId] = true
	end
end

for kitId, soundId in pairs(Constants.CHARACTER_THEME_IDS or {}) do
	local numericSoundId = tonumber(soundId) or 0
	if numericSoundId ~= 0 and not seenPreloadAudioIds[numericSoundId] then
		table.insert(preloadAudioIds, {tostring(kitId) .. " Theme", numericSoundId})
		seenPreloadAudioIds[numericSoundId] = true
	end
end

for kitId, skins in pairs(Constants.SKIN_THEME_IDS or {}) do
	if type(skins) == "table" then
		for skinId, phases in pairs(skins) do
			if type(phases) == "table" then
				for phaseName, soundId in pairs(phases) do
					local numericSoundId = tonumber(soundId) or 0
					if numericSoundId ~= 0 and not seenPreloadAudioIds[numericSoundId] then
						table.insert(preloadAudioIds, {string.format("%s %s %s", tostring(kitId), tostring(skinId), tostring(phaseName)), numericSoundId})
						seenPreloadAudioIds[numericSoundId] = true
					end
				end
			end
		end
	end
end

for _, audioInfo in ipairs(preloadAudioIds) do
	local audioName = audioInfo[1]
	local audioId = audioInfo[2]
	if audioId and audioId ~= 0 then
		local sound = Instance.new("Sound")
		sound.Name = audioName
		sound.SoundId = "rbxassetid://" .. tostring(audioId)
		table.insert(generatedInstances, sound)
		table.insert(audioTargets, sound)
	end
end

local loadingStages = {
	{
		Name = "Loading map assets...",
		Targets = mapTargets,
	},
	{
		Name = "Loading replicated assets...",
		Targets = replicatedTargets,
	},
	{
		Name = "Loading character animations...",
		Targets = animationTargets,
	},
	{
		Name = "Loading audio...",
		Targets = audioTargets,
	},
	{
		Name = "Finalizing interface...",
		Targets = {},
		Units = 1,
		Pause = 0.18,
	},
}

local totalUnits = 0
for _, stage in ipairs(loadingStages) do
	totalUnits += math.max(stage.Units or 0, #stage.Targets, 1)
end

local function getTargetLabel(target)
	if not target then
		return "Preparing"
	end

	if target.Name and target.Name ~= "" then
		return target.Name
	end

	return target.ClassName
end

local function setProgress(currentUnits, stageName, detailText)
	local progress = totalUnits > 0 and math.clamp(currentUnits / totalUnits, 0, 1) or 1
	status.Text = stageName
	hint.Text = detailText
	detail.Text = string.format("Loaded %d of %d items", math.floor(currentUnits + 0.5), totalUnits)
	percentLabel.Text = string.format("%d%%", math.floor((progress * 100) + 0.5))
	barFill:TweenSize(UDim2.new(progress, 0, 1, 0), Enum.EasingDirection.Out, Enum.EasingStyle.Quad, 0.12, true)
end

task.spawn(function()
	local completedUnits = 0
	setProgress(0, "Preparing loading pipeline...", "Scanning map, UI, audio, and animation assets")
	task.wait(0.06)

	for _, stage in ipairs(loadingStages) do
		local targets = stage.Targets
		local stageUnits = math.max(stage.Units or 0, #targets, 1)
		if #targets == 0 then
			setProgress(completedUnits, stage.Name, "No assets in this category")
			task.wait(stage.Pause or 0.08)
			completedUnits += stageUnits
			setProgress(completedUnits, stage.Name, "Ready")
		else
			for index, target in ipairs(targets) do
				setProgress(completedUnits + ((index - 1) / stageUnits), stage.Name, string.format("%s  (%d/%d)", getTargetLabel(target), index, #targets))
				pcall(function()
					ContentProvider:PreloadAsync({target})
				end)
				completedUnits += 1
				setProgress(completedUnits, stage.Name, string.format("%s loaded", getTargetLabel(target)))
				task.wait(0.01)
			end
		end
	end

	setProgress(totalUnits, "Complete", "Everything is ready")
	task.wait(0.2)

	playerGui:SetAttribute(Constants.LOADING_ATTRIBUTE, true)

	for _, instance in ipairs(generatedInstances) do
		instance:Destroy()
	end

	TweenService:Create(root, TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		BackgroundTransparency = 1,
	}):Play()
	TweenService:Create(barBack, TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		BackgroundTransparency = 1,
	}):Play()
	TweenService:Create(barFill, TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		BackgroundTransparency = 1,
	}):Play()
	for _, label in ipairs({title, status, hint, detail, percentLabel}) do
		TweenService:Create(label, TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			TextTransparency = 1,
		}):Play()
	end

	task.wait(0.45)
	gui:Destroy()
end)
