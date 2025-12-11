-- Services

local Players = game:GetService("Players")

local Workspace = game:GetService("Workspace")

local RunService = game:GetService("RunService")

local Camera = Workspace.CurrentCamera

local VirtualInputManager = game:GetService("VirtualInputManager")



-- Safe Service Get

local UserInputService = nil

pcall(function() UserInputService = game:GetService("UserInputService") end)



-- ============================================================================

-- 1. DATA & CONFIGURATION

-- ============================================================================



local ActiveRocks = {} -- For Mining Logic

local ActiveOres = {} -- For ESP Logic

local EnabledRocks = {}

local RockNamesSet = {}

local RockList = {}



local OreDatabase = {

["Stonewake"] = {

"Stone", "Sand Stone", "Copper", "Iron", "Tin", "Silver", "Gold",

"Mushroomite", "Platinum", "Bananite", "Cardboardite", "Aite", "Poopite"

},

["Forgotten"] = {

"Cobalt", "Titanium", "Lapis Lazuli", "Volcanic Rock", "Quartz", "Amethyst",

"Topaz", "Diamond", "Sapphire", "Boneite", "Slimite", "Dark Boneite",

"Cuprite", "Obsidian", "Emerald", "Ruby", "Rivalite", "Uranium", "Mythril",

"Eye Ore", "Fireite", "Magmaite", "Lightite", "Demonite", "Darkryte"

},

["Goblin"] = {

"Blue Crystal", "Orange Crystal", "Green Crystal", "Purple Crystal",

"Crimson Crystal", "Rainbow Crystal", "Arcane Crystal"

}

}



local Config = {

DebugMode = false,

FolderName = "Rocks",

ToolName = "Pickaxe",


-- MINING

MineDistance = 10,

UnderOffset = 7,

ClickDelay = 0.25, -- Seconds between clicks


-- FILTER

FilterEnabled = false,

FilterWhitelist = {},


-- SYSTEM

AutoScanRate = 1,

SkyHeight = 500,


MainEnabled = false,

EspEnabled = false,

TravelSpeed = 300,

InstantTP_Range = 60,

AutoEquip = false,


EspTextColor = Color3.fromRGB(100, 255, 100),

EspTextSize = 16,

}



local MainUI = {

X = 100, Y = 100, Width = 250, BaseHeight = 160, Visible = true,

Dragging = false, DragOffset = {x = 0, y = 0},

-- Toggle Button at Y=500

ToggleBtn = { X = 0, Y = 500, W = 40, H = 40 }

}



local FilterUI = {

X = 400, Y = 100, Width = 250, BaseHeight = 200, Visible = false,

Dragging = false, DragOffset = {x = 0, y = 0},

CurrentCategory = "Stonewake"

}



local Colors = {

Bg = Color3.fromRGB(30, 30, 30), Header = Color3.fromRGB(45, 45, 45),

Text = Color3.fromRGB(255, 255, 255), On = Color3.fromRGB(0, 255, 100),

Off = Color3.fromRGB(255, 50, 50), Btn = Color3.fromRGB(60, 60, 60),

Lava = Color3.fromRGB(255, 100, 0), Gold = Color3.fromRGB(255, 200, 0),

Debug = Color3.fromRGB(255, 0, 255)

}



local LocalPlayer = Players.LocalPlayer

local CurrentTarget = nil

local MouseState = { WasPressed = false }

local EquipDebounce = 0

local LastMineClick = 0



-- ============================================================================

-- 2. SAFETY HELPERS (LAG FIX SECTION)

-- ============================================================================



local function IsValid(Obj)

if not Obj then return false end

local success, parent = pcall(function() return Obj.Parent end)

return success and parent ~= nil

end



local function SafeGetAttribute(Obj, Attr)

if not IsValid(Obj) then return nil end

local s, r = pcall(function() return Obj:GetAttribute(Attr) end)

if s then return r end

return nil

end



local function SafeGetName(Obj)

if not IsValid(Obj) then return nil end

local s, n = pcall(function() return Obj.Name end)

return s and n or nil

end



local function GetRockHealth(Rock)

local H = SafeGetAttribute(Rock, "Health")

