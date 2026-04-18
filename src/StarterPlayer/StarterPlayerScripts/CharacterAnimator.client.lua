local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CharacterKits = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("CharacterKits"))
local Constants = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Constants"))

local player = Players.LocalPlayer
local SANS_WALK_ANIMATION_SPEED_SCALE = 1.2

local activeTracks = {
	Idle = nil,
	CombatIdle = nil,
	Walk = nil,
	Block = nil,
	DodgeLeft = nil,
	DodgeRight = nil,
}

local connections = {}
local dodgeEndsAt = 0

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

local function getSansBlockAnimationId(character, kit)
	local animationIds = kit and kit.AnimationIds
	if not animationIds then
		return 0
	end

	local mode = character and character:GetAttribute("Mode")
	local blockByMode = animationIds.BlockByMode
	if type(blockByMode) == "table" and mode and blockByMode[mode] then
		return blockByMode[mode]
	end

	return animationIds.Block or 0
end

local function stopMovementTracks(fadeTime)
	fadeTime = fadeTime or 0.08
	if activeTracks.Walk and activeTracks.Walk.IsPlaying then
		activeTracks.Walk:Stop(fadeTime)
	end
	if activeTracks.Idle and activeTracks.Idle.IsPlaying then
		activeTracks.Idle:Stop(fadeTime)
	end
	if activeTracks.CombatIdle and activeTracks.CombatIdle.IsPlaying then
		activeTracks.CombatIdle:Stop(fadeTime)
	end
	if activeTracks.Block and activeTracks.Block.IsPlaying then
		activeTracks.Block:Stop(fadeTime)
	end
end

local function stopLocomotionTracks(fadeTime)
	fadeTime = fadeTime or 0.08
	if activeTracks.Walk and activeTracks.Walk.IsPlaying then
		activeTracks.Walk:Stop(fadeTime)
	end
	if activeTracks.Idle and activeTracks.Idle.IsPlaying then
		activeTracks.Idle:Stop(fadeTime)
	end
	if activeTracks.CombatIdle and activeTracks.CombatIdle.IsPlaying then
		activeTracks.CombatIdle:Stop(fadeTime)
	end
end

local function playDodge(direction)
	local track = direction == "Left" and activeTracks.DodgeLeft or activeTracks.DodgeRight
	if not track then
		if Constants.SANS_DODGE_DEBUG then
			warn(string.format("[SansDodgeDebug][Animator] missing track direction=%s left=%s right=%s", tostring(direction), tostring(activeTracks.DodgeLeft ~= nil), tostring(activeTracks.DodgeRight ~= nil)))
			local reporter = _G.JudgementDividedDodgeDebug
			if reporter then
				reporter(string.format("ANIM missing track | dir %s", tostring(direction)))
			end
		end
		return
	end

	stopMovementTracks(0.05)
	if track.IsPlaying then
		track:Stop(0.02)
	end
	track.TimePosition = 0
	track:AdjustSpeed(1)
	track:Play(0.04)
	dodgeEndsAt = os.clock() + math.max(0.35, track.Length > 0 and math.min(track.Length, 0.7) or 0.35)
	if Constants.SANS_DODGE_DEBUG then
		warn(string.format("[SansDodgeDebug][Animator] play direction=%s length=%.3f", tostring(direction), track.Length))
		local reporter = _G.JudgementDividedDodgeDebug
		if reporter then
			reporter(string.format("ANIM play %s | len %.2f", tostring(direction), track.Length))
		end
	end
end

local function syncMovement(humanoid)
	local character = humanoid.Parent
	local isBlocking = character and character:GetAttribute("Blocking") == true
	local inCombat = character and character:GetAttribute("InCombat") == true
	local isDodging = (character and character:GetAttribute("Dodging") == true) or os.clock() < dodgeEndsAt
	local moving = humanoid.MoveDirection.Magnitude > 0.05 and humanoid.FloorMaterial ~= Enum.Material.Air
	local idleTrack = inCombat and activeTracks.CombatIdle or activeTracks.Idle
	local alternateIdleTrack = inCombat and activeTracks.Idle or activeTracks.CombatIdle

	if isDodging then
		stopMovementTracks(0.05)
		return
	end

	if isBlocking then
		stopLocomotionTracks(0.08)
		if activeTracks.Block and not activeTracks.Block.IsPlaying then
			activeTracks.Block.TimePosition = 0
			activeTracks.Block:AdjustSpeed(1)
			activeTracks.Block:Play(0.08)
		end
		if activeTracks.Block and activeTracks.Block.IsPlaying and activeTracks.Block.Speed ~= 0 then
			local holdTime = math.max(0, activeTracks.Block.Length - 0.02)
			if activeTracks.Block.Length > 0.05 and activeTracks.Block.TimePosition >= holdTime then
				activeTracks.Block.TimePosition = holdTime
				activeTracks.Block:AdjustSpeed(0)
			end
		end
		return
	end

	if activeTracks.Block and activeTracks.Block.IsPlaying then
		activeTracks.Block:Stop(0.08)
	end
	if activeTracks.Block then
		activeTracks.Block.TimePosition = 0
		activeTracks.Block:AdjustSpeed(1)
	end

	if moving then
		if idleTrack and idleTrack.IsPlaying then
			idleTrack:Stop(0.12)
		end
		if alternateIdleTrack and alternateIdleTrack.IsPlaying then
			alternateIdleTrack:Stop(0.12)
		end
		if activeTracks.Walk and not activeTracks.Walk.IsPlaying then
			activeTracks.Walk:Play(0.12)
		end
		if activeTracks.Walk then
			local speedScale = math.clamp(humanoid.WalkSpeed / Constants.DEFAULT_WALKSPEED, 0.1, 3)
			if character:GetAttribute("KitId") == "Sans" then
				speedScale *= SANS_WALK_ANIMATION_SPEED_SCALE
			end
			activeTracks.Walk:AdjustSpeed(speedScale)
		end
	else
		if activeTracks.Walk and activeTracks.Walk.IsPlaying then
			activeTracks.Walk:Stop(0.12)
		end
		if alternateIdleTrack and alternateIdleTrack.IsPlaying then
			alternateIdleTrack:Stop(0.12)
		end
		if idleTrack and not idleTrack.IsPlaying then
			idleTrack:Play(0.12)
		end
	end
