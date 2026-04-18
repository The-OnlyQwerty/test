local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Constants = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Constants"))

local player = Players.LocalPlayer

local function getRoot(model)
	return model and model:FindFirstChild("HumanoidRootPart")
end

local function getHumanoid(model)
	return model and model:FindFirstChildOfClass("Humanoid")
end

local function isRotationLocked(character)
	return character and character:GetAttribute("KnockbackLocked") == true
end

local function applyUnlockedCamera()
	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end

	camera.CameraType = Enum.CameraType.Custom
	camera.FieldOfView = Constants.DEFAULT_FOV
	player.CameraMode = Enum.CameraMode.Classic
	player.CameraMinZoomDistance = 0.5
	player.CameraMaxZoomDistance = 128

	local character = player.Character
	local humanoid = getHumanoid(character)
	if humanoid then
		camera.CameraSubject = humanoid
		humanoid.AutoRotate = not isRotationLocked(character)
		humanoid.CameraOffset = Vector3.zero
	end
end

local function applyLockedCamera(targetModel)
	local camera = Workspace.CurrentCamera
	local character = player.Character
	local playerRoot = getRoot(character)
	local humanoid = getHumanoid(character)
	local targetHumanoid = getHumanoid(targetModel)
	local targetRoot = getRoot(targetModel)
	if not camera or not playerRoot or not targetRoot or not humanoid or not targetHumanoid then
		return false
	end

	if humanoid.Health <= 0 or targetHumanoid.Health <= 0 then
		return false
	end

	local targetPoint = targetRoot.Position + Vector3.new(0, 2.5, 0)
	local flatDirection = targetRoot.Position - playerRoot.Position
	if flatDirection.Magnitude < 0.01 then
		flatDirection = playerRoot.CFrame.LookVector
	end
	flatDirection = Vector3.new(flatDirection.X, 0, flatDirection.Z).Unit

	local right = flatDirection:Cross(Vector3.yAxis)
	local cameraPosition =
		playerRoot.Position
		- flatDirection * Constants.CAMERA_LOCKED_DISTANCE
		+ right * Constants.CAMERA_LOCKED_RIGHT_SHIFT
		+ Vector3.new(0, Constants.CAMERA_LOCKED_HEIGHT, 0)

	humanoid.AutoRotate = false
	playerRoot.CFrame = CFrame.lookAt(playerRoot.Position, playerRoot.Position + flatDirection)
	camera.CameraType = Enum.CameraType.Scriptable
	camera.FieldOfView = Constants.LOCK_ON_FOV
	camera.CFrame = CFrame.lookAt(cameraPosition, targetPoint)
	return true
end

player.CharacterAdded:Connect(function()
	applyUnlockedCamera()
end)

if player.Character then
	applyUnlockedCamera()
end

RunService:BindToRenderStep("JudgementDividedCamera", Enum.RenderPriority.Camera.Value + 1, function()
	local lockOn = _G.JudgementDividedLockOn
	local targetModel = lockOn and lockOn.GetLockedModel and lockOn.GetLockedModel() or nil
	if targetModel and applyLockedCamera(targetModel) then
		return
	end

	if targetModel and lockOn and lockOn.ClearLock then
		lockOn.ClearLock(true)
	end

	applyUnlockedCamera()
end)