return (H and tonumber(H)) or 0

end



local function GetRockMaxHealth(Rock)

local H = SafeGetAttribute(Rock, "MaxHealth")

return (H and tonumber(H)) or 0

end



local function GetOreType(Rock)

return SafeGetAttribute(Rock, "Ore")

end



local function GetPosition(Obj)

if not IsValid(Obj) then return nil end

local success, pos = pcall(function()

if Obj.ClassName == "Model" then

if Obj.PrimaryPart then return Obj.PrimaryPart.Position end

local kids = Obj:GetChildren()

for i=1, #kids do

local child = kids[i]

if string.find(child.ClassName, "Part") or child.ClassName == "MeshPart" then return child.Position end

end

elseif string.find(Obj.ClassName, "Part") or Obj.ClassName == "UnionOperation" then

return Obj.Position

end

end)

return success and pos or nil

end



-- SMART MATCHING

local function IsOreWanted(CurrentOre)

if not CurrentOre then return false end

CurrentOre = tostring(CurrentOre)


if Config.FilterWhitelist[CurrentOre] then return true end


local NoSpace = string.gsub(CurrentOre, " ", "")

if Config.FilterWhitelist[NoSpace] then return true end


for whitelistedOre, enabled in pairs(Config.FilterWhitelist) do

if enabled then

local CleanWL = string.gsub(whitelistedOre, " ", "")

if CleanWL == NoSpace then return true end

end

end


return false

end



local function GarbageCollect()

-- Clean Rocks List

for i = #ActiveRocks, 1, -1 do

if not IsValid(ActiveRocks[i]) then table.remove(ActiveRocks, i) end

end

-- Clean Ores List

for i = #ActiveOres, 1, -1 do

if not IsValid(ActiveOres[i]) then table.remove(ActiveOres, i) end

end


if CurrentTarget then

if not IsValid(CurrentTarget) or GetRockHealth(CurrentTarget) <= 0 then

CurrentTarget = nil

end

end

end



-- ============================================================================

-- 3. INTERACTION & MOVEMENT

-- ============================================================================



local function IsMouseInRect(MousePos, RectX, RectY, RectW, RectH)

return MousePos.x >= RectX and MousePos.x <= RectX + RectW and

MousePos.y >= RectY and MousePos.y <= RectY + RectH

end



local function CheckClick()

local IsPressed = false

if isleftpressed then IsPressed = isleftpressed()

elseif UserInputService then

pcall(function() IsPressed = UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1) end)

end

if IsPressed and not MouseState.WasPressed then MouseState.WasPressed = true return true end

MouseState.WasPressed = IsPressed

return false

end



local function FindNearestRock()

local Char = LocalPlayer.Character

if not Char then return nil end

local Root = Char:FindFirstChild("HumanoidRootPart")

if not Root then return nil end


local MyPos = Root.Position

local Closest = nil

local MinDist = 999999



for _, Rock in ipairs(ActiveRocks) do

local RName = SafeGetName(Rock)

if RName and EnabledRocks[RName] == true then

local HP = GetRockHealth(Rock)

local MaxHP = GetRockMaxHealth(Rock)

local IsFresh = (MaxHP > 0 and HP >= MaxHP) or (MaxHP == 0 and HP > 0)


if IsFresh then

local Pos = GetPosition(Rock)

if Pos then

local Dist = vector.magnitude(Pos - MyPos)

if Dist < MinDist then

MinDist = Dist

Closest = Rock

end

end

end

end

end

return Closest

end



local function CheckAutoEquip(Character)

if not Config.AutoEquip then return end

if os.clock() - EquipDebounce < 1 then return end

local Tool = Character:FindFirstChild(Config.ToolName)

if not Tool then

local Backpack = LocalPlayer.Backpack

if Backpack and Backpack:FindFirstChild(Config.ToolName) then

if keypress then keypress(49) keyrelease(49)

else

VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.One, false, game)

VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.One, false, game)

end

EquipDebounce = os.clock()

end

end

end



local function SkyHopMove(RootPart, GoalPos, DeltaTime)

local CurrentPos = RootPart.Position

