local CONFIG = {
	DayNightCycleEnabled = true,
	DayCycleLength = 120,
	StartTime = 9,
	FirefliesEnabled = true,
	MaxFireflies = 120,
	FireflySpreadArea = 400,
	FireflyHeight = {1, 12},
	FireflyMinSize = 0.1,
	FireflyMaxSize = 0.45,
	FireflyAppearTime = 18,
	FireflyDisappearTime = 6,
	FallingLeavesEnabled = true,
	MaxLeaves = 40,
	LeafColors = {
		Color3.fromRGB(80, 120, 50),
		Color3.fromRGB(100, 140, 60),
		Color3.fromRGB(140, 100, 40),
		Color3.fromRGB(120, 110, 50),
	},
	LeafFallSpeed = 3,
	LeafSpreadArea = 300,
	LeafHeight = 50,
	MorningMistEnabled = true,
	MistAppearTime = 4,
	MistFadeTime = 9,
	MistParticles = 25,
	MistSpreadArea = 200,
	DirtParticlesEnabled = true,
	DirtColor = Color3.fromRGB(120, 80, 50),
	DirtColorVariation = Color3.fromRGB(100, 70, 45),
	ParticlesPerStep = 6,
	ParticleLifetime = 0.8,
	ParticleSpeed = 3,
	StepInterval = 0.25,
	UpdateInterval = 0.03,
}

local Players = game:GetService("Players")
local Lighting = game:GetService("Lighting")
local Workspace = game:GetService("Workspace")
local Debris = game:GetService("Debris")

local State = {
	CurrentTime = CONFIG.StartTime,
	Fireflies = {},
	Leaves = {},
	MistParts = {},
	PlayerFootsteps = {},
}

local Folders = {
	Main = nil,
	Fireflies = nil,
	Leaves = nil,
	Mist = nil,
	Particles = nil,
}

local function GetCurrentHour()
	return State.CurrentTime
end

local function GetPlayerPositions()
	local positions = {}
	for _, player in ipairs(Players:GetPlayers()) do
		if player.Character then
			local hrp = player.Character:FindFirstChild("HumanoidRootPart")
			if hrp then
				table.insert(positions, hrp.Position)
			end
		end
	end
	if #positions == 0 then
		positions = {Vector3.new(0, 5, 0)}
	end
	return positions
end

local function SetupFolders()
	local existing = Workspace:FindFirstChild("AtmosphereSystem")
	if existing then existing:Destroy() end
	Folders.Main = Instance.new("Folder")
	Folders.Main.Name = "AtmosphereSystem"
	Folders.Main.Parent = Workspace
	Folders.Fireflies = Instance.new("Folder")
	Folders.Fireflies.Name = "Fireflies"
	Folders.Fireflies.Parent = Folders.Main
	Folders.Leaves = Instance.new("Folder")
	Folders.Leaves.Name = "Leaves"
	Folders.Leaves.Parent = Folders.Main
	Folders.Mist = Instance.new("Folder")
	Folders.Mist.Name = "Mist"
	Folders.Mist.Parent = Folders.Main
	Folders.Particles = Instance.new("Folder")
	Folders.Particles.Name = "DirtParticles"
	Folders.Particles.Parent = Folders.Main
end

local function UpdateDayNightCycle(deltaTime)
	if not CONFIG.DayNightCycleEnabled then return end
	local hoursPerSecond = 24 / CONFIG.DayCycleLength
	State.CurrentTime = State.CurrentTime + (hoursPerSecond * deltaTime)
	if State.CurrentTime >= 24 then State.CurrentTime = State.CurrentTime - 24 end
	Lighting.ClockTime = State.CurrentTime
end

local function CreateFirefly(position)
	local size = CONFIG.FireflyMinSize + math.random() * (CONFIG.FireflyMaxSize - CONFIG.FireflyMinSize)
	local firefly = Instance.new("Part")
	firefly.Shape = Enum.PartType.Ball
	firefly.Size = Vector3.new(size, size, size)
	firefly.Position = position
	firefly.Anchored = true
	firefly.CanCollide = false
	firefly.CastShadow = false
	firefly.Material = Enum.Material.Neon
	local colorRoll = math.random()
	if colorRoll < 0.5 then firefly.Color = Color3.fromRGB(255, 255, 255)
	elseif colorRoll < 0.8 then firefly.Color = Color3.fromRGB(255, 252, 245)
	else firefly.Color = Color3.fromRGB(255, 255, 235) end
	firefly.Transparency = 0.1
	local light = Instance.new("PointLight")
	light.Color = firefly.Color
	light.Brightness = 1.2 + (size / CONFIG.FireflyMaxSize) * 1.5
	light.Range = 5 + size * 12
	light.Shadows = false
	light.Parent = firefly
	local fireflyData = {
		Part = firefly,
		Light = light,
		BasePosition = position,
		Size = size,
		Phase = math.random() * math.pi * 2,
		GlowPhase = math.random() * math.pi * 2,
		Speed = 0.2 + math.random() * 0.4,
		WanderRadius = 2 + math.random() * 5,
		VerticalWander = 1 + math.random() * 2.5,
		BlinkRate = 1.5 + math.random() * 2,
	}
	firefly.Parent = Folders.Fireflies
	table.insert(State.Fireflies, fireflyData)
	return fireflyData
