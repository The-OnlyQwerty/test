local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ContextActionService = game:GetService("ContextActionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")
local Workspace = game:GetService("Workspace")

local Constants = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Constants"))
local CharacterKits = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("CharacterKits"))

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local mouse = player:GetMouse()
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local combatRequest = remotes:WaitForChild("CombatRequest")
local combatState = remotes:WaitForChild("CombatState")

local abilityKeys = {
	[Enum.KeyCode.One] = "Z",
	[Enum.KeyCode.Two] = "X",
	[Enum.KeyCode.Three] = "C",
	[Enum.KeyCode.Four] = "V",
	[Enum.KeyCode.Five] = "G",
}

local blocking = false
local cooldowns = {}
local duelPromptActive = false
local heldAbilityTokens = {}
local heldBonesAnimation = {
	Track = nil,
	Animation = nil,
}
local dodgeAttributeConnection = nil
local lastDodgeAnimationAt = 0
local touchAttackCandidates = {}
local movementTapTimes = {}
local movementHeld = {}
local activeRunKeyCode = nil

local MOBILE_TAP_ATTACK_MAX_DURATION = 0.22
local MOBILE_TAP_ATTACK_MAX_MOVEMENT = 18

local function notify(text)
	return
end

local function isTouchOverGuiButton(screenPosition)
	local guiObjects = playerGui:GetGuiObjectsAtPosition(screenPosition.X, screenPosition.Y)
	for _, guiObject in ipairs(guiObjects) do
		if guiObject:IsA("GuiButton") then
			return true
		end
	end
	return false
end

local function getCharacter()
	return player.Character
end

local function getMode()
	local character = getCharacter()
	return character and character:GetAttribute("Mode")
end

local function getKitId()
	local character = getCharacter()
	return character and character:GetAttribute("KitId")
end

local function isBlockingLocally()
	local character = getCharacter()
	return blocking or (character and character:GetAttribute("Blocking") == true)
end

local function isJumpSuppressedLocally()
	local character = getCharacter()
	return isBlockingLocally() or (character and character:GetAttribute("KnockbackLocked") == true)
end

local function hasPendingBlasterShots()
	local character = getCharacter()
	return character and (character:GetAttribute("PendingBlasterShots") or 0) > 0
end

local function getCooldownKey(slot)
	local kitId = getKitId() or "Unknown"
	local mode = getMode() or "Base"
	return string.format("%s:%s:%s", kitId, mode, slot)
end

local function canUse(slot)
	local readyAt = cooldowns[getCooldownKey(slot)] or 0
	return os.clock() >= readyAt
end

local function getLockedPosition()
	local lockOn = _G.JudgementDividedLockOn
	return lockOn and lockOn.GetLockedPosition and lockOn.GetLockedPosition() or nil
end

local function getLockedTargetPayload()
	local lockOn = _G.JudgementDividedLockOn
	local model = lockOn and lockOn.GetLockedModel and lockOn.GetLockedModel() or nil
	if not model then
		return nil
	end

	local targetPlayer = Players:GetPlayerFromCharacter(model)
	if targetPlayer then
		return {
			LockedTargetUserId = targetPlayer.UserId,
		}
	end

	return {
		LockedTargetName = model.Name,
	}
end

local function playAnimationById(animationId, priority)
	local character = getCharacter()
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid or not animationId or animationId == 0 then
		return
	end

	local animator = humanoid:FindFirstChildOfClass("Animator") or Instance.new("Animator", humanoid)
	local animation = Instance.new("Animation")
	animation.AnimationId = "rbxassetid://" .. tostring(animationId)
	local track = animator:LoadAnimation(animation)
	track.Priority = priority or Enum.AnimationPriority.Action
	track.Looped = false
	track:Play(0.05)
	track.Stopped:Once(function()
		track:Destroy()
		animation:Destroy()
	end)
end

