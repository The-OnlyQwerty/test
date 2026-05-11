local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Constants = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Constants"))

local player = Players.LocalPlayer
local CAMERA_SHAKE_LIFETIME = 0.18
local CAMERA_SHAKE_POSITION_SCALE = 0.08
local CAMERA_SHAKE_ROTATION_SCALE = 0.9
local cameraShakeState = {
	Magnitude = 0,
	ExpiresAt = 0,
	Seed = 0,
}

local cameraEffects = rawget(_G, "JudgementDividedCameraEffects") or {}
_G.JudgementDividedCameraEffects = cameraEffects

local function getRoot(model)
	return model and model:FindFirstChild("HumanoidRootPart")
end

local function getHumanoid(model)
	return model and model:FindFirstChildOfClass("Humanoid")
end

local function isRotationLocked(character)
	return character and character:GetAttribute("KnockbackLocked") == true
end

function cameraEffects.AddImpulse(config)
	local magnitude = config
	if type(config) == "table" then
		magnitude = config.magnitude
	end

	magnitude = tonumber(magnitude) or 0
	if magnitude <= 0 then
		return
	end

	cameraShakeState.Magnitude = math.clamp(math.max(cameraShakeState.Magnitude, magnitude), 0, 2.5)
	cameraShakeState.ExpiresAt = os.clock() + CAMERA_SHAKE_LIFETIME
	cameraShakeState.Seed += 11.37
end

local function getShakeNoise(seedOffset, timePosition)
	return math.noise(cameraShakeState.Seed + seedOffset, timePosition, 0)
end

local function applyCameraShake(camera)
	local remaining = cameraShakeState.ExpiresAt - os.clock()
	if not camera or remaining <= 0 or cameraShakeState.Magnitude <= 0.001 then
		cameraShakeState.Magnitude = 0
		return
	end

	local fadeAlpha = math.clamp(remaining / CAMERA_SHAKE_LIFETIME, 0, 1)
	local strength = cameraShakeState.Magnitude * fadeAlpha
	local timePosition = os.clock() * 24
	local x = getShakeNoise(0, timePosition) * strength
	local y = getShakeNoise(13, timePosition) * strength
	local z = getShakeNoise(29, timePosition) * strength

	camera.CFrame = camera.CFrame
		* CFrame.new(x * CAMERA_SHAKE_POSITION_SCALE, y * CAMERA_SHAKE_POSITION_SCALE, math.abs(z) * -0.04 * strength)
		* CFrame.Angles(
			math.rad(y * CAMERA_SHAKE_ROTATION_SCALE),
			math.rad(x * CAMERA_SHAKE_ROTATION_SCALE),
			math.rad(z * CAMERA_SHAKE_ROTATION_SCALE * 1.35)
		)
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
	local flatDirection = Vector3.new(targetRoot.Position.X - playerRoot.Position.X, 0, targetRoot.Position.Z - playerRoot.Position.Z)
	if flatDirection.Magnitude < 0.01 then
		flatDirection = Vector3.new(playerRoot.CFrame.LookVector.X, 0, playerRoot.CFrame.LookVector.Z)
	end
	if flatDirection.Magnitude < 0.01 then
		flatDirection = Vector3.zAxis
	else
		flatDirection = flatDirection.Unit
	end

	local right = flatDirection:Cross(Vector3.yAxis)
	local cameraPosition =
		playerRoot.Position
		- flatDirection * Constants.CAMERA_LOCKED_DISTANCE
		+ right * Constants.CAMERA_LOCKED_RIGHT_SHIFT
		+ Vector3.new(0, Constants.CAMERA_LOCKED_HEIGHT, 0)

	humanoid.AutoRotate = false
	if not isRotationLocked(character) then
		playerRoot.CFrame = CFrame.lookAt(playerRoot.Position, playerRoot.Position + flatDirection)
	end
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
		applyCameraShake(Workspace.CurrentCamera)
		return
	end

	if targetModel and lockOn and lockOn.ClearLock then
		lockOn.ClearLock(true)
	end

	applyUnlockedCamera()
	applyCameraShake(Workspace.CurrentCamera)
end)
