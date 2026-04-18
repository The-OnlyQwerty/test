local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
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

local BLASTER_TEMPLATE_NAMES = {
	"GasterBlaster",
	"Gaster Blaster",
	"SansGasterBlaster",
	"Sans Gaster Blaster",
}

local function findNamedDescendant(parent, targetNames)
	if not parent then
		return nil
	end

	for _, name in ipairs(targetNames) do
		local direct = parent:FindFirstChild(name)
		if direct then
			return direct
		end
	end

	local descendants = parent:GetDescendants()
	for _, name in ipairs(targetNames) do
		for _, descendant in ipairs(descendants) do
			if descendant.Name == name then
				return descendant
			end
		end
	end

	return nil
end

local function getBlasterTemplate(templateNames)
	local candidates = {
		ReplicatedStorage,
		ServerStorage,
		workspace,
		ReplicatedStorage:FindFirstChild("Assets"),
		ReplicatedStorage:FindFirstChild("Effects"),
		ReplicatedStorage:FindFirstChild("Models"),
		ServerStorage:FindFirstChild("Assets"),
		ServerStorage:FindFirstChild("Effects"),
		ServerStorage:FindFirstChild("Models"),
		workspace:FindFirstChild("Assets"),
		workspace:FindFirstChild("Effects"),
		workspace:FindFirstChild("Models"),
	}
	local names = templateNames or BLASTER_TEMPLATE_NAMES

	for _, candidate in ipairs(candidates) do
		local template = findNamedDescendant(candidate, names)
		if template and (template:IsA("Model") or template:IsA("BasePart") or template:IsA("Accessory")) then
			return template
		end
	end

	return nil
end

local function materializeBlasterTemplate(template)
	if not template then
		return nil
	end

	if template:IsA("Model") then
		return template:Clone()
	end

	local model = Instance.new("Model")
	model.Name = template.Name
	local clone = template:Clone()
	clone.Parent = model
	return model
end

local function getModelRoot(model)
	if model.PrimaryPart then
		return model.PrimaryPart
	end

	return model:FindFirstChildWhichIsA("BasePart", true)
end

local function normalizeBlasterModel(model, anchored)
	local rootPart = getModelRoot(model)
	if not rootPart then
		return nil
	end

	model.PrimaryPart = rootPart
	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("BasePart") then
			descendant.Anchored = anchored
			descendant.CanCollide = false
			descendant.CanQuery = false
			descendant.CanTouch = false
			descendant.Locked = true
			descendant.Massless = not anchored
		end
	end

	if not anchored then
		for _, descendant in ipairs(model:GetDescendants()) do
			if descendant:IsA("BasePart") and descendant ~= rootPart and not descendant:FindFirstChild("BlasterRootWeld") then
				local weld = Instance.new("WeldConstraint")
				weld.Name = "BlasterRootWeld"
				weld.Part0 = rootPart
				weld.Part1 = descendant
				weld.Parent = descendant
			end
		end
	end

	return rootPart
end

local function cloneBlasterModel(parent, anchored, templateNames)
	local template = getBlasterTemplate(templateNames)
	if not template then
		return nil, nil, nil
	end

	local model = materializeBlasterTemplate(template)
	if not model then
		return nil, nil, nil
	end
	model.Parent = parent

	local rootPart = normalizeBlasterModel(model, anchored)
	if not rootPart then
		model:Destroy()
		return nil, nil, nil
	end

	return model, rootPart, template.Name
end

local function tintModel(model, color)
	if not model or not color then
		return
	end

	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("BasePart") then
			descendant.Color = color
		end
	end
end

local function stylizeAfterimagePart(part, color, transparency)
	if not part then
		return
	end

	part.Material = Enum.Material.Neon
	part.Color = color
	part.Transparency = transparency

	if part:IsA("MeshPart") then
		part.TextureID = ""
	end

	for _, child in ipairs(part:GetDescendants()) do
		if child:IsA("Decal") or child:IsA("Texture") or child:IsA("SurfaceAppearance") then
			child:Destroy()
		elseif child:IsA("SpecialMesh") then
			child.TextureId = ""
		end
	end
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