local function playSansDodgeAnimation(direction)
	local sansKit = CharacterKits.Sans
	local animationIds = sansKit and sansKit.AnimationIds
	if not animationIds then
		return
	end

	local nowTime = os.clock()
	if nowTime - lastDodgeAnimationAt < 0.08 then
		return
	end
	lastDodgeAnimationAt = nowTime

	local animationId = direction == "Left" and animationIds.DodgeLeft or animationIds.DodgeRight
	playAnimationById(animationId, Enum.AnimationPriority.Action4)
end

local function hookCharacterDodge(character)
	if dodgeAttributeConnection then
		dodgeAttributeConnection:Disconnect()
		dodgeAttributeConnection = nil
	end

	if not character then
		return
	end

	dodgeAttributeConnection = character:GetAttributeChangedSignal("DodgeNonce"):Connect(function()
		if character ~= getCharacter() or character:GetAttribute("KitId") ~= "Sans" then
			return
		end
		if Constants.SANS_DODGE_DEBUG then
			warn(string.format("[SansDodgeDebug][CombatClient] nonce=%s direction=%s dodging=%s", tostring(character:GetAttribute("DodgeNonce")), tostring(character:GetAttribute("DodgeDirection")), tostring(character:GetAttribute("Dodging"))))
			local reporter = _G.JudgementDividedDodgeDebug
			if reporter then
				reporter(string.format("CLIENT nonce %s | dir %s", tostring(character:GetAttribute("DodgeNonce")), tostring(character:GetAttribute("DodgeDirection"))))
			end
		end
		playSansDodgeAnimation(character:GetAttribute("DodgeDirection"))
	end)
end

local function stopHeldBonesAnimation()
	if heldBonesAnimation.Track then
		heldBonesAnimation.Track:Stop(0.08)
		heldBonesAnimation.Track:Destroy()
		heldBonesAnimation.Track = nil
	end
	if heldBonesAnimation.Animation then
		heldBonesAnimation.Animation:Destroy()
		heldBonesAnimation.Animation = nil
	end
end

local function playHeldBonesAnimation()
	if heldBonesAnimation.Track then
		return
	end

	local sansKit = CharacterKits.Sans
	local animationId = sansKit and sansKit.AnimationIds and sansKit.AnimationIds.Bones and sansKit.AnimationIds.Bones.Z
	if not animationId or animationId == 0 then
		return
	end

	local character = getCharacter()
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end

	local animator = humanoid:FindFirstChildOfClass("Animator") or Instance.new("Animator", humanoid)
	local animation = Instance.new("Animation")
	animation.AnimationId = "rbxassetid://" .. tostring(animationId)
	local track = animator:LoadAnimation(animation)
	track.Priority = Enum.AnimationPriority.Action
	track.Looped = false
	track:Play(0.05)

	heldBonesAnimation.Track = track
	heldBonesAnimation.Animation = animation

	task.spawn(function()
		local waitForLengthDeadline = os.clock() + 1
		while heldBonesAnimation.Track == track and track.Length <= 0 and os.clock() < waitForLengthDeadline do
			task.wait()
		end

		local holdTime = math.max(0, track.Length - 0.02)
		while heldBonesAnimation.Track == track do
			if track.TimePosition >= holdTime then
				track.TimePosition = holdTime
				track:AdjustSpeed(0)
				break
			end
			task.wait()
		end
	end)
end

local function playSansTeleAnimation(direction)
	local sansKit = CharacterKits.Sans
	local teleAnimations = sansKit and sansKit.AnimationIds and sansKit.AnimationIds.Telekinesis
	if not teleAnimations then
		return
	end

	local animationIdByDirection = {
		W = teleAnimations.Down,
		A = teleAnimations.Left,
		S = teleAnimations.Down,
		D = teleAnimations.Right,
		Space = teleAnimations.Up,
	}

	playAnimationById(animationIdByDirection[direction])
end