local Diff = GoalPos - CurrentPos

local Dist = vector.magnitude(Diff)


if Dist <= Config.InstantTP_Range then

RootPart.CFrame = CFrame.new(GoalPos.x, GoalPos.y, GoalPos.z)

return true

end


if CurrentPos.y < Config.SkyHeight - 10 then

RootPart.CFrame = CFrame.new(CurrentPos.x, Config.SkyHeight, CurrentPos.z)

RootPart.Velocity = vector.zero

return false

end


local FlatDiff = vector.create(GoalPos.x - CurrentPos.x, 0, GoalPos.z - CurrentPos.z)

local FlatDist = vector.magnitude(FlatDiff)


if FlatDist < 15 then

RootPart.CFrame = CFrame.new(GoalPos.x, GoalPos.y, GoalPos.z)

RootPart.Velocity = vector.zero

return false

end


local Step = Config.TravelSpeed * DeltaTime

local Direction = vector.normalize(FlatDiff)

local MoveVec = Direction * Step

local NewPos = CurrentPos + MoveVec


RootPart.CFrame = CFrame.new(NewPos.x, Config.SkyHeight, NewPos.z)

RootPart.Velocity = vector.zero

return false

end



-- ============================================================================

-- 4. SCANNERS (MINING & ESP)

-- ============================================================================



-- Mining Scanner

local function PerformScan()

local Folder = Workspace:FindFirstChild(Config.FolderName)

if not Folder then return end

local FoundInstances = {}

local Success, AllObjects = pcall(function() return Folder:GetDescendants() end)


if Success and AllObjects then

for _, Obj in ipairs(AllObjects) do

if Obj.ClassName == "Model" then

if GetRockHealth(Obj) > 0 then

table.insert(FoundInstances, Obj)

local N = SafeGetName(Obj)

if N and not RockNamesSet[N] then

RockNamesSet[N] = true

table.insert(RockList, N)

table.sort(RockList)

if EnabledRocks[N] == nil then EnabledRocks[N] = false end

end

end

end

end

ActiveRocks = FoundInstances

end

end



-- Ore Scanner

task.spawn(function()

while true do

PerformScan()


if Config.EspEnabled then

local FoundOres = {}

local Folder = Workspace:FindFirstChild(Config.FolderName)

if Folder then

local Success, Descendants = pcall(function() return Folder:GetDescendants() end)

if Success and Descendants then

for _, Obj in ipairs(Descendants) do

if Obj.Name == "Ore" then

table.insert(FoundOres, Obj)

end

end

ActiveOres = FoundOres

end

end

else

ActiveOres = {}

end


task.wait(Config.AutoScanRate)

end

end)



-- ============================================================================

-- 5. RENDER LOOP (DUAL WINDOW UI)

-- ============================================================================



local function DrawButton(UI_Obj, RelX, RelY, Width, Height, Text, Color, IsToggle)

DrawingImmediate.FilledRectangle(vector.create(UI_Obj.X + RelX, UI_Obj.Y + RelY, 0), vector.create(Width, Height, 0), Color, 1)

