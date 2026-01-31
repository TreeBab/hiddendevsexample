local CONFIG = {
	RenderDistance = 250,
	UpdateInterval = 0.3,
	GrassColor = Color3.fromRGB(76, 153, 76),
	GrassMaterial = Enum.Material.Grass,
	TerrainChunkSize = 100,
	TerrainWidth = 400,
	GrassHeight = 1,
	PathColor = Color3.fromRGB(139, 90, 43),
	PathColorVariation = 8,
	PathMaterial = Enum.Material.Ground,
	PathWidth = 8,
	PathHeight = 0.2,
	PathSegmentLength = 10,
	MaxTurnAngle = 15,
	StraightChance = 0.4,
	CurveSmoothing = 0.8,
	CurveBias = 0,
	TreeModelName = "Tree",
	TreesPerChunk = 8,
	TreeMinDistanceFromPath = 20,
	TreeMinDistanceBetween = 12,
	TreeSizeVariation = 5,
	TreeRotationRandom = true,
	LampModelName = "Lamp",
	LampSpacing = 40,
	LampDistanceFromPath = 6,
	LampAlternateSides = true,
	LampRandomOffset = 1.5,
	LampRotateToPath = true,
	SegmentsPerFrame = 3,
	StartDirection = 0,
}

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PathState = {
	ForwardEndPosition = Vector3.new(0, 0, 0),
	ForwardEndAngle = CONFIG.StartDirection,
	ForwardPreviousTurn = 0,
	BackwardEndPosition = Vector3.new(0, 0, 0),
	BackwardEndAngle = CONFIG.StartDirection + 180,
	BackwardPreviousTurn = 0,
	SegmentIndex = 0,
	LoadedChunkKeys = {},
	AllPathPoints = {},
	TreePositions = {},
	TreeIndex = 0,
	LampIndex = 0,
	LastLampPositionForward = Vector3.new(0, 0, 0),
	LastLampPositionBackward = Vector3.new(0, 0, 0),
	LampSideForward = 1,
	LampSideBackward = 1,
}

local Folders = {Main = nil, Grass = nil, Path = nil, Trees = nil, Lamps = nil}
local TreeTemplate = nil
local LampTemplate = nil

local function Clamp(value, min, max)
	return math.max(min, math.min(max, value))
end

local function GetVariedPathColor()
	local variation = CONFIG.PathColorVariation
	local baseColor = CONFIG.PathColor
	local r = Clamp(baseColor.R * 255 + (math.random() - 0.5) * 2 * variation, 0, 255)
	local g = Clamp(baseColor.G * 255 + (math.random() - 0.5) * 2 * variation, 0, 255)
	local b = Clamp(baseColor.B * 255 + (math.random() - 0.5) * 2 * variation, 0, 255)
	return Color3.fromRGB(r, g, b)
end

local function GetChunkKey(position)
	local chunkSize = CONFIG.TerrainChunkSize
	local cx = math.floor(position.X / chunkSize)
	local cz = math.floor(position.Z / chunkSize)
	return cx .. "," .. cz
end

local function GetChunkCenter(chunkKey)
	local cx, cz = chunkKey:match("([^,]+),([^,]+)")
	cx, cz = tonumber(cx), tonumber(cz)
	local chunkSize = CONFIG.TerrainChunkSize
	return Vector3.new(cx * chunkSize + chunkSize / 2, 0, cz * chunkSize + chunkSize / 2)
end

local function IsTooCloseToPath(position)
	local minDist = CONFIG.TreeMinDistanceFromPath
	local posX, posZ = position.X, position.Z
	for _, pathPoint in ipairs(PathState.AllPathPoints) do
		local dx = posX - pathPoint.X
		local dz = posZ - pathPoint.Z
		if dx*dx + dz*dz < minDist*minDist then return true end
	end
	return false
end

local function IsTooCloseToTrees(position)
	local minDist = CONFIG.TreeMinDistanceBetween
	local posX, posZ = position.X, position.Z
	for _, treePos in ipairs(PathState.TreePositions) do
		local dx = posX - treePos.X
		local dz = posZ - treePos.Z
		if dx*dx + dz*dz < minDist*minDist then return true end
	end
	return false
end

local function SetupFolders()
	local existing = Workspace:FindFirstChild("InfinitePathSystem")
	if existing then existing:Destroy() task.wait(0.1) end
	Folders.Main = Instance.new("Folder")
	Folders.Main.Name = "InfinitePathSystem"
	Folders.Main.Parent = Workspace
	Folders.Grass = Instance.new("Folder")
	Folders.Grass.Name = "Grass"
	Folders.Grass.Parent = Folders.Main
	Folders.Path = Instance.new("Folder")
	Folders.Path.Name = "Path"
	Folders.Path.Parent = Folders.Main
	Folders.Trees = Instance.new("Folder")
	Folders.Trees.Name = "Trees"
	Folders.Trees.Parent = Folders.Main
	Folders.Lamps = Instance.new("Folder")
	Folders.Lamps.Name = "Lamps"
	Folders.Lamps.Parent = Folders.Main