local function playSansTeleStartupAnimation()
	local sansKit = CharacterKits.Sans
	local teleAnimations = sansKit and sansKit.AnimationIds and sansKit.AnimationIds.Telekinesis
	if not teleAnimations then
		return
	end

	playAnimationById(teleAnimations.Startup)
end

local function playSansBonesAnimation(slot)
	if slot == "Z" then
		playHeldBonesAnimation()
		return
	end

	local sansKit = CharacterKits.Sans
	local bonesAnimations = sansKit and sansKit.AnimationIds and sansKit.AnimationIds.Bones
	if not bonesAnimations then
		return
	end

	playAnimationById(bonesAnimations[slot])
end

local function buildTargetedPayload(action)
	local lockedPosition = getLockedPosition()
	local payload = {
		Action = action,
		MousePosition = lockedPosition or mouse.Hit.Position,
	}
	local lockedTargetPayload = getLockedTargetPayload()
	if lockedTargetPayload then
		for key, value in pairs(lockedTargetPayload) do
			payload[key] = value
		end
	end

	return payload
end

local function requestM1()
	combatRequest:FireServer(buildTargetedPayload("M1"))
end

local function getDashMoveDirection()
	local character = getCharacter()
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return nil
	end

	local moveDirection = humanoid.MoveDirection
	if moveDirection.Magnitude <= 0.01 then
		return nil
	end

	return moveDirection.Unit
end

local function requestDash()
	combatRequest:FireServer({
		Action = "Dash",
		MoveDirection = getDashMoveDirection(),
	})
end

local function requestDirectedDash(moveDirection)
	combatRequest:FireServer({
		Action = "Dash",
		MoveDirection = moveDirection or getDashMoveDirection(),
	})
end

local function requestRunState(enabled)
	combatRequest:FireServer({
		Action = "SetRun",
		Enabled = enabled == true,
	})
end

local function isDirectionalDashRunBlocked()
	return getKitId() == "Sans" and getMode() == "Telekinesis"
end

local function getDirectionalDashVector(keyCode)
	local camera = Workspace.CurrentCamera
	local character = getCharacter()
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local forward = camera and Vector3.new(camera.CFrame.LookVector.X, 0, camera.CFrame.LookVector.Z)
	if not forward or forward.Magnitude <= 0.01 then
		forward = root and Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z) or Vector3.zAxis
	end
	forward = forward.Unit

	local right = camera and Vector3.new(camera.CFrame.RightVector.X, 0, camera.CFrame.RightVector.Z)
	if not right or right.Magnitude <= 0.01 then
		right = root and Vector3.new(root.CFrame.RightVector.X, 0, root.CFrame.RightVector.Z) or Vector3.xAxis
	end
	right = right.Unit

	if keyCode == Enum.KeyCode.W then
		return forward
	elseif keyCode == Enum.KeyCode.S then
		return -forward
	elseif keyCode == Enum.KeyCode.D then
		return right
	elseif keyCode == Enum.KeyCode.A then
		return -right
	end

	return nil
end

local function stopRun(keyCode)
	if activeRunKeyCode and (keyCode == nil or keyCode == activeRunKeyCode) then
		activeRunKeyCode = nil
		requestRunState(false)
	end
end

local function handleDirectionalDashRunKeyCode(keyCode)
	if isDirectionalDashRunBlocked() then
		return false
	end

	if keyCode ~= Enum.KeyCode.W and keyCode ~= Enum.KeyCode.A and keyCode ~= Enum.KeyCode.S and keyCode ~= Enum.KeyCode.D then
		return false
	end

	local pressedAt = os.clock()
	local lastTapAt = movementTapTimes[keyCode] or 0
	movementTapTimes[keyCode] = pressedAt
	movementHeld[keyCode] = true

	if pressedAt - lastTapAt <= (Constants.DOUBLE_TAP_DASH_WINDOW or 0.3) then
		activeRunKeyCode = keyCode
		requestDirectedDash(getDirectionalDashVector(keyCode))
		requestRunState(true)
		movementTapTimes[keyCode] = 0
	end

	return false
end