function EffectService:SpawnCharacterAfterimage(character, rootCFrame, color, transparency, duration)
	if not character or not rootCFrame then
		return nil
	end

	local sourceRoot = character:FindFirstChild("HumanoidRootPart")
	if not sourceRoot then
		return nil
	end

	local model = Instance.new("Model")
	model.Name = "Afterimage"
	model.Parent = self.Folder

	local tone = color or Color3.fromRGB(245, 245, 255)
	local baseTransparency = transparency or 0.28
	local life = duration or 0.32
	local createdAny = false

	for _, descendant in ipairs(character:GetDescendants()) do
		if descendant:IsA("BasePart") and descendant.Name ~= "HumanoidRootPart" then
			local clone = descendant:Clone()
			if clone:IsA("BasePart") then
				createdAny = true
				clone.Anchored = true
				clone.CanCollide = false
				clone.CanQuery = false
				clone.CanTouch = false
				clone.Locked = true
				clone.Massless = true
				stylizeAfterimagePart(clone, tone, baseTransparency)
				clone.Size = clone.Size + Vector3.new(0.05, 0.05, 0.05)
				local relative = sourceRoot.CFrame:ToObjectSpace(descendant.CFrame)
				clone.CFrame = rootCFrame * relative
				clone.Parent = model

				local tween = TweenService:Create(clone, TweenInfo.new(life, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
					Transparency = 1,
				})
				tween:Play()
			end
		end
	end

	if not createdAny then
		model:Destroy()
		return nil
	end

	local highlight = Instance.new("Highlight")
	highlight.Name = "AfterimageHighlight"
	highlight.Adornee = model
	highlight.DepthMode = Enum.HighlightDepthMode.Occluded
	highlight.FillColor = tone
	highlight.FillTransparency = 0.82
	highlight.OutlineColor = tone
	highlight.OutlineTransparency = 0.18
	highlight.Parent = model

	Debris:AddItem(model, life + 0.05)
	return model
end