DrawingImmediate.Text(vector.create(UI_Obj.X + RelX + (Width/2) - (IsToggle and 0 or (#Text*3)), UI_Obj.Y + RelY + 5, 0), 16, Colors.Text, 1, Text, true, nil)

end



local function UpdateLoop()

GarbageCollect()

local DeltaTime = 0.03

local MousePos = getmouseposition()

local Clicked = CheckClick()

local IsLeftDown = false

if isleftpressed then IsLeftDown = isleftpressed() end



-- --- DRAG LOGIC ---

if IsLeftDown then

if not MainUI.Dragging and not FilterUI.Dragging then

if MainUI.Visible and IsMouseInRect(MousePos, MainUI.X, MainUI.Y, MainUI.Width, 30) then

MainUI.Dragging = true; MainUI.DragOffset.x = MousePos.x - MainUI.X; MainUI.DragOffset.y = MousePos.y - MainUI.Y

elseif FilterUI.Visible and IsMouseInRect(MousePos, FilterUI.X, FilterUI.Y, FilterUI.Width, 30) then

FilterUI.Dragging = true; FilterUI.DragOffset.x = MousePos.x - FilterUI.X; FilterUI.DragOffset.y = MousePos.y - FilterUI.Y

end

end

if MainUI.Dragging then MainUI.X = MousePos.x - MainUI.DragOffset.x; MainUI.Y = MousePos.y - MainUI.DragOffset.y end

if FilterUI.Dragging then FilterUI.X = MousePos.x - FilterUI.DragOffset.x; FilterUI.Y = MousePos.y - FilterUI.DragOffset.y end

else

MainUI.Dragging = false; FilterUI.Dragging = false

end



-- TOGGLE BUTTON

DrawingImmediate.FilledRectangle(vector.create(MainUI.ToggleBtn.X, MainUI.ToggleBtn.Y, 0), vector.create(MainUI.ToggleBtn.W, MainUI.ToggleBtn.H, 0), MainUI.Visible and Colors.On or Colors.Off, 1)

-- ADDED TEXT: "Ore"

DrawingImmediate.Text(vector.create(MainUI.ToggleBtn.X + 20, MainUI.ToggleBtn.Y + 12, 0), 14, Color3.new(0,0,0), 1, "Ore", true, nil)


if Clicked and IsMouseInRect(MousePos, MainUI.ToggleBtn.X, MainUI.ToggleBtn.Y, MainUI.ToggleBtn.W, MainUI.ToggleBtn.H) then MainUI.Visible = not MainUI.Visible end



-- ===========================

-- MAIN WINDOW

-- ===========================

if MainUI.Visible then

local ItemCount = math.max(1, #RockList)

local TotalHeight = MainUI.BaseHeight + (ItemCount * 22) + 20

DrawingImmediate.FilledRectangle(vector.create(MainUI.X, MainUI.Y, 0), vector.create(MainUI.Width, TotalHeight, 0), Colors.Bg, 0.95)

DrawingImmediate.FilledRectangle(vector.create(MainUI.X, MainUI.Y, 0), vector.create(MainUI.Width, 30, 0), Colors.Header, 1)

DrawingImmediate.OutlinedText(vector.create(MainUI.X + 10, MainUI.Y + 8, 0), 16, Colors.Text, 1, "Ore Farm", false, nil)


local Y = 35

local function MainBtn(Txt, Col, Act)

DrawingImmediate.FilledRectangle(vector.create(MainUI.X + 10, MainUI.Y + Y, 0), vector.create(230, 25, 0), Col, 1)

DrawingImmediate.Text(vector.create(MainUI.X + 20, MainUI.Y + Y + 5, 0), 16, Colors.Text, 1, Txt, false, nil)

if Clicked and IsMouseInRect(MousePos, MainUI.X + 10, MainUI.Y + Y, 230, 25) then Act() end

Y = Y + 30

end



MainBtn(Config.MainEnabled and "FARMING: ON" or "FARMING: OFF", Config.MainEnabled and Colors.On or Colors.Off, function() Config.MainEnabled = not Config.MainEnabled; CurrentTarget = nil end)


MainBtn(Config.EspEnabled and "ORE ESP: ON" or "ORE ESP: OFF", Config.EspEnabled and Colors.On or Colors.Off, function() Config.EspEnabled = not Config.EspEnabled end)


MainBtn(Config.AutoEquip and "Auto Equip: ON" or "Auto Equip: OFF", Config.AutoEquip and Colors.On or Colors.Off, function() Config.AutoEquip = not Config.AutoEquip end)

MainBtn(FilterUI.Visible and "Close Filter Menu" or "Open Filter Menu", Colors.Gold, function() FilterUI.Visible = not FilterUI.Visible end)



Y = Y + 10

DrawingImmediate.OutlinedText(vector.create(MainUI.X + 10, MainUI.Y + Y, 0), 14, Colors.Text, 1, "Select Rocks to Farm:", false, nil)

Y = Y + 20


for i, Name in ipairs(RockList) do

local IsOn = EnabledRocks[Name]

DrawingImmediate.FilledRectangle(vector.create(MainUI.X + 10, MainUI.Y + Y, 0), vector.create(230, 20, 0), IsOn and Colors.On or Colors.Off, 1)

DrawingImmediate.Text(vector.create(MainUI.X + 20, MainUI.Y + Y + 2, 0), 14, Colors.Text, 1, Name, false, nil)

if Clicked and IsMouseInRect(MousePos, MainUI.X + 10, MainUI.Y + Y, 230, 20) then

EnabledRocks[Name] = not EnabledRocks[Name]

CurrentTarget = nil

end

Y = Y + 22

end

end



-- ===========================

-- FILTER WINDOW

-- ===========================

if FilterUI.Visible then

local CatList = OreDatabase[FilterUI.CurrentCategory] or {}

local F_TotalHeight = FilterUI.BaseHeight + (#CatList * 22)

DrawingImmediate.FilledRectangle(vector.create(FilterUI.X, FilterUI.Y, 0), vector.create(FilterUI.Width, F_TotalHeight, 0), Colors.Bg, 0.95)

DrawingImmediate.FilledRectangle(vector.create(FilterUI.X, FilterUI.Y, 0), vector.create(FilterUI.Width, 30, 0), Colors.Header, 1)

DrawingImmediate.OutlinedText(vector.create(FilterUI.X + 10, FilterUI.Y + 8, 0), 16, Colors.Text, 1, "Ore Filter", false, nil)


local FY = 35

local F_Txt = Config.FilterEnabled and "FILTER: ACTIVE" or "FILTER: DISABLED"

local F_Col = Config.FilterEnabled and Colors.On or Colors.Off

DrawingImmediate.FilledRectangle(vector.create(FilterUI.X + 10, FilterUI.Y + FY, 0), vector.create(230, 25, 0), F_Col, 1)

DrawingImmediate.Text(vector.create(FilterUI.X + 60, FilterUI.Y + FY + 5, 0), 16, Colors.Text, 1, F_Txt, false, nil)

if Clicked and IsMouseInRect(MousePos, FilterUI.X + 10, FilterUI.Y + FY, 230, 25) then Config.FilterEnabled = not Config.FilterEnabled end

FY = FY + 35



local btnW = 73

local Cats = {"Stonewake", "Forgotten", "Goblin"}

for i, Cat in ipairs(Cats) do

local bx = FilterUI.X + 10 + ((i-1) * (btnW + 5))

local isSel = FilterUI.CurrentCategory == Cat

DrawingImmediate.FilledRectangle(vector.create(bx, FilterUI.Y + FY, 0), vector.create(btnW, 25, 0), isSel and Colors.Gold or Colors.Btn, 1)

DrawingImmediate.Text(vector.create(bx + 5, FilterUI.Y + FY + 5, 0), 14, Colors.Text, 1, Cat, false, nil)

if Clicked and IsMouseInRect(MousePos, bx, FilterUI.Y + FY, btnW, 25) then FilterUI.CurrentCategory = Cat end

end

FY = FY + 35



DrawingImmediate.OutlinedText(vector.create(FilterUI.X + 10, FilterUI.Y + FY, 0), 14, Colors.Text, 1, "Keep these ores:", false, nil)

FY = FY + 20



for _, OreName in ipairs(CatList) do

local IsWhitelisted = Config.FilterWhitelist[OreName]

DrawingImmediate.FilledRectangle(vector.create(FilterUI.X + 10, FilterUI.Y + FY, 0), vector.create(230, 20, 0), IsWhitelisted and Colors.On or Colors.Off, 1)

DrawingImmediate.Text(vector.create(FilterUI.X + 20, FilterUI.Y + FY + 2, 0), 14, Colors.Text, 1, OreName, false, nil)

if Clicked and IsMouseInRect(MousePos, FilterUI.X + 10, FilterUI.Y + FY, 230, 20) then

Config.FilterWhitelist[OreName] = not Config.FilterWhitelist[OreName]

CurrentTarget = nil

end

FY = FY + 22

end

end



-- ===========================

-- ORE ESP LOGIC

-- ===========================

if Config.EspEnabled then

for _, OreObj in ipairs(ActiveOres) do

if IsValid(OreObj) then

local OreName = SafeGetAttribute(OreObj, "Ore")

if OreName then

local Pos = GetPosition(OreObj)

if Pos then

local ScreenPos, Visible = Camera:WorldToScreenPoint(Pos)

if Visible then

DrawingImmediate.OutlinedText(

vector.create(ScreenPos.X, ScreenPos.Y, 0),

Config.EspTextSize,

Config.EspTextColor,

1,

"[" .. tostring(OreName) .. "]",

true,

nil

)

end

end

end

end

end

end



-- C. FARM LOGIC

local Char = LocalPlayer.Character

if Char then CheckAutoEquip(Char) end



if Char and Char:FindFirstChild("HumanoidRootPart") then

local MyRoot = Char.HumanoidRootPart


if Config.MainEnabled then

if CurrentTarget then

if not IsValid(CurrentTarget) then CurrentTarget = nil return end


local HP = GetRockHealth(CurrentTarget)

if HP <= 0 then CurrentTarget = nil return end



local MaxHP = GetRockMaxHealth(CurrentTarget)

local OrePos = GetPosition(CurrentTarget)

if not OrePos then CurrentTarget = nil return end


local DistToRock = vector.magnitude(MyRoot.Position - OrePos)

if DistToRock > 15 and MaxHP > 0 and HP < MaxHP then

CurrentTarget = nil

return

end



-- ====== MULTI-ORE FILTER LOGIC ======

if Config.FilterEnabled then

local FoundOres = {} -- Stores names of revealed ores

local UnrevealedOreCount = 0

local HasValuableOre = false


local success, Children = pcall(function() return CurrentTarget:GetChildren() end)


if success and Children then

for _, Child in ipairs(Children) do

if Child.Name == "Ore" then

local OreAttr = GetOreType(Child) -- Get Attribute

if OreAttr and OreAttr ~= "" and OreAttr ~= "None" then

table.insert(FoundOres, tostring(OreAttr))

if IsOreWanted(OreAttr) then

HasValuableOre = true

end

else

UnrevealedOreCount = UnrevealedOreCount + 1

end

end

end

end


local MainOreAttr = GetOreType(CurrentTarget)

if MainOreAttr and MainOreAttr ~= "" and MainOreAttr ~= "None" then

table.insert(FoundOres, tostring(MainOreAttr))

if IsOreWanted(MainOreAttr) then HasValuableOre = true end

end



-- DECISION LOGIC

if not HasValuableOre and UnrevealedOreCount == 0 and #FoundOres > 0 then

CurrentTarget = nil

return

end

end

-- ==================================



-- MOVE & MINE

local GoalPos = vector.create(OrePos.x, OrePos.y - Config.UnderOffset, OrePos.z)

local Diff = MyRoot.Position - GoalPos

local Dist = vector.magnitude(Diff)


if Dist > Config.MineDistance then

SkyHopMove(MyRoot, GoalPos, DeltaTime)

else

if GetRockHealth(CurrentTarget) > 0 then

local LookAt = Vector3.new(OrePos.x, OrePos.y, OrePos.z)

local Pos = Vector3.new(GoalPos.x, GoalPos.y, GoalPos.z)

MyRoot.CFrame = CFrame.lookAt(Pos, LookAt)

MyRoot.Velocity = vector.zero


-- CLICK LOGIC WITH DELAY

if os.clock() - LastMineClick > Config.ClickDelay then

if mouse1click then mouse1click() end

LastMineClick = os.clock()

end

else

CurrentTarget = nil

end

end

else

CurrentTarget = FindNearestRock()

end

end

end

end



-- ============================================================================

-- FAIL-SAFE CONNECTIONS

-- ============================================================================

local Connected = false

if RunService then

pcall(function() RunService.Heartbeat:Connect(UpdateLoop); Connected = true end)

if not Connected then pcall(function() RunService.RenderStepped:Connect(UpdateLoop); Connected = true end) end

if not Connected then pcall(function() RunService.Render:Connect(UpdateLoop); Connected = true end) end

end



if not Connected then

warn("Using Manual Loop")

task.spawn(function() while true do UpdateLoop() task.wait(0.03) end end)

end