local function isDirectionalMovementKey(keyCode)
	return keyCode == Enum.KeyCode.W
		or keyCode == Enum.KeyCode.A
		or keyCode == Enum.KeyCode.S
		or keyCode == Enum.KeyCode.D
end

local function handleDirectionalDashRunAction(_, inputState, inputObject)
	if playerGui:GetAttribute(Constants.MENU_ATTRIBUTE) or UserInputService:GetFocusedTextBox() then
		return Enum.ContextActionResult.Pass
	end

	local keyCode = inputObject and inputObject.KeyCode or Enum.KeyCode.Unknown
	if not isDirectionalMovementKey(keyCode) then
		return Enum.ContextActionResult.Pass
	end

	if inputState == Enum.UserInputState.Begin then
		handleDirectionalDashRunKeyCode(keyCode)
	elseif inputState == Enum.UserInputState.End then
		movementHeld[keyCode] = nil
		stopRun(keyCode)
	end

	return Enum.ContextActionResult.Pass
end

local function requestSwitchMode(direction)
	combatRequest:FireServer({Action = "SwitchMode", Direction = direction})
end

local function requestBlockStart()
	if not blocking then
		blocking = true
		combatRequest:FireServer({Action = "BlockStart"})
	end
end

local function requestBlockEnd()
	if blocking then
		blocking = false
		combatRequest:FireServer({Action = "BlockEnd"})
	end
end

local function requestAbility(slot)
	local bypassCooldown = slot == "X" and getKitId() == "Sans" and getMode() == "Blasters" and hasPendingBlasterShots()
	if not slot or (not canUse(slot) and not bypassCooldown) then
		return
	end

	local payload = buildTargetedPayload("Ability")
	payload.Slot = slot
	combatRequest:FireServer(payload)
end

local function requestTelekinesisMove(direction)
	if not direction then
		return
	end

	combatRequest:FireServer({
		Action = "TelekinesisMove",
		Direction = direction,
		MousePosition = getLockedPosition() or mouse.Hit.Position,
	})
end

local function respondToDuel(accepted)
	combatRequest:FireServer({
		Action = "RespondToDuel",
		Accepted = accepted == true,
	})
	duelPromptActive = false
end

local function startHeldBonesAbility()
	if heldAbilityTokens.Z then
		return
	end

	local sansKit = CharacterKits.Sans
	local bonesAbility = sansKit and sansKit.Abilities and sansKit.Abilities.Bones and sansKit.Abilities.Bones.Z
	local volleyInterval = (bonesAbility and bonesAbility.HoldInterval) or (bonesAbility and bonesAbility.Cooldown) or 0.4
	local maxHoldDuration = (bonesAbility and bonesAbility.MaxHoldDuration) or 2.5
	local token = (heldAbilityTokens.Z or 0) + 1
	heldAbilityTokens.Z = token
	local startedAt = os.clock()
	local nextVolleyAt = startedAt
	requestAbility("Z")
	nextVolleyAt += volleyInterval

	task.spawn(function()
		while heldAbilityTokens.Z == token and os.clock() - startedAt < maxHoldDuration do
			if playerGui:GetAttribute(Constants.MENU_ATTRIBUTE) then
				break
			end
			if getKitId() ~= "Sans" or getMode() ~= "Bones" then
				break
			end

			local nowTime = os.clock()
			if nowTime >= nextVolleyAt then
				requestAbility("Z")
				nextVolleyAt += volleyInterval
			else
				task.wait(math.min(0.05, math.max(0.01, nextVolleyAt - nowTime)))
			end
		end

		if heldAbilityTokens.Z == token then
			heldAbilityTokens.Z = nil
			combatRequest:FireServer({
				Action = "EndHeldAbility",
				Slot = "Z",
			})
		end
	end)
end

local function beginAbilityInput(slot)
	if not slot then
		return
	end

	if slot == "Z" and getKitId() == "Sans" and getMode() == "Bones" then
		startHeldBonesAbility()
		return
	end

	requestAbility(slot)