function EffectService:CreateAfterimageRing(character, targetRoot, options)
	options = options or {}
	if not character or not targetRoot then
		return nil
	end

	local sourceRoot = character:FindFirstChild("HumanoidRootPart")
	if not sourceRoot then
		return nil
	end

	local tone = options.Color or Color3.fromRGB(245, 245, 255)
	local baseTransparency = options.Transparency or 0.3
	local duration = options.Duration or 5
	local count = math.max(2, options.Count or 6)
	local radius = options.Radius or 2.8
	local rotateSpeed = options.RotateSpeed or 1.8

	local container = Instance.new("Model")
	container.Name = "AfterimageRing"
	container:SetAttribute("Active", true)
	container.Parent = self.Folder

	local rigs = {}

	local function buildRigClone(index)
		local rigModel = Instance.new("Model")
		rigModel.Name = "RingClone" .. tostring(index)
		rigModel.Parent = container

		local parts = {}
		for _, descendant in ipairs(character:GetDescendants()) do
			if descendant:IsA("BasePart") and descendant.Name ~= "HumanoidRootPart" then
				local clone = descendant:Clone()
				clone.Anchored = true
				clone.CanCollide = false
				clone.CanQuery = false
				clone.CanTouch = false
				clone.Locked = true
				clone.Massless = true
				stylizeAfterimagePart(clone, tone, baseTransparency)
				clone.Size = clone.Size + Vector3.new(0.05, 0.05, 0.05)
				clone.Parent = rigModel

				table.insert(parts, {
					Part = clone,
					Relative = sourceRoot.CFrame:ToObjectSpace(descendant.CFrame),
				})
			end
		end

		if #parts == 0 then
			rigModel:Destroy()
			return nil
		end

		local highlight = Instance.new("Highlight")
		highlight.Name = "RingCloneHighlight"
		highlight.Adornee = rigModel
		highlight.DepthMode = Enum.HighlightDepthMode.Occluded
		highlight.FillColor = tone
		highlight.FillTransparency = 0.84
		highlight.OutlineColor = tone
		highlight.OutlineTransparency = 0.22
		highlight.Parent = rigModel

		return {
			Model = rigModel,
			Parts = parts,
			Highlight = highlight,
		}
	end

	for index = 1, count do
		local rig = buildRigClone(index)
		if rig then
			table.insert(rigs, rig)
		end
	end

	if #rigs == 0 then
		container:Destroy()
		return nil
	end

	task.spawn(function()
		local startedAt = os.clock()
		while container.Parent and container:GetAttribute("Active") and targetRoot.Parent and (os.clock() - startedAt) < duration do
			local elapsed = os.clock() - startedAt
			local focusPoint = targetRoot.Position + Vector3.new(0, 1.1, 0)

			for index, rig in ipairs(rigs) do
				local angle = ((index - 1) / #rigs) * (math.pi * 2) + elapsed * rotateSpeed
				local clonePosition = targetRoot.Position + Vector3.new(math.cos(angle) * radius, 0, math.sin(angle) * radius)
				local flatFocusPoint = Vector3.new(focusPoint.X, clonePosition.Y, focusPoint.Z)
				local cloneRootCFrame = CFrame.lookAt(clonePosition, flatFocusPoint)

				for _, partData in ipairs(rig.Parts) do
					if partData.Part and partData.Part.Parent then
						partData.Part.CFrame = cloneRootCFrame * partData.Relative
					end
				end
			end

			task.wait(0.05)
		end

		container:SetAttribute("Active", false)
		for _, rig in ipairs(rigs) do
			if rig.Highlight then
				rig.Highlight.Enabled = false
			end
			for _, partData in ipairs(rig.Parts) do
				if partData.Part and partData.Part.Parent then
					TweenService:Create(partData.Part, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
						Transparency = 1,
					}):Play()
				end
			end
		end
		Debris:AddItem(container, 0.22)
	end)

	return container
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

	task.spawn(function()
		local low = 0.62
		local high = 0.3
		local toHigh = true
		while model.Parent and model:GetAttribute("Active") do
			local goalTransparency = toHigh and high or low
			toHigh = not toHigh

			local tweenInfo = TweenInfo.new(0.28, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
			TweenService:Create(outline, tweenInfo, {Transparency = goalTransparency}):Play()

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

function EffectService:CreateTelekinesisMarker(root, color)
	local tone = color or Color3.fromRGB(240, 240, 255)
	local model = Instance.new("Model")
	model.Name = "TelekinesisMarker"
	model:SetAttribute("Active", true)
	model.Parent = self.Folder

	local shell = createAttachedPart(model, {
		Name = "MarkerShell",
		Material = Enum.Material.ForceField,
		Color = tone,
		Transparency = 0.38,
		Size = Vector3.new(0.95, 4.6, 0.95),
		CFrame = root.CFrame * CFrame.new(2.5, 1.8, 0),
	})

	local core = createAttachedPart(model, {
		Name = "MarkerCore",
		Material = Enum.Material.Neon,
		Color = tone,
		Transparency = 0.08,
		Size = Vector3.new(0.42, 3.8, 0.42),
		CFrame = root.CFrame * CFrame.new(2.5, 1.8, 0),
	})

	for _, part in ipairs({shell, core}) do
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = root
		weld.Part1 = part
		weld.Parent = part
	end

	task.spawn(function()
		local brighten = true
		while model.Parent and model:GetAttribute("Active") do
			local shellTransparency = brighten and 0.22 or 0.44
			local coreTransparency = brighten and 0.02 or 0.18
			brighten = not brighten

			local tweenInfo = TweenInfo.new(0.16, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
			TweenService:Create(shell, tweenInfo, {Transparency = shellTransparency}):Play()
			TweenService:Create(core, tweenInfo, {Transparency = coreTransparency}):Play()

			task.wait(0.16)
		end
	end)

	return model
end

function EffectService:DestroyTelekinesisMarker(marker)
	if not marker or not marker.Parent then
		return
	end

	marker:SetAttribute("Active", false)
	for _, child in ipairs(marker:GetDescendants()) do
		if child:IsA("BasePart") then
			TweenService:Create(child, TweenInfo.new(0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				Transparency = 1,
				Size = child.Size + Vector3.new(0.1, 0.4, 0.1),
			}):Play()
		end
	end
	Debris:AddItem(marker, 0.18)
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

function EffectService:SpawnBoneBall(position, size, color, duration)
	local boneBall = createPart(self.Folder, {
		Name = "BoneBall",
		Shape = Enum.PartType.Ball,
		Material = Enum.Material.Neon,
		Color = color or Color3.fromRGB(100, 175, 255),
		Transparency = 0.04,
		Size = Vector3.new(1, 1, 1) * (size or 1.2),
		CFrame = CFrame.new(position),
	})
	self:FadePart(boneBall, duration or 0.26, 1, boneBall.Size + Vector3.new(0.8, 0.8, 0.8))
	return boneBall
end

function EffectService:SpawnBoneBatSwing(cframe, color)
	local swing = createPart(self.Folder, {
		Name = "BoneBatSwing",
		Material = Enum.Material.Neon,
		Color = color or Color3.fromRGB(245, 245, 255),
		Transparency = 0.08,
		Size = Vector3.new(0.6, 4.5, 0.6),
		CFrame = cframe,
	})
	self:FadePart(swing, 0.18, 1, swing.Size + Vector3.new(0.2, 1.1, 0.2))

	local arc = createPart(self.Folder, {
		Name = "BoneBatArc",
		Material = Enum.Material.Neon,
		Color = color or Color3.fromRGB(245, 245, 255),
		Transparency = 0.16,
		Size = Vector3.new(2.6, 2.6, 5.4),
		CFrame = cframe * CFrame.new(0, 0.2, -1.8),
	})
	self:FadePart(arc, 0.16, 1, arc.Size + Vector3.new(1.2, 1.2, 1.8))
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

function EffectService:SpawnCounterFlash(position, color)
	local flash = createPart(self.Folder, {
		Name = "CounterFlash",
		Shape = Enum.PartType.Ball,
		Material = Enum.Material.Neon,
		Color = color or Color3.fromRGB(255, 70, 70),
		Transparency = 0.2,
		Size = Vector3.new(3, 3, 3),
		CFrame = CFrame.new(position),
	})
	self:FadePart(flash, 0.3, 1, Vector3.new(12, 12, 12))
end

function EffectService:CreateGroundSlideTrail(root, duration)
	if not root then
		return nil
	end

	local life = duration or 2
	local model = Instance.new("Model")
	model.Name = "GroundSlideTrail"
	model:SetAttribute("Active", true)
	model.Parent = self.Folder

	local streak = createAttachedPart(model, {
		Name = "SlideStreak",
		Material = Enum.Material.ForceField,
		Color = Color3.fromRGB(196, 176, 140),
		Transparency = 0.62,
		Size = Vector3.new(2.6, 0.16, 3.8),
		CFrame = root.CFrame * CFrame.new(0, -2.55, 1.2),
	})
	local streakMesh = Instance.new("SpecialMesh")
	streakMesh.MeshType = Enum.MeshType.Brick
	streakMesh.Parent = streak

	local glow = createAttachedPart(model, {
		Name = "SlideGlow",
		Material = Enum.Material.Neon,
		Color = Color3.fromRGB(238, 202, 138),
		Transparency = 0.8,
		Size = Vector3.new(1.8, 0.08, 2.1),
		CFrame = root.CFrame * CFrame.new(0, -2.62, 0.9),
	})

	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = "SlideDust"
	emitter.Texture = "rbxasset://textures/particles/smoke_main.dds"
	emitter.Rate = 54
	emitter.Lifetime = NumberRange.new(0.4, 0.78)
	emitter.Speed = NumberRange.new(3.5, 7.5)
	emitter.RotSpeed = NumberRange.new(-70, 70)
	emitter.SpreadAngle = Vector2.new(40, 40)
	emitter.Acceleration = Vector3.new(0, 3.2, 0)
	emitter.Drag = 3
	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.9),
		NumberSequenceKeypoint.new(0.45, 1.8),
		NumberSequenceKeypoint.new(1, 2.6),
	})
	emitter.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.08),
		NumberSequenceKeypoint.new(0.6, 0.38),
		NumberSequenceKeypoint.new(1, 1),
	})
	emitter.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(230, 205, 164)),
		ColorSequenceKeypoint.new(0.55, Color3.fromRGB(170, 145, 112)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(118, 104, 87)),
	})
	emitter.Parent = streak
	emitter:Emit(24)

	for _, part in ipairs({streak, glow}) do
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = root
		weld.Part1 = part
		weld.Parent = part
	end

	task.spawn(function()
		local startedAt = os.clock()
		local brighten = true
		while model.Parent and model:GetAttribute("Active") and (os.clock() - startedAt) < life do
			local tweenInfo = TweenInfo.new(0.12, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
			TweenService:Create(streak, tweenInfo, {
				Transparency = brighten and 0.54 or 0.68,
				Size = brighten and Vector3.new(2.9, 0.16, 4.3) or Vector3.new(2.6, 0.16, 3.8),
			}):Play()
			TweenService:Create(glow, tweenInfo, {
				Transparency = brighten and 0.72 or 0.86,
				Size = brighten and Vector3.new(2.2, 0.08, 2.5) or Vector3.new(1.8, 0.08, 2.1),
			}):Play()
			brighten = not brighten
			task.wait(0.12)
		end
	end)

	task.delay(life, function()
		if not model.Parent then
			return
		end
		model:SetAttribute("Active", false)
		emitter.Enabled = false
		for _, part in ipairs({streak, glow}) do
			TweenService:Create(part, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				Transparency = 1,
			}):Play()
		end
		Debris:AddItem(model, 0.28)
	end)

	return model
