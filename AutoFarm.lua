-- Services
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local Camera = Workspace.CurrentCamera

-- ============================================================================
-- 1. CONFIGURATION & STATE
-- ============================================================================

local MobList = {}             
local EnabledMobs = {}         

local Config = {
    TargetFolder = "Living",
    RocksFolder = Workspace:WaitForChild("Rocks"), -- Added for Ore ESP
    UnderOffset = 8,
    AttackDistance = 8,
    
    -- Sky Hop Settings
    SkyHeight = 500,       
    
    -- Variables controlled by GUI
    MainEnabled = false,       
    OreEspEnabled = false,     -- New Toggle
    TravelSpeed = 300,     
    InstantTP_Range = 70,
    AutoEquip = false,
    
    -- ESP Settings
    EspColor = Color3.fromRGB(100, 255, 100),
    EspSize = 16
}

local UI = {
    X = 100, Y = 100,
    Width = 250, 
    BaseHeight = 160, 
    Visible = true,
    
    ToggleBtn = { X = 0, Y = 300, W = 40, H = 40 },
    Dragging = false,
    DragOffset = {x = 0, y = 0},
    
    BgColor = Color3.fromRGB(30, 30, 30),
    HeaderColor = Color3.fromRGB(45, 45, 45),
    TextColor = Color3.fromRGB(255, 255, 255),
    OnColor = Color3.fromRGB(0, 255, 100),
    OffColor = Color3.fromRGB(255, 50, 50),
    BtnColor = Color3.fromRGB(60, 60, 60),
    LavaColor = Color3.fromRGB(255, 100, 0),
    EspColor = Color3.fromRGB(100, 200, 255) -- Blue for ESP Button
}

local LocalPlayer = Players.LocalPlayer
local CurrentTarget = nil
local MouseState = { WasPressed = false }
local EquipDebounce = 0
local GoingToLava = false 

-- Ore ESP State
local ActiveOres = {}

-- ============================================================================
-- 2. HELPER FUNCTIONS
-- ============================================================================

local function IsMouseInRect(MousePos, RectX, RectY, RectW, RectH)
    return MousePos.x >= RectX and MousePos.x <= RectX + RectW and
           MousePos.y >= RectY and MousePos.y <= RectY + RectH
end

local function CheckClick()
    local IsPressed = false
    if isleftpressed then IsPressed = isleftpressed() end
    local Result = false
    if IsPressed and not MouseState.WasPressed then Result = true end
    MouseState.WasPressed = IsPressed
    return Result
end

local function GetBaseName(Name)
    local Base = string.match(Name, "^(.-)%d*$")
    return (Base and Base ~= "") and Base or Name
end

local function RefreshMobList()
    local Folder = Workspace:FindFirstChild(Config.TargetFolder)
    if not Folder then MobList = {} return end
    
    local Unique = {}
    local NewList = {}
    
    for _, Child in ipairs(Folder:GetChildren()) do
        if Players:FindFirstChild(Child.Name) then continue end
        if Child.ClassName == "Model" and Child:FindFirstChild("Humanoid") then
            local BaseName = GetBaseName(Child.Name)
            if not Unique[BaseName] then
                Unique[BaseName] = true
                table.insert(NewList, BaseName)
                if EnabledMobs[BaseName] == nil then EnabledMobs[BaseName] = false end
            end
        end
    end
    table.sort(NewList)
    MobList = NewList
end

local function IsAlive(Model)
    if not Model then return false end
    local Humanoid = Model:FindFirstChild("Humanoid")
    local RootPart = Model:FindFirstChild("HumanoidRootPart")
    if Humanoid and RootPart and Humanoid.Health > 0 then return true end
    return false
end

local function FindTarget()
    local LivingFolder = Workspace:FindFirstChild(Config.TargetFolder)
    if not LivingFolder then return nil end
    for _, Mob in ipairs(LivingFolder:GetChildren()) do
        local BaseName = GetBaseName(Mob.Name)
        if EnabledMobs[BaseName] == true and IsAlive(Mob) then
            return Mob
        end
    end
    return nil
end

local function CheckAutoEquip(Character)
    if not Config.AutoEquip then return end
    if os.clock() - EquipDebounce < 1 then return end
    
    if not Character:FindFirstChild("Weapon") then
        local Backpack = LocalPlayer.Backpack
        if Backpack and Backpack:FindFirstChild("Weapon") then
            if keypress then
                keypress(50) 
                keyrelease(50)
                EquipDebounce = os.clock() 
            end
        end
    end
end