end

local function LoadTemplates()
	TreeTemplate = ReplicatedStorage:FindFirstChild(CONFIG.TreeModelName)
	LampTemplate = ReplicatedStorage:FindFirstChild(CONFIG.LampModelName)
end

local function SpawnTree(position)
	if not TreeTemplate then return nil end
	PathState.TreeIndex += 1
	local tree = TreeTemplate:Clone()
	tree.Name = "Tree_" .. PathState.TreeIndex
	local rotation = CONFIG.TreeRotationRandom and (math.random() * 360) or 0
	local baseScale = 1
	local variation = (math.random() - 0.5) * 2 * (CONFIG.TreeSizeVariation / 10)
	local scaleFactor = Clamp(baseScale + variation, 0.5, 1.5)
	local primaryPart = tree.PrimaryPart
	if not primaryPart then
		for _, child in ipairs(tree:GetDescendants()) do
			if child:IsA("BasePart") then
				primaryPart = child
				tree.PrimaryPart = primaryPart
				break
			end
		end
	end
	if primaryPart then
		tree:PivotTo(CFrame.new(Vector3.new(position.X,0,position.Z))*CFrame.Angles(0,math.rad(rotation),0))
		if scaleFactor ~= 1 then tree:ScaleTo(scaleFactor) end
	else
		tree:Destroy()
		return nil
	end
	tree.Parent = Folders.Trees
	table.insert(PathState.TreePositions, position)
	return tree
end

local function GenerateTreesForChunk(chunkKey)
	if not TreeTemplate then return end
	local chunkCenter = GetChunkCenter(chunkKey)
	local chunkSize = CONFIG.TerrainChunkSize
	local treesPlaced = 0
	local maxAttempts = CONFIG.TreesPerChunk*10
	local attempts = 0
	while treesPlaced < CONFIG.TreesPerChunk and attempts < maxAttempts do
		attempts += 1
		local offsetX = (math.random()-0.5)*chunkSize
		local offsetZ = (math.random()-0.5)*chunkSize
		local position = Vector3.new(chunkCenter.X+offsetX,0,chunkCenter.Z+offsetZ)
		if not IsTooCloseToPath(position) and not IsTooCloseToTrees(position) then
			SpawnTree(position)
			treesPlaced += 1
		end
	end
end

local function SpawnLamp(position,pathAngle,side)
	if not LampTemplate then return nil end
	PathState.LampIndex += 1
	local lamp = LampTemplate:Clone()
	lamp.Name = "Lamp_" .. PathState.LampIndex
	local pathAngleRad = math.rad(pathAngle)
	local perpAngle = pathAngleRad + (math.pi/2)*side
	local offsetDistance = CONFIG.LampDistanceFromPath + (math.random()-0.5)*CONFIG.LampRandomOffset
	local lampPosition = Vector3.new(position.X+math.sin(perpAngle)*offsetDistance,0,position.Z+math.cos(perpAngle)*offsetDistance)
	local primaryPart = lamp.PrimaryPart
	if not primaryPart then
		for _, child in ipairs(lamp:GetDescendants()) do
			if child:IsA("BasePart") then
				primaryPart = child
				lamp.PrimaryPart = primaryPart
				break
			end
		end
	end
	if primaryPart then
		local lampRotation = CONFIG.LampRotateToPath and (pathAngle+90*side) or 0
		lamp:PivotTo(CFrame.new(lampPosition)*CFrame.Angles(0,math.rad(lampRotation),0))
	else
		lamp:Destroy()
		return nil
	end
	lamp.Parent = Folders.Lamps
	return lamp
end

local function TrySpawnLamp(position,pathAngle,direction)
	if not LampTemplate then return end
	local lastLampPos,lampSide
	if direction=="forward" then
		lastLampPos=PathState.LastLampPositionForward
		lampSide=PathState.LampSideForward
	else
		lastLampPos=PathState.LastLampPositionBackward
		lampSide=PathState.LampSideBackward
	end
	local distance=(position-lastLampPos).Magnitude
	if distance>=CONFIG.LampSpacing then
		SpawnLamp(position,pathAngle,lampSide)
		if direction=="forward" then
			PathState.LastLampPositionForward=position
			if CONFIG.LampAlternateSides then PathState.LampSideForward=-PathState.LampSideForward end
		else
			PathState.LastLampPositionBackward=position
			if CONFIG.LampAlternateSides then PathState.LampSideBackward=-PathState.LampSideBackward end
		end
	end