end

local function endAbilityInput(slot)
	if slot ~= "Z" or not heldAbilityTokens.Z then
		return
	end

	combatRequest:FireServer({
		Action = "EndHeldAbility",
		Slot = "Z",
	})
	heldAbilityTokens.Z = nil
	stopHeldBonesAnimation()
end

_G.JudgementDividedControls = {
	M1 = requestM1,
	Dash = requestDash,
	BlockStart = requestBlockStart,
	BlockEnd = requestBlockEnd,
	BeginAbilityInput = beginAbilityInput,
	EndAbilityInput = endAbilityInput,
	RespondToDuel = respondToDuel,
	TelekinesisMove = requestTelekinesisMove,
	SwitchModePrevious = function()
		requestSwitchMode("Previous")
	end,
	SwitchModeNext = function()
		requestSwitchMode("Next")
	end,
	UseAbility = requestAbility,
}

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if playerGui:GetAttribute(Constants.MENU_ATTRIBUTE) then
		return
	end

	local allowProcessedMovementKey = input.UserInputType == Enum.UserInputType.Keyboard and isDirectionalMovementKey(input.KeyCode)
	if UserInputService:GetFocusedTextBox() then
		return
	end

	if gameProcessed and not allowProcessedMovementKey then
		return
	end

	if input.UserInputType == Enum.UserInputType.Touch then
		if isTouchOverGuiButton(input.Position) then
			return
		end
		touchAttackCandidates[input] = {
			StartedAt = os.clock(),
			StartPosition = Vector2.new(input.Position.X, input.Position.Y),
			Cancelled = false,
		}
		return
	end

	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		requestM1()
		return
	end

	if input.KeyCode == Enum.KeyCode.LeftShift then
		requestDash()
		return
	end

	if input.KeyCode == Enum.KeyCode.Q then
		requestSwitchMode("Previous")
		return
	end

	if input.KeyCode == Enum.KeyCode.E then
		requestSwitchMode("Next")
		return
	end

	if input.KeyCode == Enum.KeyCode.F then
		requestBlockStart()
		return
	end

	if duelPromptActive and input.KeyCode == Enum.KeyCode.Y then
		respondToDuel(true)
		return
	elseif duelPromptActive and input.KeyCode == Enum.KeyCode.N then
		respondToDuel(false)
		return
	end

	if getKitId() == "Sans" and getMode() == "Telekinesis" then
		local moveKeys = {
			[Enum.KeyCode.W] = "W",
			[Enum.KeyCode.A] = "A",
			[Enum.KeyCode.S] = "S",
			[Enum.KeyCode.D] = "D",
			[Enum.KeyCode.Space] = "Space",
		}

		local direction = moveKeys[input.KeyCode]
		if direction then
			requestTelekinesisMove(direction)
			return
		end
	end

	local slot = abilityKeys[input.KeyCode]
	if slot then
		beginAbilityInput(slot)
	end
end)

UserInputService.InputChanged:Connect(function(input)
	if input.UserInputType ~= Enum.UserInputType.Touch then
		return
	end

	local candidate = touchAttackCandidates[input]
	if not candidate or candidate.Cancelled then
		return
	end

	local currentPosition = Vector2.new(input.Position.X, input.Position.Y)
	if (currentPosition - candidate.StartPosition).Magnitude > MOBILE_TAP_ATTACK_MAX_MOVEMENT then
		candidate.Cancelled = true
	end
end)

UserInputService.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.Touch then
		local candidate = touchAttackCandidates[input]
		touchAttackCandidates[input] = nil
		if not candidate or candidate.Cancelled or playerGui:GetAttribute(Constants.MENU_ATTRIBUTE) then
			return
		end

		if os.clock() - candidate.StartedAt <= MOBILE_TAP_ATTACK_MAX_DURATION then
			requestM1()
		end
		return
	end

	if movementHeld[input.KeyCode] then
		movementHeld[input.KeyCode] = nil
		stopRun(input.KeyCode)
	end

	if input.KeyCode == Enum.KeyCode.F then
		requestBlockEnd()
	elseif input.KeyCode == Enum.KeyCode.One then
		endAbilityInput("Z")
	end