end

local function applyKitAnimations(character)
	stopTracks()
	disconnectAll()
	dodgeEndsAt = 0

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end

	table.insert(connections, character:GetAttributeChangedSignal("KitId"):Connect(function()
		applyKitAnimations(character)
	end))

	local kitId = character:GetAttribute("KitId")
	local kit = kitId and CharacterKits[kitId]
	if not kit then
		return
	end

	if kitId ~= "Sans" then
		return
	end

	local animator = humanoid:FindFirstChildOfClass("Animator") or Instance.new("Animator", humanoid)
	activeTracks.Idle = createTrack(animator, kit.AnimationIds and kit.AnimationIds.Idle, Enum.AnimationPriority.Idle)
	activeTracks.CombatIdle = createTrack(animator, kit.AnimationIds and kit.AnimationIds.CombatIdle, Enum.AnimationPriority.Idle)
	activeTracks.Walk = createTrack(animator, kit.AnimationIds and kit.AnimationIds.Walk, Enum.AnimationPriority.Movement)
	activeTracks.Block = createTrack(animator, getSansBlockAnimationId(character, kit), Enum.AnimationPriority.Action)
	activeTracks.DodgeLeft = createTrack(animator, kit.AnimationIds and kit.AnimationIds.DodgeLeft, Enum.AnimationPriority.Action4)
	activeTracks.DodgeRight = createTrack(animator, kit.AnimationIds and kit.AnimationIds.DodgeRight, Enum.AnimationPriority.Action4)

	if activeTracks.Idle then
		activeTracks.Idle.Looped = true
	end
	if activeTracks.CombatIdle then
		activeTracks.CombatIdle.Looped = true
	end
	if activeTracks.Walk then
		activeTracks.Walk.Looped = true
	end
	if activeTracks.Block then
		activeTracks.Block.Looped = false
	end
	if activeTracks.DodgeLeft then
		activeTracks.DodgeLeft.Looped = false
	end
	if activeTracks.DodgeRight then
		activeTracks.DodgeRight.Looped = false
	end

	table.insert(connections, RunService.RenderStepped:Connect(function()
		if character.Parent and humanoid.Health > 0 then
			syncMovement(humanoid)
		end
	end))

	table.insert(connections, character:GetAttributeChangedSignal("Mode"):Connect(function()
		applyKitAnimations(character)
	end))

	table.insert(connections, character:GetAttributeChangedSignal("Blocking"):Connect(function()
		syncMovement(humanoid)
	end))

	table.insert(connections, character:GetAttributeChangedSignal("InCombat"):Connect(function()
		syncMovement(humanoid)
	end))

	table.insert(connections, character:GetAttributeChangedSignal("Dodging"):Connect(function()
		syncMovement(humanoid)
	end))

	table.insert(connections, character:GetAttributeChangedSignal("DodgeNonce"):Connect(function()
		if Constants.SANS_DODGE_DEBUG then
			warn(string.format("[SansDodgeDebug][Animator] nonce=%s direction=%s dodging=%s", tostring(character:GetAttribute("DodgeNonce")), tostring(character:GetAttribute("DodgeDirection")), tostring(character:GetAttribute("Dodging"))))
			local reporter = _G.JudgementDividedDodgeDebug
			if reporter then
				reporter(string.format("ANIM nonce %s | dir %s", tostring(character:GetAttribute("DodgeNonce")), tostring(character:GetAttribute("DodgeDirection"))))
			end
		end
		playDodge(character:GetAttribute("DodgeDirection"))
	end))

	syncMovement(humanoid)
end

player.CharacterAdded:Connect(function(character)
	applyKitAnimations(character)
end)

if player.Character then
	applyKitAnimations(player.Character)
end