end

local function CreateTerrainChunk(chunkKey)
	if PathState.LoadedChunkKeys[chunkKey] then return end
	local center=GetChunkCenter(chunkKey)
	local size=CONFIG.TerrainChunkSize
	local chunk=Instance.new("Part")
	chunk.Name="Chunk_"..chunkKey
	chunk.Size=Vector3.new(size,CONFIG.GrassHeight,size)
	chunk.Position=Vector3.new(center.X,-CONFIG.GrassHeight/2,center.Z)
	chunk.Anchored=true
	chunk.Color=CONFIG.GrassColor
	chunk.Material=CONFIG.GrassMaterial
	chunk.TopSurface=Enum.SurfaceType.Smooth
	chunk.BottomSurface=Enum.SurfaceType.Smooth
	chunk.CanCollide=true
	chunk.CastShadow=false
	chunk.Parent=Folders.Grass
	PathState.LoadedChunkKeys[chunkKey]=true
	task.delay(0.5,function() GenerateTreesForChunk(chunkKey) end)
end

local function LoadTerrainAroundPosition(position,radius)
	local chunkSize=CONFIG.TerrainChunkSize
	local chunksNeeded=math.ceil(radius/chunkSize)+1
	local centerCX=math.floor(position.X/chunkSize)
	local centerCZ=math.floor(position.Z/chunkSize)
	local terrainWidthChunks=math.ceil(CONFIG.TerrainWidth/chunkSize)
	for dx=-chunksNeeded,chunksNeeded do
		for dz=-terrainWidthChunks,terrainWidthChunks do
			CreateTerrainChunk((centerCX+dx)..","..(centerCZ+dz))
		end
	end
end

local function CreatePathSegment(startPos,endPos,angle)
	PathState.SegmentIndex+=1
	local index=PathState.SegmentIndex
	local dx=endPos.X-startPos.X
	local dz=endPos.Z-startPos.Z
	local length=math.sqrt(dx*dx+dz*dz)
	local centerX=(startPos.X+endPos.X)/2
	local centerZ=(startPos.Z+endPos.Z)/2
	local segment=Instance.new("Part")
	segment.Name="PathSeg_"..index
	segment.Size=Vector3.new(CONFIG.PathWidth,CONFIG.PathHeight,length)
	segment.Anchored=true
	segment.Color=GetVariedPathColor()
	segment.Material=CONFIG.PathMaterial
	segment.TopSurface=Enum.SurfaceType.Smooth
	segment.BottomSurface=Enum.SurfaceType.Smooth
	segment.CanCollide=true
	segment.CastShadow=false
	local startVec=Vector3.new(startPos.X,CONFIG.PathHeight/2,startPos.Z)
	local endVec=Vector3.new(endPos.X,CONFIG.PathHeight/2,endPos.Z)
	local centerVec=Vector3.new(centerX,CONFIG.PathHeight/2,centerZ)
	segment.CFrame=CFrame.lookAt(centerVec,centerVec+(endVec-startVec).Unit)
	segment.Parent=Folders.Path
	return segment
end

local function CreateJointCap(position)
	PathState.SegmentIndex+=1
	local index=PathState.SegmentIndex
	local cap=Instance.new("Part")
	cap.Name="PathCap_"..index
	cap.Shape=Enum.PartType.Cylinder
	cap.Size=Vector3.new(CONFIG.PathHeight*0.8,CONFIG.PathWidth+1,CONFIG.PathWidth+1)
	cap.Anchored=true
	cap.Color=CONFIG.PathColor
	cap.Material=CONFIG.PathMaterial
	cap.TopSurface=Enum.SurfaceType.Smooth
	cap.BottomSurface=Enum.SurfaceType.Smooth
	cap.CanCollide=true
	cap.CastShadow=false
	cap.CFrame=CFrame.new(position.X,CONFIG.PathHeight*0.35,position.Z)*CFrame.Angles(0,0,math.rad(90))
	cap.Parent=Folders.Path
	return cap
end

local function CalculateNextAngle(currentAngle,previousTurn)
	if math.random()<CONFIG.StraightChance then
		local tinyVariation=(math.random()-0.5)*2
		return currentAngle+tinyVariation,tinyVariation
	end
	local maxTurn=CONFIG.MaxTurnAngle
	local baseTurn=(math.random()-0.5)*2*maxTurn
	baseTurn+=CONFIG.CurveBias*maxTurn*0.5
	local smoothedTurn=baseTurn*(1-CONFIG.CurveSmoothing)+previousTurn*CONFIG.CurveSmoothing
	smoothedTurn=Clamp(smoothedTurn,-maxTurn,maxTurn)
	return currentAngle+smoothedTurn,smoothedTurn
