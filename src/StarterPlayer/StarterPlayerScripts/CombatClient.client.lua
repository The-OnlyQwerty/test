local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")

local Constants = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Constants"))

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

local function notify(text)
	pcall(function()
		StarterGui:SetCore("SendNotification", {
			Title = "Judgement Divided",
			Text = text,
			Duration = 1.5,
		})
	end)
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

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed or playerGui:GetAttribute(Constants.MENU_ATTRIBUTE) then
		return
	end

	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		combatRequest:FireServer({Action = "M1"})
		return
	end

	if input.KeyCode == Enum.KeyCode.LeftShift then
		combatRequest:FireServer({Action = "Dash"})
		return
	end

	if input.KeyCode == Enum.KeyCode.Q then
		combatRequest:FireServer({Action = "SwitchMode", Direction = "Previous"})
		return
	end

	if input.KeyCode == Enum.KeyCode.E then
		combatRequest:FireServer({Action = "SwitchMode", Direction = "Next"})
		return
	end

	if input.KeyCode == Enum.KeyCode.F and not blocking then
		blocking = true
		combatRequest:FireServer({Action = "BlockStart"})
		return
	end

	if duelPromptActive and input.KeyCode == Enum.KeyCode.Y then
		combatRequest:FireServer({Action = "RespondToDuel", Accepted = true})
		duelPromptActive = false
		return
	elseif duelPromptActive and input.KeyCode == Enum.KeyCode.N then
		combatRequest:FireServer({Action = "RespondToDuel", Accepted = false})
		duelPromptActive = false
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
			combatRequest:FireServer({
				Action = "TelekinesisMove",
				Direction = direction,
			})
		end
	end

	local slot = abilityKeys[input.KeyCode]
	local bypassCooldown = slot == "X" and getKitId() == "Sans" and getMode() == "Blasters"
	if slot and (canUse(slot) or bypassCooldown) then
		local lockedPosition = getLockedPosition()
		combatRequest:FireServer({
			Action = "Ability",
			Slot = slot,
			MousePosition = lockedPosition or mouse.Hit.Position,
		})
	end
end)

UserInputService.InputEnded:Connect(function(input)
	if input.KeyCode == Enum.KeyCode.F and blocking then
		blocking = false
		combatRequest:FireServer({Action = "BlockEnd"})
	end
end)

combatState.OnClientEvent:Connect(function(payload)
	if typeof(payload) ~= "table" then
		return
	end

	if payload.Type == "Ability" and payload.Player == player.UserId then
		cooldowns[payload.CooldownKey or getCooldownKey(payload.Slot)] = os.clock() + payload.Cooldown
		notify(string.format("%s used", payload.Name))
	elseif payload.Type == "HitConfirm" and payload.Attacker == player.UserId then
		notify(string.format("Hit for %d", payload.Damage))
	elseif payload.Type == "SystemMessage" then
		notify(payload.Text)
	elseif payload.Type == "ModeChanged" then
		notify(string.format("Mode: %s", payload.Mode))
	elseif payload.Type == "KitChanged" then
		notify(string.format("Character: %s", payload.KitId))
	elseif payload.Type == "CounterReady" then
		notify("Counter ready")
	elseif payload.Type == "CounterTriggered" and payload.Player == player.UserId then
		notify("Counter landed")
	elseif payload.Type == "TelekinesisGrab" then
		notify("Target gripped")
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
