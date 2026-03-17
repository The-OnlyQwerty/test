local Debris = game:GetService("Debris")
local TweenService = game:GetService("TweenService")

local EffectService = {}
EffectService.__index = EffectService

local function createPart(folder, props)
	local part = Instance.new("Part")
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Locked = true
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	for key, value in pairs(props) do
		part[key] = value
	end
	part.Parent = folder
	return part
end

local function createAttachedPart(parent, props)
	local part = Instance.new("Part")
	part.Anchored = false
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Locked = true
	part.Massless = true
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	for key, value in pairs(props) do
		part[key] = value
	end
	part.Parent = parent
	return part
end

function EffectService.new()
	local folder = workspace:FindFirstChild("CombatEffects")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "CombatEffects"
		folder.Parent = workspace
	end

	return setmetatable({
		Folder = folder,
	}, EffectService)
end

function EffectService:FadePart(part, duration, finalTransparency, finalSize)
	local goal = {
		Transparency = finalTransparency or 1,
	}
	if finalSize then
		goal.Size = finalSize
	end

	local tween = TweenService:Create(part, TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), goal)
	tween:Play()
	Debris:AddItem(part, duration + 0.05)
end

function EffectService:SpawnBlockWall(root, color)
	local wall = createPart(self.Folder, {
		Name = "BlockWall",
		Material = Enum.Material.Neon,
		Color = color or Color3.fromRGB(235, 235, 245),
		Transparency = 0.2,
		Size = Vector3.new(11, 8, 1.2),
		CFrame = root.CFrame * CFrame.new(0, 1.5, -4),
	})
	Instance.new("SpecialMesh", wall).MeshType = Enum.MeshType.Brick
	self:FadePart(wall, 0.22, 1, Vector3.new(13, 9, 1.4))
end

function EffectService:SpawnBlockOutline(root, color)
	local tone = color or Color3.fromRGB(170, 215, 255)
	local outline = createPart(self.Folder, {
		Name = "BlockOutline",
		Material = Enum.Material.ForceField,
		Color = tone,
		Transparency = 0.35,
		Size = Vector3.new(5.2, 7.4, 4.4),
		CFrame = root.CFrame * CFrame.new(0, 2.2, 0),
	})
	self:FadePart(outline, 0.18, 1, Vector3.new(6.1, 8.2, 5.1))

	for index = 1, 4 do
		local angle = math.rad((index - 1) * 90)
		local offset = Vector3.new(math.cos(angle) * 1.9, 2.2, math.sin(angle) * 1.6)
		local shard = createPart(self.Folder, {
			Name = "BlockShard",
			Material = Enum.Material.Neon,
			Color = (index % 2 == 0) and Color3.fromRGB(245, 245, 255) or tone,
			Transparency = 0.18,
			Size = Vector3.new(0.45, 3.6, 0.45),
			CFrame = CFrame.new(root.Position + offset),
		})
		self:FadePart(shard, 0.16, 1, Vector3.new(0.7, 4.3, 0.7))
	end
end

function EffectService:CreateBlockAura(root, color)
	local tone = color or Color3.fromRGB(170, 215, 255)
	local model = Instance.new("Model")
	model.Name = "PersistentBlockAura"
	model:SetAttribute("Active", true)
	model.Parent = self.Folder

	local outline = createAttachedPart(model, {
		Name = "AuraShell",
		Material = Enum.Material.ForceField,
		Color = tone,
		Transparency = 0.58,
		Size = Vector3.new(5.1, 7.2, 4.2),
		CFrame = root.CFrame * CFrame.new(0, 2.2, 0),
	})

	local weld = Instance.new("WeldConstraint")
	weld.Part0 = root
	weld.Part1 = outline
	weld.Parent = outline

	local shards = {}
	for index = 1, 4 do
		local angle = math.rad((index - 1) * 90)
		local offset = Vector3.new(math.cos(angle) * 1.85, 2.2, math.sin(angle) * 1.55)
		local shard = createAttachedPart(model, {
			Name = "AuraShard",
			Material = Enum.Material.Neon,
			Color = (index % 2 == 0) and Color3.fromRGB(245, 245, 255) or tone,
			Transparency = 0.42,
			Size = Vector3.new(0.42, 3.2, 0.42),
			CFrame = CFrame.new(root.Position + offset),
		})
		local shardWeld = Instance.new("WeldConstraint")
		shardWeld.Part0 = root
		shardWeld.Part1 = shard
		shardWeld.Parent = shard
		table.insert(shards, shard)
	end

	task.spawn(function()
		local low = 0.62
		local high = 0.3
		local toHigh = true
		while model.Parent and model:GetAttribute("Active") do
			local goalTransparency = toHigh and high or low
			toHigh = not toHigh

			local tweenInfo = TweenInfo.new(0.28, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
			TweenService:Create(outline, tweenInfo, {Transparency = goalTransparency}):Play()
			for _, shard in ipairs(shards) do
				TweenService:Create(shard, tweenInfo, {Transparency = math.max(0.18, goalTransparency - 0.1)}):Play()
			end

			task.wait(0.28)
		end
	end)

	return model
end

function EffectService:DestroyBlockAura(aura)
	if not aura or not aura.Parent then
		return
	end

	aura:SetAttribute("Active", false)
	for _, child in ipairs(aura:GetDescendants()) do
		if child:IsA("BasePart") then
			TweenService:Create(child, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				Transparency = 1,
				Size = child.Size + Vector3.new(0.2, 0.3, 0.2),
			}):Play()
		end
	end
	Debris:AddItem(aura, 0.22)
