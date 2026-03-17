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

local loadingSteps = {
	"Loading menu visuals...",
	"Loading character data...",
	"Loading combat systems...",
	"Loading animations...",
	"Finalizing interface...",
}

local preloadInstances = {
	ReplicatedStorage,
	ReplicatedStorage:WaitForChild("Shared"),
	ReplicatedStorage:WaitForChild("Remotes"),
	StarterPlayer:WaitForChild("StarterPlayerScripts"),
}

for _, kit in pairs(CharacterKits) do
	local animationIds = kit.AnimationIds
	if animationIds then
		for _, animationId in pairs(animationIds) do
			if animationId and animationId ~= 0 then
				local animation = Instance.new("Animation")
				animation.AnimationId = "rbxassetid://" .. tostring(animationId)
				table.insert(preloadInstances, animation)
			end
		end
	end
end

task.spawn(function()
	local stepCount = #loadingSteps
	for index, step in ipairs(loadingSteps) do
		status.Text = step
		barFill:TweenSize(UDim2.new((index - 0.25) / stepCount, 0, 1, 0), Enum.EasingDirection.Out, Enum.EasingStyle.Quad, 0.18, true)
		task.wait(0.08)
		pcall(function()
			ContentProvider:PreloadAsync(preloadInstances)
		end)
	end

	barFill:TweenSize(UDim2.new(1, 0, 1, 0), Enum.EasingDirection.Out, Enum.EasingStyle.Quad, 0.2, true)
	status.Text = "Complete"
	task.wait(0.2)

	playerGui:SetAttribute(Constants.LOADING_ATTRIBUTE, true)

	TweenService:Create(root, TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		BackgroundTransparency = 1,
	}):Play()
	TweenService:Create(barBack, TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		BackgroundTransparency = 1,
	}):Play()
	TweenService:Create(barFill, TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		BackgroundTransparency = 1,
	}):Play()
	for _, label in ipairs({title, status, hint}) do
		TweenService:Create(label, TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			TextTransparency = 1,
		}):Play()
	end

	task.wait(0.45)
	gui:Destroy()
end)