-- ESP Helper: Get Position
local function GetOrePosition(Obj)
    if not Obj then return nil end

    if Obj.ClassName == "Model" then
        if Obj.PrimaryPart then
            return Obj.PrimaryPart.Position
        else
            for _, Child in ipairs(Obj:GetChildren()) do
                if string.find(Child.ClassName, "Part") then
                    return Child.Position
                end
            end
        end
    elseif string.find(Obj.ClassName, "Part") then
        return Obj.Position
    end
    return nil
end

local function SkyHopMove(RootPart, GoalPos, DeltaTime)
    local CurrentPos = RootPart.Position
    local Diff = GoalPos - CurrentPos
    local Dist = vector.magnitude(Diff)
    
    -- INSTANT CHECK
    if Dist <= Config.InstantTP_Range then
        RootPart.CFrame = CFrame.new(GoalPos.x, GoalPos.y, GoalPos.z)
        return true
    end
    
    -- VERTICAL
    if CurrentPos.y < Config.SkyHeight - 10 then
        RootPart.CFrame = CFrame.new(CurrentPos.x, Config.SkyHeight, CurrentPos.z)
        RootPart.Velocity = vector.zero
        return false
    end
    
    -- HORIZONTAL
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
-- 3. BACKGROUND TASKS (Scanner)
-- ============================================================================

-- Ore Scanner Loop
task.spawn(function()
    while true do
        if Config.OreEspEnabled then
            local Found = {}
            local Success, Descendants = pcall(function() return Config.RocksFolder:GetDescendants() end)
            
            if Success and Descendants then
                for _, Obj in ipairs(Descendants) do
                    if Obj.Name == "Ore" then
                        table.insert(Found, Obj)
                    end
                end
                ActiveOres = Found 
            end
        else
            ActiveOres = {} -- Clear list if disabled to save FPS
        end
        task.wait(1) -- Scan rate
    end
end)