end

function EffectService:SpawnSlash(cframe, size, color, duration)
	local slash = createPart(self.Folder, {
		Name = "Slash",
		Material = Enum.Material.Neon,
		Color = color,
		Transparency = 0.18,
		Size = size,
		CFrame = cframe,
	})
	self:FadePart(slash, duration or 0.18, 1, size + Vector3.new(1.5, 1.5, 1.5))
end

function EffectService:SpawnBoneLine(startPos, endPos, color)
	local delta = endPos - startPos
	local length = math.max(3, delta.Magnitude)
	local cf = CFrame.lookAt(startPos:Lerp(endPos, 0.5), endPos)
	local bone = createPart(self.Folder, {
		Name = "BoneLine",
		Material = Enum.Material.Neon,
		Color = color or Color3.fromRGB(232, 232, 255),
		Transparency = 0.08,
		Size = Vector3.new(1, 1, length),
		CFrame = cf,
	})
	self:FadePart(bone, 0.3, 1, Vector3.new(1.5, 1.5, length + 4))
end

function EffectService:SpawnBoneBurst(position, radius, color)
	for index = 1, 6 do
		local angle = math.rad((360 / 6) * index)
		local offset = Vector3.new(math.cos(angle) * radius, 0, math.sin(angle) * radius)
		local bone = createPart(self.Folder, {
			Name = "BoneBurst",
			Material = Enum.Material.Neon,
			Color = color or Color3.fromRGB(240, 240, 255),
			Transparency = 0.1,
			Size = Vector3.new(0.8, 5.5, 0.8),
			CFrame = CFrame.new(position + offset + Vector3.new(0, 2.75, 0)),
		})
		self:FadePart(bone, 0.4, 1, bone.Size + Vector3.new(0.2, 1.4, 0.2))
	end
end

function EffectService:SpawnWaveWall(cframe, size, color)
	local wall = createPart(self.Folder, {
		Name = "WaveWall",
		Material = Enum.Material.ForceField,
		Color = color,
		Transparency = 0.15,
		Size = size,
		CFrame = cframe,
	})
	self:FadePart(wall, 0.28, 1, size + Vector3.new(3, 2, 1))
end

function EffectService:SpawnZone(position, radius, color)
	local zone = createPart(self.Folder, {
		Name = "Zone",
		Shape = Enum.PartType.Ball,
		Material = Enum.Material.ForceField,
		Color = color,
		Transparency = 0.45,
		Size = Vector3.new(radius * 2, radius * 2, radius * 2),
		CFrame = CFrame.new(position),
	})
	self:FadePart(zone, 0.45, 1, zone.Size + Vector3.new(6, 6, 6))
end

function EffectService:SpawnCounterFlash(position)
	local flash = createPart(self.Folder, {
		Name = "CounterFlash",
		Shape = Enum.PartType.Ball,
		Material = Enum.Material.Neon,
		Color = Color3.fromRGB(255, 70, 70),
		Transparency = 0.2,
		Size = Vector3.new(3, 3, 3),
		CFrame = CFrame.new(position),
	})
	self:FadePart(flash, 0.3, 1, Vector3.new(12, 12, 12))
end

function EffectService:SpawnBlaster(position)
	local blaster = createPart(self.Folder, {
		Name = "Blaster",
		Material = Enum.Material.Neon,
		Color = Color3.fromRGB(215, 235, 255),
		Transparency = 0.05,
		Size = Vector3.new(2.5, 2.5, 4),
		CFrame = CFrame.new(position),
	})
	self:FadePart(blaster, 1.1, 0.65)
end

function EffectService:SpawnBeam(startPos, endPos, color)
	local delta = endPos - startPos
	local length = math.max(4, delta.Magnitude)
	local beam = createPart(self.Folder, {
		Name = "Beam",
		Material = Enum.Material.Neon,
		Color = color or Color3.fromRGB(124, 200, 255),
		Transparency = 0.04,
		Size = Vector3.new(1.4, 1.4, length),
		CFrame = CFrame.lookAt(startPos:Lerp(endPos, 0.5), endPos),
	})
	self:FadePart(beam, 0.22, 1, Vector3.new(3, 3, length + 6))
end

function EffectService:SpawnSwordRain(position, color)
	local sword = createPart(self.Folder, {
		Name = "SwordRain",
		Material = Enum.Material.Metal,
		Color = color or Color3.fromRGB(28, 28, 35),
		Transparency = 0.05,
		Size = Vector3.new(0.7, 9, 0.9),
		CFrame = CFrame.new(position + Vector3.new(0, 8, 0)) * CFrame.Angles(0, 0, math.rad(10)),
	})
	self:FadePart(sword, 0.5, 1, sword.Size)
end

return EffectService