end

local function GenerateNextSegment(direction)
	local currentPos,currentAngle,prevTurn
	if direction=="forward" then
		currentPos=PathState.ForwardEndPosition
		currentAngle=PathState.ForwardEndAngle
		prevTurn=PathState.ForwardPreviousTurn
	else
		currentPos=PathState.BackwardEndPosition
		currentAngle=PathState.BackwardEndAngle
		prevTurn=PathState.BackwardPreviousTurn
	end
	local newAngle,newTurn=CalculateNextAngle(currentAngle,prevTurn)
	local angleRad=math.rad(newAngle)
	local dirX=math.sin(angleRad)
	local dirZ=math.cos(angleRad)
	local endPos=Vector3.new(currentPos.X+dirX*CONFIG.PathSegmentLength,0,currentPos.Z+dirZ*CONFIG.PathSegmentLength)
	local centerPos=Vector3.new((currentPos.X+endPos.X)/2,0,(currentPos.Z+endPos.Z)/2)
	CreateJointCap(currentPos)
	CreatePathSegment(currentPos,endPos,newAngle)
	table.insert(PathState.AllPathPoints,currentPos)
	table.insert(PathState.AllPathPoints,centerPos)
	table.insert(PathState.AllPathPoints,endPos)
	TrySpawnLamp(centerPos,newAngle,direction)
	if direction=="forward" then
		PathState.ForwardEndPosition=endPos
		PathState.ForwardEndAngle=newAngle
		PathState.ForwardPreviousTurn=newTurn
	else
		PathState.BackwardEndPosition=endPos
		PathState.BackwardEndAngle=newAngle
		PathState.BackwardPreviousTurn=newTurn
	end
	LoadTerrainAroundPosition(endPos,CONFIG.RenderDistance)
end

local function GetAllPlayerPositions()
	local positions={}
	for _,player in ipairs(Players:GetPlayers()) do
		local character=player.Character
		if character then
			local hrp=character:FindFirstChild("HumanoidRootPart")
			if hrp then table.insert(positions,hrp.Position) end
		end
	end
	return positions
end

local function GetDistanceToNearestPlayer(position,playerPositions)
	local minDistance=math.huge
	for _,playerPos in ipairs(playerPositions) do
		local dx=position.X-playerPos.X
		local dz=position.Z-playerPos.Z
		local distance=math.sqrt(dx*dx+dz*dz)
		if distance<minDistance then minDistance=distance end
	end
	return minDistance
end

local function UpdatePathGeneration()
	local playerPositions=GetAllPlayerPositions()
	if #playerPositions==0 then return end
	local segmentsCreatedThisFrame=0
	local forwardDistance=GetDistanceToNearestPlayer(PathState.ForwardEndPosition,playerPositions)
	while forwardDistance<CONFIG.RenderDistance and segmentsCreatedThisFrame<CONFIG.SegmentsPerFrame do
		GenerateNextSegment("forward")
		forwardDistance=GetDistanceToNearestPlayer(PathState.ForwardEndPosition,playerPositions)
		segmentsCreatedThisFrame+=1
	end
	local backwardDistance=GetDistanceToNearestPlayer(PathState.BackwardEndPosition,playerPositions)
	while backwardDistance<CONFIG.RenderDistance and segmentsCreatedThisFrame<CONFIG.SegmentsPerFrame do
		GenerateNextSegment("backward")
		backwardDistance=GetDistanceToNearestPlayer(PathState.BackwardEndPosition,playerPositions)
		segmentsCreatedThisFrame+=1
	end
end

local function CreateStartingArea()
	table.insert(PathState.AllPathPoints,Vector3.new(0,0,0))
	LoadTerrainAroundPosition(Vector3.new(0,0,0),CONFIG.RenderDistance)
	for i=1,20 do
		GenerateNextSegment("forward")
		GenerateNextSegment("backward")
	end
end

local function Initialize()
	SetupFolders()
	LoadTemplates()
	CreateStartingArea()
	task.spawn(function()
		while true do
			UpdatePathGeneration()
			task.wait(CONFIG.UpdateInterval)
		end
	end)
end

local function OnPlayerAdded(player)
	player.CharacterAdded:Connect(function(character)
		task.wait(1)
		local hrp=character:FindFirstChild("HumanoidRootPart")
		if hrp then hrp.CFrame=CFrame.new(0,5,0) end
		task.wait(0.5)
		UpdatePathGeneration()
	end)
end

Players.PlayerAdded:Connect(OnPlayerAdded)
for _,player in ipairs(Players:GetPlayers()) do
	OnPlayerAdded(player)
end

Initialize()
