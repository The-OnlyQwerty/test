local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local StarterGui = game:GetService("StarterGui")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Constants = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Constants"))

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local mouse = player:GetMouse()

local currentTarget
local lastLockedTarget
local camera = Workspace.CurrentCamera
local characterHumanoidConnection

local function updateFov(targetFov)
	if not camera then
		camera = Workspace.CurrentCamera
	end
	if not camera then
		return
	end

	TweenService:Create(camera, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		FieldOfView = targetFov,
	}):Play()
end

local function notify(text)
	return
end

local function getRoot(model)
	return model and model:FindFirstChild("HumanoidRootPart")
end

local function getHumanoid(model)
	return model and model:FindFirstChildOfClass("Humanoid")
end

local function isAliveTarget(model)
	local humanoid = getHumanoid(model)
	return humanoid and humanoid.Health > 0 and getRoot(model)
end

local function getTargetFromMouse()
	local hitPart = mouse.Target
	local model = hitPart and hitPart:FindFirstAncestorOfClass("Model")
	if not model or not isAliveTarget(model) then
		return nil
	end

	if model == player.Character then
		return nil
	end

	return model
end

local function setTarget(model, options)
	options = options or {}
	currentTarget = model
	if model then
		lastLockedTarget = model
		updateFov(Constants.LOCK_ON_FOV)
		if not options.Silent then
			notify("Locked")
		end
	else
		updateFov(Constants.DEFAULT_FOV)
		if not options.Silent then
			notify("Lock cleared")
		end
	end
end

local function isValidTarget(model)
	return model and model.Parent and isAliveTarget(model)
end

local function getCharacterRoot()
	return player.Character and player.Character:FindFirstChild("HumanoidRootPart")
end

local function getNearestTarget()
	local root = getCharacterRoot()
	if not root then
		return nil
	end

	local bestTarget
	local bestDistance = math.huge
	for _, descendant in ipairs(workspace:GetDescendants()) do
		if descendant:IsA("Model") and descendant ~= player.Character and isAliveTarget(descendant) then
			local targetRoot = getRoot(descendant)
			local distance = (targetRoot.Position - root.Position).Magnitude
			if distance < bestDistance and distance <= 80 then
				bestTarget = descendant
				bestDistance = distance
			end
		end
	end

	return bestTarget
end

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed or playerGui:GetAttribute(Constants.MENU_ATTRIBUTE) then
		return
	end

	if input.UserInputType == Enum.UserInputType.MouseButton3 then
		setTarget(getTargetFromMouse())
	elseif input.KeyCode == Enum.KeyCode.X then
		if isValidTarget(lastLockedTarget) then
			currentTarget = lastLockedTarget
			updateFov(Constants.LOCK_ON_FOV)
			notify("Relocked")
		else
			updateFov(Constants.DEFAULT_FOV)
			notify("No previous target")
		end
	end
end)

player.CharacterAdded:Connect(function(character)
	setTarget(nil, {Silent = true})
	if characterHumanoidConnection then
		characterHumanoidConnection:Disconnect()
		characterHumanoidConnection = nil
	end

	local humanoid = getHumanoid(character)
	if humanoid then
		characterHumanoidConnection = humanoid.Died:Connect(function()
			setTarget(nil, {Silent = true})
		end)
	end
end)

player.CharacterRemoving:Connect(function()
	setTarget(nil, {Silent = true})
	if characterHumanoidConnection then
		characterHumanoidConnection:Disconnect()
		characterHumanoidConnection = nil
	end
end)

_G.JudgementDividedLockOn = {
	GetLockedPosition = function()
		if isValidTarget(currentTarget) then
			return getRoot(currentTarget).Position + Vector3.new(0, 2, 0)
		end
		currentTarget = nil
		updateFov(Constants.DEFAULT_FOV)
		return nil
	end,
	GetLockedName = function()
		return isValidTarget(currentTarget) and currentTarget.Name or nil
	end,
	GetLockedModel = function()
		return isValidTarget(currentTarget) and currentTarget or nil
	end,
	LockFromCursor = function()
		setTarget(getTargetFromMouse())
	end,
	LockNearest = function()
		setTarget(getNearestTarget())
	end,
	RelockLast = function()
		if isValidTarget(lastLockedTarget) then
			currentTarget = lastLockedTarget
			updateFov(Constants.LOCK_ON_FOV)
			notify("Relocked")
		else
			updateFov(Constants.DEFAULT_FOV)
			notify("No previous target")
		end
	end,
	ClearLock = function(silent)
		setTarget(nil, {Silent = silent == true})
	end,
}