end

local function UpdateFireflies(deltaTime)
	local hour = GetCurrentHour()
	local shouldShow = hour >= CONFIG.FireflyAppearTime or hour < CONFIG.FireflyDisappearTime
	local playerPositions = GetPlayerPositions()
	if shouldShow then
		local intensity = 1
		if hour >= CONFIG.FireflyAppearTime and hour < 22 then intensity = (hour - CONFIG.FireflyAppearTime) / 4
		elseif hour >= 4 and hour < CONFIG.FireflyDisappearTime then intensity = (CONFIG.FireflyDisappearTime - hour) / 2 end
		local targetCount = math.floor(CONFIG.MaxFireflies * math.min(intensity, 1))
		while #State.Fireflies < targetCount do
			local centerPos = playerPositions[math.random(1, #playerPositions)]
			local angle = math.random() * math.pi * 2
			local distance = math.random() * CONFIG.FireflySpreadArea
			local spawnPos = Vector3.new(centerPos.X + math.cos(angle) * distance,
				CONFIG.FireflyHeight[1] + math.random() * (CONFIG.FireflyHeight[2] - CONFIG.FireflyHeight[1]),
				centerPos.Z + math.sin(angle) * distance)
			CreateFirefly(spawnPos)
		end
	end
	for i = #State.Fireflies, 1, -1 do
		local data = State.Fireflies[i]
		local firefly = data.Part
		if firefly and firefly.Parent then
			if not shouldShow then
				firefly.Transparency = firefly.Transparency + deltaTime * 0.5
				data.Light.Brightness = data.Light.Brightness * 0.95
				if firefly.Transparency >= 1 then
					firefly:Destroy()
					table.remove(State.Fireflies, i)
				end
			else
				data.Phase = data.Phase + deltaTime * data.Speed
				data.GlowPhase = data.GlowPhase + deltaTime * data.BlinkRate
				local wanderX = math.sin(data.Phase) * data.WanderRadius
				local wanderY = math.sin(data.Phase * 1.7) * data.VerticalWander
				local wanderZ = math.cos(data.Phase * 0.9) * data.WanderRadius
				firefly.Position = data.BasePosition + Vector3.new(wanderX, wanderY, wanderZ)
				local glowIntensity = 0.5 + math.sin(data.GlowPhase) * 0.5
				local baseBrightness = 1.2 + (data.Size / CONFIG.FireflyMaxSize) * 1.5
				data.Light.Brightness = baseBrightness * glowIntensity
				firefly.Transparency = 0.1 + (1 - glowIntensity) * 0.5
				if math.random() < 0.001 then data.GlowPhase = data.GlowPhase + math.pi * 0.8 end
				data.BasePosition = data.BasePosition + Vector3.new((math.random() - 0.5) * deltaTime * 0.3, 0, (math.random() - 0.5) * deltaTime * 0.3)
			end
		else
			table.remove(State.Fireflies, i)
		end
	end
end

local function CreateLeaf(position)
	local leaf = Instance.new("Part")
	leaf.Size = Vector3.new(0.4 + math.random() * 0.3, 0.05, 0.3 + math.random() * 0.2)
	leaf.Position = position
	leaf.Anchored = true
	leaf.CanCollide = false
	leaf.CastShadow = false
	leaf.Material = Enum.Material.SmoothPlastic
	leaf.Color = CONFIG.LeafColors[math.random(1, #CONFIG.LeafColors)]
	leaf.Orientation = Vector3.new(math.random() * 30, math.random() * 360, math.random() * 30)
	local leafData = {Part = leaf, Phase = math.random() * math.pi * 2, FallSpeed = CONFIG.LeafFallSpeed * (0.7 + math.random() * 0.6), SwayAmount = 2 + math.random() * 3, SpinSpeed = 30 + math.random() * 60, StartY = position.Y}
	leaf.Parent = Folders.Leaves
	table.insert(State.Leaves, leafData)
	return leafData
end

local function UpdateLeaves(deltaTime)
	if not CONFIG.FallingLeavesEnabled then return end
	local playerPositions = GetPlayerPositions()
	while #State.Leaves < CONFIG.MaxLeaves do
		local centerPos = playerPositions[math.random(1, #playerPositions)]
		local spawnPos = Vector3.new(centerPos.X + (math.random() - 0.5) * CONFIG.LeafSpreadArea,
			CONFIG.LeafHeight + math.random() * 20,
			centerPos.Z + (math.random() - 0.5) * CONFIG.LeafSpreadArea)
		CreateLeaf(spawnPos)
	end
	for i = #State.Leaves, 1, -1 do
		local data = State.Leaves[i]
		local leaf = data.Part
		if leaf and leaf.Parent then
			data.Phase = data.Phase + deltaTime
			local currentPos = leaf.Position
			local swayX = math.sin(data.Phase * 2) * data.SwayAmount
			local swayZ = math.cos(data.Phase * 1.5) * data.SwayAmount * 0.7
			leaf.Position = Vector3.new(currentPos.X + swayX * deltaTime, currentPos.Y - data.FallSpeed * deltaTime, currentPos.Z + swayZ * deltaTime)
			local currentRot = leaf.Orientation
			leaf.Orientation = Vector3.new(currentRot.X + math.sin(data.Phase) * 20 * deltaTime, currentRot.Y + data.SpinSpeed * deltaTime, currentRot.Z + math.cos(data.Phase) * 15 * deltaTime)
			if leaf.Position.Y < -5 then
				leaf:Destroy()
				table.remove(State.Leaves, i)
			end
		else
			table.remove(State.Leaves, i)
		end
	end
end

local function CreateMistParticle(position)
	local mist = Instance.new("Part")
	mist.Shape = Enum.PartType.Ball
	mist.Size = Vector3.new(15 + math.random() * 20, 5 + math.random() * 5, 15 + math.random() * 20)
	mist.Position = position
	mist.Anchored = true
	mist.CanCollide = false
	mist.CastShadow = false
	mist.Material = Enum.Material.SmoothPlastic
	mist.Color = Color3.fromRGB(220, 225, 230)
	mist.Transparency = 0.85
	local mistData = {Part = mist, Phase = math.random() * math.pi * 2, DriftSpeed = 0.5 + math.random() * 0.5, BaseY = position.Y}
	mist.Parent = Folders.Mist
	table.insert(State.MistParts, mistData)
	return mistData
end

local function UpdateMist(deltaTime)
	if not CONFIG.MorningMistEnabled then return end
	local hour = GetCurrentHour()
	local shouldShow = hour >= CONFIG.MistAppearTime and hour < CONFIG.MistFadeTime
	local mistIntensity = 0
	if shouldShow then
		if hour < 6 then mistIntensity = (hour - CONFIG.MistAppearTime) / 2
		else mistIntensity = 1 - ((hour - 6) / (CONFIG.MistFadeTime - 6)) end
		mistIntensity = math.max(0, math.min(1, mistIntensity))
	end
	local playerPositions = GetPlayerPositions()
	if mistIntensity > 0 and #State.MistParts < CONFIG.MistParticles then
		local centerPos = playerPositions[math.random(1, #playerPositions)]
		local spawnPos = Vector3.new(centerPos.X + (math.random() - 0.5) * CONFIG.MistSpreadArea, 1 + math.random() * 3, centerPos.Z + (math.random() - 0.5) * CONFIG.MistSpreadArea)
		CreateMistParticle(spawnPos)
	end
	for i = #State.MistParts, 1, -1 do
		local data = State.MistParts[i]
		local mist = data.Part
		if mist and mist.Parent then
			if mistIntensity <= 0 then
				mist.Transparency = mist.Transparency + deltaTime * 0.3
				if mist.Transparency >= 1 then
					mist:Destroy()
					table.remove(State.MistParts, i)
				end
			else
				data.Phase = data.Phase + deltaTime * data.DriftSpeed
				local currentPos = mist.Position
				mist.Position = Vector3.new(currentPos.X + math.sin(data.Phase) * deltaTime * 2, data.BaseY + math.sin(data.Phase * 0.5) * 0.5, currentPos.Z + math.cos(data.Phase * 0.7) * deltaTime * 1.5)
				mist.Transparency = 0.7 + (1 - mistIntensity) * 0.25
			end
		else
			table.remove(State.MistParts, i)
		end
	end
end

local function CreateDirtParticle(position, velocity)
	local particle = Instance.new("Part")
	particle.Shape = Enum.PartType.Ball
	particle.Size = Vector3.new(0.15 + math.random() * 0.15, 0.1 + math.random() * 0.1, 0.15 + math.random() * 0.15)
	particle.Position = position
	particle.Anchored = false
	particle.CanCollide = false
	particle.CastShadow = false
	particle.Material = Enum.Material.SmoothPlastic
	if math.random() > 0.5 then particle.Color = CONFIG.DirtColor else particle.Color = CONFIG.DirtColorVariation end
	particle.Parent = Folders.Particles
	local bodyVelocity = Instance.new("BodyVelocity")
	bodyVelocity.Velocity = velocity
	bodyVelocity.MaxForce = Vector3.new(1000, 1000, 1000)
	bodyVelocity.Parent = particle
	Debris:AddItem(bodyVelocity, 0.1)
	task.spawn(function()
		local lifetime = CONFIG.ParticleLifetime
		local startTime = tick()
		while tick() - startTime < lifetime do
			local elapsed = tick() - startTime
			local alpha = elapsed / lifetime
			particle.Transparency = alpha
			particle.Size = particle.Size * 0.98
			task.wait(0.03)
		end
		particle:Destroy()
	end)
	return particle
end

local function EmitDirtParticles(position, moveDirection)
	for i = 1, CONFIG.ParticlesPerStep do
		local offsetX = (math.random() - 0.5) * 1
		local offsetZ = (math.random() - 0.5) * 1
		local spawnPos = Vector3.new(position.X + offsetX, position.Y + 0.1, position.Z + offsetZ)
		local upSpeed = CONFIG.ParticleSpeed * (0.8 + math.random() * 0.4)
		local outSpeed = CONFIG.ParticleSpeed * 0.5 * (math.random() - 0.3)
		local velocity = Vector3.new(-moveDirection.X * outSpeed + (math.random() - 0.5) * 2, upSpeed, -moveDirection.Z * outSpeed + (math.random() - 0.5) * 2)
		CreateDirtParticle(spawnPos, velocity)
	end
end

local function IsOnPath(position)
	local rayOrigin = position + Vector3.new(0, 1, 0)
	local rayDirection = Vector3.new(0, -3, 0)
	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Include
	local pathSystem = Workspace:FindFirstChild("InfinitePathSystem")
	if pathSystem then
		local pathFolder = pathSystem:FindFirstChild("Path")
		if pathFolder then
			raycastParams.FilterDescendantsInstances = {pathFolder}
			local result = Workspace:Raycast(rayOrigin, rayDirection, raycastParams)
			if result then return true end
		end
	end
	return false
end

local function UpdateDirtParticles(deltaTime)
	if not CONFIG.DirtParticlesEnabled then return end
	for _, player in ipairs(Players:GetPlayers()) do
		local character = player.Character
		if character then
			local humanoid = character:FindFirstChild("Humanoid")
			local hrp = character:FindFirstChild("HumanoidRootPart")
			if humanoid and hrp then
				local isWalking = humanoid.MoveDirection.Magnitude > 0.1
				local isGrounded = humanoid.FloorMaterial ~= Enum.Material.Air
				if isWalking and isGrounded then
					local footPosition = hrp.Position - Vector3.new(0, 2.5, 0)
					if IsOnPath(footPosition) then
						local lastStep = State.PlayerFootsteps[player.UserId] or 0
						local currentTime = tick()
						if currentTime - lastStep >= CONFIG.StepInterval then
							State.PlayerFootsteps[player.UserId] = currentTime
							EmitDirtParticles(footPosition, humanoid.MoveDirection)
						end
					end
				end
			end
		end
	end
end

local function MainLoop()
	local lastTime = tick()
	while true do
		local currentTime = tick()
		local deltaTime = math.min(currentTime - lastTime, 0.1)
		lastTime = currentTime
		UpdateDayNightCycle(deltaTime)
		UpdateFireflies(deltaTime)
		UpdateLeaves(deltaTime)
		UpdateMist(deltaTime)
		UpdateDirtParticles(deltaTime)
		task.wait(CONFIG.UpdateInterval)
	end
end

Players.PlayerRemoving:Connect(function(player)
	State.PlayerFootsteps[player.UserId] = nil
end)

local function Initialize()
	SetupFolders()
	Lighting.ClockTime = CONFIG.StartTime
	task.spawn(MainLoop)
end

Initialize()
