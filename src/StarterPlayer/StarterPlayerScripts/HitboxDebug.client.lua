local Players = game:GetService("Players")
local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared:WaitForChild("Constants"))

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local combatState = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("CombatState")

local function renderDebug(payload)
	local part = Instance.new("Part")
	part.Name = "HitboxDebug"
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Material = Enum.Material.ForceField
	part.Transparency = 0.72
	part.Color = payload.Color or Color3.fromRGB(255, 90, 90)
	part.Size = payload.Size or Vector3.new(4, 4, 4)
	part.CFrame = payload.CFrame or CFrame.new()
	part.Shape = payload.Shape == "Sphere" and Enum.PartType.Ball or Enum.PartType.Block
	part.Parent = workspace
	Debris:AddItem(part, payload.Duration or 0.15)
end

combatState.OnClientEvent:Connect(function(payload)
	if not playerGui:GetAttribute(Constants.HITBOX_ATTRIBUTE) or typeof(payload) ~= "table" then
		return
	end

	if payload.Type == "HitboxDebug" then
		renderDebug(payload)
	end
end)
