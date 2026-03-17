local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CharacterKits = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("CharacterKits"))

local player = Players.LocalPlayer

local activeTracks = {
	Idle = nil,
	Walk = nil,
}

local connections = {}

local function disconnectAll()
	for _, connection in ipairs(connections) do
		connection:Disconnect()
	end
	table.clear(connections)
end

local function stopTracks()
	for key, track in pairs(activeTracks) do
		if track then
			track:Stop(0.15)
			track:Destroy()
			activeTracks[key] = nil
		end
	end
end

local function createTrack(animator, animationId, priority)
	if not animationId or animationId == 0 then
		return nil
	end

	local animation = Instance.new("Animation")
	animation.AnimationId = "rbxassetid://" .. tostring(animationId)
	local track = animator:LoadAnimation(animation)
	track.Priority = priority
	return track
end

local function syncMovement(humanoid)
	local moving = humanoid.MoveDirection.Magnitude > 0.05 and humanoid.FloorMaterial ~= Enum.Material.Air

	if moving then
		if activeTracks.Idle and activeTracks.Idle.IsPlaying then
			activeTracks.Idle:Stop(0.12)
		end
		if activeTracks.Walk and not activeTracks.Walk.IsPlaying then
			activeTracks.Walk:Play(0.12)
		end
	else
		if activeTracks.Walk and activeTracks.Walk.IsPlaying then
			activeTracks.Walk:Stop(0.12)
		end
		if activeTracks.Idle and not activeTracks.Idle.IsPlaying then
			activeTracks.Idle:Play(0.12)
		end
	end
end

local function applyKitAnimations(character)
	stopTracks()
	disconnectAll()

	local kitId = character:GetAttribute("KitId")
	local kit = kitId and CharacterKits[kitId]
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not kit or not humanoid then
		return
	end

	if kitId ~= "Sans" then
		return
	end

	local animator = humanoid:FindFirstChildOfClass("Animator") or Instance.new("Animator", humanoid)
	activeTracks.Idle = createTrack(animator, kit.AnimationIds and kit.AnimationIds.Idle, Enum.AnimationPriority.Idle)
	activeTracks.Walk = createTrack(animator, kit.AnimationIds and kit.AnimationIds.Walk, Enum.AnimationPriority.Movement)

	if activeTracks.Idle then
		activeTracks.Idle.Looped = true
	end
	if activeTracks.Walk then
		activeTracks.Walk.Looped = true
	end

	table.insert(connections, RunService.RenderStepped:Connect(function()
		if character.Parent and humanoid.Health > 0 then
			syncMovement(humanoid)
		end
	end))

	table.insert(connections, character:GetAttributeChangedSignal("KitId"):Connect(function()
		applyKitAnimations(character)
	end))

	syncMovement(humanoid)
end

player.CharacterAdded:Connect(function(character)
	applyKitAnimations(character)
end)

if player.Character then
	applyKitAnimations(player.Character)
end