end

function EffectService:SpawnBlaster(position, color, templateNames)
	local model, rootPart, templateName = cloneBlasterModel(self.Folder, true, templateNames)
	if model and rootPart then
		model.Name = "Blaster"
		model:PivotTo(CFrame.new(position))
		if templateName ~= "Fatal Gaster Blaster" and templateName ~= "FatalGasterBlaster" then
			tintModel(model, color)
		end
		for _, child in ipairs(model:GetDescendants()) do
			if child:IsA("BasePart") then
				TweenService:Create(child, TweenInfo.new(1.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
					Transparency = math.min(1, child.Transparency + 0.6),
				}):Play()
			end
		end
		Debris:AddItem(model, 1.15)
		return
	end

	local blaster = createPart(self.Folder, {
		Name = "Blaster",
		Material = Enum.Material.Neon,
		Color = color or Color3.fromRGB(215, 235, 255),
		Transparency = 0.05,
		Size = Vector3.new(2.5, 2.5, 4),
		CFrame = CFrame.new(position),
	})
	self:FadePart(blaster, 1.1, 0.65)
end

function EffectService:CreatePersistentBlaster(root, localOffset, color, templateNames)
	if not root then
		return nil
	end

	local offset = localOffset or Vector3.new()
	local model, modelRoot, templateName = cloneBlasterModel(self.Folder, false, templateNames)
	if model and modelRoot then
		model.Name = "PersistentBlaster"
		model:SetAttribute("Active", true)
		model:PivotTo(root.CFrame * CFrame.new(offset))
		if templateName ~= "Fatal Gaster Blaster" and templateName ~= "FatalGasterBlaster" then
			tintModel(model, color)
		end

		local weld = Instance.new("WeldConstraint")
		weld.Part0 = root
		weld.Part1 = modelRoot
		weld.Parent = modelRoot
		return model
	end

	local model = Instance.new("Model")
	model.Name = "PersistentBlaster"
	model:SetAttribute("Active", true)
	model.Parent = self.Folder

	local shell = createAttachedPart(model, {
		Name = "BlasterShell",
		Material = Enum.Material.ForceField,
		Color = color or Color3.fromRGB(215, 235, 255),
		Transparency = 0.35,
		Size = Vector3.new(3.1, 3.1, 4.8),
		CFrame = root.CFrame * CFrame.new(offset),
	})

	local core = createAttachedPart(model, {
		Name = "BlasterCore",
		Material = Enum.Material.Neon,
		Color = color or Color3.fromRGB(235, 245, 255),
		Transparency = 0.08,
		Size = Vector3.new(2.35, 2.35, 4),
		CFrame = root.CFrame * CFrame.new(offset),
	})

	for _, part in ipairs({shell, core}) do
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = root
		weld.Part1 = part
		weld.Parent = part
	end

	task.spawn(function()
		local brighten = true
		while model.Parent and model:GetAttribute("Active") do
			local shellTransparency = brighten and 0.24 or 0.42
			local coreTransparency = brighten and 0.02 or 0.14
			brighten = not brighten

			local tweenInfo = TweenInfo.new(0.18, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
			TweenService:Create(shell, tweenInfo, {Transparency = shellTransparency}):Play()
			TweenService:Create(core, tweenInfo, {Transparency = coreTransparency}):Play()

			task.wait(0.18)
		end
	end)

	return model
end

function EffectService:DestroyPersistentBlaster(blaster)
	if not blaster or not blaster.Parent then
		return
	end

	blaster:SetAttribute("Active", false)
	for _, child in ipairs(blaster:GetDescendants()) do
		if child:IsA("BasePart") then
			TweenService:Create(child, TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				Transparency = 1,
				Size = child.Size + Vector3.new(0.2, 0.2, 0.25),
			}):Play()
		end
	end
	Debris:AddItem(blaster, 0.2)
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