-- ============================================================================
-- 4. MAIN LOOP
-- ============================================================================
RunService.Render:Connect(function()
    local DeltaTime = 0.03
    local MousePos = getmouseposition()
    local Clicked = CheckClick()
    local IsLeftDown = false
    if isleftpressed then IsLeftDown = isleftpressed() end

    -- Drag Logic
    if IsLeftDown then
        if not UI.Dragging then
            if UI.Visible and IsMouseInRect(MousePos, UI.X, UI.Y, UI.Width, 30) then
                UI.Dragging = true
                UI.DragOffset.x = MousePos.x - UI.X
                UI.DragOffset.y = MousePos.y - UI.Y
            end
        else
            UI.X = MousePos.x - UI.DragOffset.x
            UI.Y = MousePos.y - UI.DragOffset.y
        end
    else
        UI.Dragging = false
    end

    -- Draw GUI Toggle Button
    local ToggleColor = UI.Visible and UI.OnColor or UI.OffColor
    DrawingImmediate.FilledRectangle(vector.create(UI.ToggleBtn.X, UI.ToggleBtn.Y, 0), vector.create(UI.ToggleBtn.W, UI.ToggleBtn.H, 0), ToggleColor, 1)
    DrawingImmediate.Text(vector.create(UI.ToggleBtn.X + 10, UI.ToggleBtn.Y + 10, 0), 20, Color3.new(0,0,0), 1, UI.Visible and "<<" or ">>", true, nil)
    
    if Clicked and IsMouseInRect(MousePos, UI.ToggleBtn.X, UI.ToggleBtn.Y, UI.ToggleBtn.W, UI.ToggleBtn.H) then
        UI.Visible = not UI.Visible
    end

    -- Draw Main UI
    if UI.Visible then
        local ItemCount = math.max(1, #MobList)
        local ListHeight = ItemCount * 22
        local ExtraH = 105 -- Increased height for ESP Button + Lava
        local TotalHeight = UI.BaseHeight + ListHeight + 20 + ExtraH
        
        DrawingImmediate.FilledRectangle(vector.create(UI.X, UI.Y, 0), vector.create(UI.Width, TotalHeight, 0), UI.BgColor, 0.95)
        DrawingImmediate.FilledRectangle(vector.create(UI.X, UI.Y, 0), vector.create(UI.Width, 30, 0), UI.HeaderColor, 1)
        DrawingImmediate.OutlinedText(vector.create(UI.X + 10, UI.Y + 8, 0), 16, UI.TextColor, 1, "Mob & Ore Farm", false, nil)
        
        local Y_Offset = UI.Y + 35

        -- 1. Master Switch
        local MasterColor = Config.MainEnabled and UI.OnColor or UI.OffColor
        DrawingImmediate.FilledRectangle(vector.create(UI.X + 10, Y_Offset, 0), vector.create(230, 25, 0), MasterColor, 1)
        DrawingImmediate.Text(vector.create(UI.X + 125, Y_Offset + 5, 0), 16, Color3.new(0,0,0), 1, Config.MainEnabled and "FARMING: ON" or "FARMING: OFF", true, nil)
        
        if Clicked and IsMouseInRect(MousePos, UI.X + 10, Y_Offset, 230, 25) then
            Config.MainEnabled = not Config.MainEnabled
            if not Config.MainEnabled then CurrentTarget = nil end
            if Config.MainEnabled then GoingToLava = false end
        end
        Y_Offset = Y_Offset + 30

        -- 2. Ore ESP Toggle (NEW)
        local EspColorBtn = Config.OreEspEnabled and UI.OnColor or UI.EspColor
        DrawingImmediate.FilledRectangle(vector.create(UI.X + 10, Y_Offset, 0), vector.create(230, 25, 0), EspColorBtn, 1)
        DrawingImmediate.Text(vector.create(UI.X + 125, Y_Offset + 5, 0), 16, Color3.new(0,0,0), 1, Config.OreEspEnabled and "ORE ESP: ON" or "ORE ESP: OFF", true, nil)
        
        if Clicked and IsMouseInRect(MousePos, UI.X + 10, Y_Offset, 230, 25) then
            Config.OreEspEnabled = not Config.OreEspEnabled
        end
        Y_Offset = Y_Offset + 30

        -- 3. Auto Equip
        local EqColor = Config.AutoEquip and UI.OnColor or UI.OffColor
        local EqText = Config.AutoEquip and "Auto-Equip (Slot 2): ON" or "Auto-Equip (Slot 2): OFF"
        DrawingImmediate.FilledRectangle(vector.create(UI.X + 10, Y_Offset, 0), vector.create(230, 25, 0), EqColor, 1)
        DrawingImmediate.Text(vector.create(UI.X + 125, Y_Offset + 5, 0), 14, Color3.new(0,0,0), 1, EqText, true, nil)
        
        if Clicked and IsMouseInRect(MousePos, UI.X + 10, Y_Offset, 230, 25) then
            Config.AutoEquip = not Config.AutoEquip
        end
        Y_Offset = Y_Offset + 30

        -- 4. Speed Controls
        DrawingImmediate.OutlinedText(vector.create(UI.X + 10, Y_Offset, 0), 14, UI.TextColor, 1, "Speed: " .. math.floor(Config.TravelSpeed), false, nil)
        DrawingImmediate.FilledRectangle(vector.create(UI.X + 150, Y_Offset, 0), vector.create(40, 18, 0), UI.BtnColor, 1)
        DrawingImmediate.Text(vector.create(UI.X + 170, Y_Offset, 0), 14, UI.TextColor, 1, "-", true, nil)
        if Clicked and IsMouseInRect(MousePos, UI.X + 150, Y_Offset, 40, 18) then Config.TravelSpeed = math.max(10, Config.TravelSpeed - 5) end
        DrawingImmediate.FilledRectangle(vector.create(UI.X + 200, Y_Offset, 0), vector.create(40, 18, 0), UI.BtnColor, 1)
        DrawingImmediate.Text(vector.create(UI.X + 220, Y_Offset, 0), 14, UI.TextColor, 1, "+", true, nil)
        if Clicked and IsMouseInRect(MousePos, UI.X + 200, Y_Offset, 40, 18) then Config.TravelSpeed = Config.TravelSpeed + 5 end
        Y_Offset = Y_Offset + 22

        -- 5. Range Controls
        DrawingImmediate.OutlinedText(vector.create(UI.X + 10, Y_Offset, 0), 14, UI.TextColor, 1, "TP Range: " .. math.floor(Config.InstantTP_Range), false, nil)
        DrawingImmediate.FilledRectangle(vector.create(UI.X + 150, Y_Offset, 0), vector.create(40, 18, 0), UI.BtnColor, 1)
        DrawingImmediate.Text(vector.create(UI.X + 170, Y_Offset, 0), 14, UI.TextColor, 1, "-", true, nil)
        if Clicked and IsMouseInRect(MousePos, UI.X + 150, Y_Offset, 40, 18) then Config.InstantTP_Range = math.max(0, Config.InstantTP_Range - 5) end
        DrawingImmediate.FilledRectangle(vector.create(UI.X + 200, Y_Offset, 0), vector.create(40, 18, 0), UI.BtnColor, 1)
        DrawingImmediate.Text(vector.create(UI.X + 220, Y_Offset, 0), 14, UI.TextColor, 1, "+", true, nil)
        if Clicked and IsMouseInRect(MousePos, UI.X + 200, Y_Offset, 40, 18) then Config.InstantTP_Range = Config.InstantTP_Range + 5 end
        Y_Offset = Y_Offset + 25

        -- 6. Refresh List
        DrawingImmediate.FilledRectangle(vector.create(UI.X + 10, Y_Offset, 0), vector.create(230, 20, 0), Color3.fromRGB(80, 80, 150), 1)
        DrawingImmediate.Text(vector.create(UI.X + 125, Y_Offset + 3, 0), 14, UI.TextColor, 1, "Refresh Mob List", true, nil)
        if Clicked and IsMouseInRect(MousePos, UI.X + 10, Y_Offset, 230, 20) then RefreshMobList() end
        Y_Offset = Y_Offset + 25

        -- 7. Mob List
        DrawingImmediate.OutlinedText(vector.create(UI.X + 10, Y_Offset, 0), 14, Color3.fromRGB(150,150,150), 1, "Click Name to Enable:", false, nil)
        Y_Offset = Y_Offset + 22

        if #MobList == 0 then
             DrawingImmediate.OutlinedText(vector.create(UI.X + 10, Y_Offset, 0), 14, Color3.fromRGB(100,100,100), 1, "(Click Refresh to Scan)", false, nil)
             Y_Offset = Y_Offset + 22 
        else
            for i = 1, #MobList do
                local MobName = MobList[i]
                local IsEnabled = EnabledMobs[MobName] == true
                local ItemColor = IsEnabled and UI.OnColor or UI.OffColor
                
                DrawingImmediate.FilledRectangle(vector.create(UI.X + 10, Y_Offset, 0), vector.create(230, 20, 0), ItemColor, 1)
                DrawingImmediate.Text(vector.create(UI.X + 125, Y_Offset + 3, 0), 14, Color3.new(0,0,0), 1, MobName, true, nil)
                
                if Clicked and IsMouseInRect(MousePos, UI.X + 10, Y_Offset, 230, 20) then
                    EnabledMobs[MobName] = not EnabledMobs[MobName]
                    CurrentTarget = nil 
                end
                Y_Offset = Y_Offset + 22
            end
        end

        Y_Offset = Y_Offset + 5
        
        -- 8. Lava Teleport
        local LColor = GoingToLava and UI.OnColor or UI.LavaColor
        local LText = GoingToLava and "Traveling to Lava..." or "Teleport to Lava"
        
        DrawingImmediate.FilledRectangle(vector.create(UI.X + 10, Y_Offset, 0), vector.create(230, 25, 0), LColor, 1)
        DrawingImmediate.OutlinedText(vector.create(UI.X + 125, Y_Offset + 5, 0), 16, UI.TextColor, 1, LText, true, nil)
        
        if Clicked and IsMouseInRect(MousePos, UI.X + 10, Y_Offset, 230, 25) then
            GoingToLava = not GoingToLava
            if GoingToLava then
                Config.MainEnabled = false
                CurrentTarget = nil
            end
        end
    end

    -- DRAW LOGIC: ORE ESP
    if Config.OreEspEnabled then
        for _, OreObj in ipairs(ActiveOres) do
            if OreObj and OreObj.Parent then
                local OreName = OreObj:GetAttribute("Ore")
                if OreName then
                    local Pos = GetOrePosition(OreObj)
                    if Pos then
                        local ScreenPos, Visible = Camera:WorldToScreenPoint(Pos)
                        if Visible then
                            DrawingImmediate.OutlinedText(
                                vector.create(ScreenPos.X, ScreenPos.Y, 0),
                                Config.EspSize,
                                Config.EspColor,
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

    -- LOGIC: Auto Equip
    local Char = LocalPlayer.Character
    if Char then CheckAutoEquip(Char) end

    -- LOGIC: Movement
    if Char and Char:FindFirstChild("HumanoidRootPart") then
        local MyRoot = Char.HumanoidRootPart
        
        if GoingToLava then
            local LavaPos = vector.create(387, 65, 72)
            local Arrived = SkyHopMove(MyRoot, LavaPos, DeltaTime)
            if Arrived then GoingToLava = false end
            
        elseif Config.MainEnabled then
            if CurrentTarget and IsAlive(CurrentTarget) then
                local MobRoot = CurrentTarget.HumanoidRootPart
                local MobPos = MobRoot.Position
                local GoalPos = vector.create(MobPos.x, MobPos.y - Config.UnderOffset, MobPos.z)
                local Diff = MyRoot.Position - GoalPos
                local Dist = vector.magnitude(Diff)
                
                if Dist > Config.AttackDistance then
                    SkyHopMove(MyRoot, GoalPos, DeltaTime)
                else
                    local LookAt = Vector3.new(MobPos.x, MobPos.y, MobPos.z)
                    local Pos = Vector3.new(GoalPos.x, GoalPos.y, GoalPos.z)
                    MyRoot.CFrame = CFrame.lookAt(Pos, LookAt)
                    MyRoot.Velocity = vector.zero
                    mouse1click()
                end
            else
                CurrentTarget = FindTarget()
            end
        end
    end
end)