end)

UserInputService.JumpRequest:Connect(function()
	if not isJumpSuppressedLocally() then
		return
	end

	local character = getCharacter()
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end

	humanoid.Jump = false
end)

playerGui:GetAttributeChangedSignal(Constants.MENU_ATTRIBUTE):Connect(function()
	if playerGui:GetAttribute(Constants.MENU_ATTRIBUTE) then
		stopRun()
	end
end)

player.CharacterAdded:Connect(function()
	table.clear(movementTapTimes)
	table.clear(movementHeld)
	activeRunKeyCode = nil
end)

ContextActionService:BindAction("JudgementDividedDirectionalDashRun", handleDirectionalDashRunAction, false,
	Enum.KeyCode.W,
	Enum.KeyCode.A,
	Enum.KeyCode.S,
	Enum.KeyCode.D
)

combatState.OnClientEvent:Connect(function(payload)
	if typeof(payload) ~= "table" then
		return
	end

	if payload.Type == "Ability" and payload.Player == player.UserId then
		cooldowns[payload.CooldownKey or getCooldownKey(payload.Slot)] = os.clock() + payload.Cooldown
		if payload.KitId == "Sans" and payload.Mode == "Blasters" and payload.Slot == "Z" then
			local kit = CharacterKits.Sans
			playAnimationById(kit and kit.AnimationIds and kit.AnimationIds.BlasterSummon)
		elseif payload.KitId == "Sans" and payload.Mode == "Telekinesis" and payload.Slot == "Z" then
			playSansTeleStartupAnimation()
		elseif payload.KitId == "Sans" and payload.Mode == "Bones" then
			playSansBonesAnimation(payload.Slot)
		end
		notify(string.format("%s used", payload.Name))
	elseif payload.Type == "CooldownSet" and payload.Player == player.UserId then
		cooldowns[payload.CooldownKey or getCooldownKey(payload.Slot)] = os.clock() + payload.Cooldown
		if payload.Slot == "Z" then
			stopHeldBonesAnimation()
		end
	elseif payload.Type == "SystemMessage" then
		notify(payload.Text)
	elseif payload.Type == "ModeChanged" then
		stopHeldBonesAnimation()
		notify(string.format("Mode: %s", payload.Mode))
	elseif payload.Type == "KitChanged" then
		stopHeldBonesAnimation()
		notify(string.format("Character: %s", payload.KitId))
	elseif payload.Type == "CounterReady" then
		notify("Counter ready")
	elseif payload.Type == "CounterTriggered" and payload.Player == player.UserId then
		notify("Counter landed")
	elseif payload.Type == "SansDodged" and payload.Player == player.UserId then
		playSansDodgeAnimation(payload.Direction)
	elseif payload.Type == "TelekinesisGrab" then
		notify("Target gripped")
	elseif payload.Type == "TelekinesisCast" and payload.Player == player.UserId then
		playSansTeleAnimation(payload.Direction)
	elseif payload.Type == "DuelRequested" then
		duelPromptActive = true
		notify(string.format("%s challenged you. Press Y to accept or N to decline.", payload.From))
	elseif payload.Type == "DuelCountdown" then
		notify(string.format("Duel vs %s starts in %d", payload.Opponent or "opponent", payload.Value))
	elseif payload.Type == "DuelEnded" then
		duelPromptActive = false
		notify(string.format("%s defeated %s", payload.Winner, payload.Loser))
	end
end)

player.CharacterAdded:Connect(function()
	stopHeldBonesAnimation()
end)

player.CharacterAdded:Connect(function(character)
	hookCharacterDodge(character)
end)

if player.Character then
	hookCharacterDodge(player.Character)
end
