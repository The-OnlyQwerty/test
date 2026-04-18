local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local localPlayer = Players.LocalPlayer
local isTouchDevice = UserInputService.TouchEnabled
local dummyWatchers = {}
local overheadRescanElapsed = 0

local function hasBarGui(character)
	local head = character and character:FindFirstChild("Head")
	return head and head:FindFirstChild("OverheadHealth") ~= nil
end

local function createBarGui(character)
	local head = character:FindFirstChild("Head") or character:WaitForChild("Head", 5)
	local humanoid = character:FindFirstChildOfClass("Humanoid") or character:WaitForChild("Humanoid", 5)
	if not head or not humanoid then
		return
	end

	local existing = head:FindFirstChild("OverheadHealth")
	if existing then
		existing:Destroy()
	end

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "OverheadHealth"
	billboard.Size = isTouchDevice and UDim2.fromOffset(118, 30) or UDim2.fromOffset(130, 34)
	billboard.StudsOffset = isTouchDevice and Vector3.new(0, 2.75, 0) or Vector3.new(0, 3.5, 0)
	billboard.AlwaysOnTop = true
	billboard.MaxDistance = 120
	billboard.Parent = head

	local nameLabel = Instance.new("TextLabel")
	nameLabel.Name = "NameLabel"
	nameLabel.Position = UDim2.new(0, 0, 0, 0)
	nameLabel.Size = UDim2.new(1, 0, 0, 14)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Font = Enum.Font.GothamBold
	nameLabel.Text = character:GetAttribute("DisplayName") or (Players:GetPlayerFromCharacter(character) and Players:GetPlayerFromCharacter(character).DisplayName) or character.Name
	nameLabel.TextColor3 = Color3.fromRGB(245, 245, 245)
	nameLabel.TextStrokeTransparency = 0.4
	nameLabel.TextSize = isTouchDevice and 10 or 12
	nameLabel.Parent = billboard

	local back = Instance.new("Frame")
	back.Position = isTouchDevice and UDim2.new(0, 18, 0, 16) or UDim2.new(0, 20, 0, 18)
	back.Size = isTouchDevice and UDim2.new(1, -36, 0, 9) or UDim2.new(1, -40, 0, 10)
	back.BackgroundColor3 = Color3.fromRGB(18, 18, 22)
	back.BorderSizePixel = 0
	back.Parent = billboard

	local backCorner = Instance.new("UICorner")
	backCorner.CornerRadius = UDim.new(1, 0)
	backCorner.Parent = back

	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.fromScale(1, 1)
	fill.BackgroundColor3 = Color3.fromRGB(225, 70, 70)
	fill.BorderSizePixel = 0
	fill.Parent = back

	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = UDim.new(1, 0)
	fillCorner.Parent = fill

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(240, 240, 240)
	stroke.Thickness = 1
	stroke.Parent = back

	local function update()
		local ratio = math.clamp(humanoid.Health / math.max(humanoid.MaxHealth, 1), 0, 1)
		fill.Size = UDim2.new(ratio, 0, 1, 0)
		fill.BackgroundColor3 = ratio > 0.5 and Color3.fromRGB(82, 198, 104) or (ratio > 0.25 and Color3.fromRGB(232, 190, 70) or Color3.fromRGB(225, 70, 70))
		nameLabel.Text = character:GetAttribute("DisplayName") or (Players:GetPlayerFromCharacter(character) and Players:GetPlayerFromCharacter(character).DisplayName) or character.Name
	end

	humanoid.HealthChanged:Connect(update)
	humanoid:GetPropertyChangedSignal("MaxHealth"):Connect(update)
	update()
end

local function hookDummy(dummy)
	if not dummy:IsA("Model") or dummyWatchers[dummy] then
		return
	end

	local function tryCreate()
		if dummy.Parent and dummy:GetAttribute("IsTargetDummy") and not hasBarGui(dummy) then
			createBarGui(dummy)
		end
	end

	dummyWatchers[dummy] = {
		AttributeConnection = dummy:GetAttributeChangedSignal("IsTargetDummy"):Connect(tryCreate),
		AncestryConnection = dummy.AncestryChanged:Connect(function(_, parent)
			if parent == nil then
				local watcher = dummyWatchers[dummy]
				if watcher then
					if watcher.AttributeConnection then
						watcher.AttributeConnection:Disconnect()
					end
					if watcher.AncestryConnection then
						watcher.AncestryConnection:Disconnect()
					end
					dummyWatchers[dummy] = nil
				end
			end
		end),
	}

	tryCreate()
end

local function hookPlayer(player)
	if player == localPlayer then
		return
	end

	player.CharacterAdded:Connect(createBarGui)
	if player.Character then
		createBarGui(player.Character)
	end
end

for _, player in ipairs(Players:GetPlayers()) do
	hookPlayer(player)
end

Players.PlayerAdded:Connect(hookPlayer)

local function hookNpcFolder(folder)
	for _, child in ipairs(folder:GetChildren()) do
		hookDummy(child)
	end
	folder.ChildAdded:Connect(hookDummy)
end

local function refreshDummyBars()
	local folder = workspace:FindFirstChild("CombatNPCs")
	if not folder then
		return
	end

	for _, child in ipairs(folder:GetChildren()) do
		if child:IsA("Model") and child:GetAttribute("IsTargetDummy") and not hasBarGui(child) then
			createBarGui(child)
		end
	end
end

local npcFolder = workspace:FindFirstChild("CombatNPCs")
if npcFolder then
	hookNpcFolder(npcFolder)
else
	workspace.ChildAdded:Connect(function(child)
		if child.Name == "CombatNPCs" and child:IsA("Folder") then
			hookNpcFolder(child)
		end
	end)
end

RunService.Heartbeat:Connect(function(deltaTime)
	overheadRescanElapsed += deltaTime
	if overheadRescanElapsed < 1 then
		return
	end

	overheadRescanElapsed = 0
	refreshDummyBars()
end)
