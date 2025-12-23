--!optimize 2
loadstring(game:HttpGet("https://raw.githubusercontent.com/Sploiter13/severefuncs/refs/heads/main/merge.lua"))();

-- // SERVICES //
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local Camera = Workspace.CurrentCamera
local VirtualInputManager = game:GetService("VirtualInputManager")
local MouseService = game:GetService("MouseService")

-- Safe Service Get
local UserInputService = nil
pcall(function() UserInputService = game:GetService("UserInputService") end)

-- ============================================================================
-- 1. DATA & CONFIGURATION
-- ============================================================================

local ActiveRocks = {} 
local ActiveOres = {}  
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
    LavaFolder = "Island2VolcanicDepths",
    ToolName = "Pickaxe",        
    
    -- MINING
    MineDistance = 10,        
    UnderOffset = 6,          
    AboveOffset = 6,
    MiningPosition = "Under", 
    ClickDelay = 0.2, 
    
    -- FILTER
    FilterEnabled = false,    
    FilterVolcanicOnly = false,
    FilterWhitelist = {}, 
    
    -- SYSTEM
    AutoScanRate = 1,        
    SkyHeight = 500,        
    
    MainEnabled = false,        
    EspEnabled = false,      
    OnlyLava = false,
    PriorityVolcanic = false,
    TravelSpeed = 270,      
    InstantTP_Range = 55,
    AutoEquip = false,
    
    -- AUTO SELL
    AutoSell = false,
    MerchantPos = Vector3.new(-132.07, 21.61, -20.92),
    SellTimeout = 60,
    
    EspTextColor = Color3.fromRGB(100, 255, 100),
    EspTextSize = 16,
}

local MainUI = {
    X = 100, Y = 100, Width = 250, BaseHeight = 320, Visible = true,
    Dragging = false, DragOffset = {x = 0, y = 0},
    ToggleBtn = { X = 0, Y = 500, W = 40, H = 40 }
}

local FilterUI = {
    X = 400, Y = 100, Width = 250, BaseHeight = 240, Visible = false,
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
local TargetLocked = false

-- STATE MANAGEMENT
local IsSelling = false

-- ============================================================================
-- 2. SAFETY & UI HELPERS
-- ============================================================================

local function IsValid(Obj)
    return Obj and Obj.Parent
end

local function SafeGetAttribute(Obj, Attr)
    if not IsValid(Obj) then return nil end
    return Obj:GetAttribute(Attr)
end

local function SafeGetName(Obj)
    if not IsValid(Obj) then return nil end
    return Obj.Name
end

local function GetRockHealth(Rock)
    if not IsValid(Rock) then return 0 end
    local H = Rock:GetAttribute("Health")
    return (H and tonumber(H)) or 0 
end

local function GetRockMaxHealth(Rock)
    if not IsValid(Rock) then return 0 end
    local H = Rock:GetAttribute("MaxHealth")
    return (H and tonumber(H)) or 0 
end

local function GetPosition(Obj)
    if not IsValid(Obj) then return nil end
    if Obj.ClassName == "Model" then
        if Obj.PrimaryPart then return Obj.PrimaryPart.Position end
        local kids = Obj:GetChildren()
        for i=1, #kids do
            local child = kids[i]
            if child.ClassName == "Part" or child.ClassName == "MeshPart" then 
                return child.Position 
            end
        end
    elseif string.find(Obj.ClassName, "Part") then 
        return Obj.Position 
    end
    return nil
end

local function IsVolcanic(Rock)
    if not IsValid(Rock) then return false end
    local N = Rock.Name
    if N == "Volcanic Rock" then return true end
    local Attr = Rock:GetAttribute("Ore")
    if Attr and tostring(Attr) == "Volcanic Rock" then return true end
    if Rock:FindFirstChild("Volcanic Rock") then return true end
    return false
end

-- // NEW: UI FINDER HELPERS //
local function GetObject(pathStr)
    local segments = pathStr:split(".")
    local current = game
    for i, name in ipairs(segments) do
        if i == 1 and name == "game" then
        elseif current == game and name == "Players" then
            current = Players
        elseif current == Players and name ~= "LocalPlayer" then
            current = current.LocalPlayer
        else
            local nextObj = current:FindFirstChild(name)
            if not nextObj then return nil end
            current = nextObj
        end
    end
    return current
end

local function GetTextMemory(obj)
    if not obj then return "" end
    if memory and memory.readstring then
        return memory.readstring(obj, 3648) or ""
    else
        return obj.Text
    end
end

local function ClickObject(obj)
    if not obj then return false end
    local absPos = obj.AbsolutePosition
    local absSize = obj.AbsoluteSize
    if absPos and absSize then
        local centerX = absPos.X + (absSize.X / 2)
        local centerY = absPos.Y + (absSize.Y / 2)
        if mouse1click and MouseService then
            mouse1click()
            MouseService:SetMouseLocation(centerX, centerY)
            return true
        end
    end
    return false
end

-- ============================================================================
-- 3. INTELLIGENT ORE DETECTION
-- ============================================================================

local function GetRevealedOreType(Rock)
    if not IsValid(Rock) then return nil end
    local Attr = Rock:GetAttribute("Ore")
    if Attr and Attr ~= "" then return tostring(Attr) end
    local OreModel = Rock:FindFirstChild("Ore")
    if OreModel then
        local ChildAttr = OreModel:GetAttribute("Ore")
        if ChildAttr and ChildAttr ~= "" then return tostring(ChildAttr) end
    end
    return nil 
end

-- [FIXED] Robust Filter matching (ignores case and spaces)
local function IsOreWanted(CurrentOre)
    if not CurrentOre then return false end
    
    -- Normalize: Lowercase and remove spaces
    local function Clean(s)
        return string.lower(string.gsub(s, " ", ""))
    end
    
    local Target = Clean(tostring(CurrentOre))
    
    for Name, Enabled in pairs(Config.FilterWhitelist) do
        if Enabled then
            if Clean(Name) == Target then return true end
        end
    end
    return false
end

local function GarbageCollect()
    for i = #ActiveRocks, 1, -1 do
        if not IsValid(ActiveRocks[i]) then table.remove(ActiveRocks, i) end
    end
    for i = #ActiveOres, 1, -1 do
        if not IsValid(ActiveOres[i]) then table.remove(ActiveOres, i) end
    end
    if CurrentTarget then
        if not IsValid(CurrentTarget) or GetRockHealth(CurrentTarget) <= 0 then
            CurrentTarget = nil
            TargetLocked = false
        end
    end
end

-- ============================================================================
-- 4. INTERACTION & MOVEMENT
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

local function FindVolcanicRock()
    local Char = LocalPlayer.Character
    if not Char then return nil end
    local Root = Char:FindFirstChild("HumanoidRootPart")
    if not Root then return nil end
    
    local MyPos = Root.Position
    local Closest = nil
    local MinDist = 999999

    for _, Rock in ipairs(ActiveRocks) do
        if IsVolcanic(Rock) then
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

local function FindNearestRock()
    local Char = LocalPlayer.Character
    if not Char then return nil end
    local Root = Char:FindFirstChild("HumanoidRootPart")
    if not Root then return nil end
    
    local MyPos = Root.Position
    local Closest = nil
    local MinDist = 999999

    if Config.PriorityVolcanic then
        local Volcanic = FindVolcanicRock()
        if Volcanic then return Volcanic end
    end

    for _, Rock in ipairs(ActiveRocks) do
        -- [CRASH FIX] Validation Check before reading properties
        if not IsValid(Rock) then continue end
        
        local RName = Rock.Name
        if RName and EnabledRocks[RName] == true then
            
            local RevealedOre = GetRevealedOreType(Rock)
            local IsValidCandidate = true
            
            if Config.FilterEnabled and RevealedOre then
                local ApplyFilter = true
                
                if Config.FilterVolcanicOnly and not IsVolcanic(Rock) then
                    ApplyFilter = false 
                end
                
                if ApplyFilter then
                    if not IsOreWanted(RevealedOre) then
                        IsValidCandidate = false 
                    end
                end
            end
            
            if IsValidCandidate then
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
-- 5. AUTO SELL SYSTEM
-- ============================================================================

local function PressE()
    if keypress then
        keypress(0x45) 
        task.wait(0.05)
        keyrelease(0x45)
    else
        VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.E, false, game)
        task.wait(0.05)
        VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.E, false, game)
    end
end

local function PerformAutoSell()
    if IsSelling then return end 
    if not Config.AutoSell then return end
    
    -- [FIX] DYNAMIC NAME PATH
    local pName = LocalPlayer.Name
    local Path_Capacity = "game.Players."..pName..".PlayerGui.Menu.Frame.Frame.Menus.Stash.Capacity.Text"
    
    local capObj = GetObject(Path_Capacity)
    
    if not capObj then return end 
    
    local text = GetTextMemory(capObj)
    local current, max = text:match("(%d+)/(%d+)")
    
    if current and max and tonumber(current) >= tonumber(max) then
        IsSelling = true
        CurrentTarget = nil 
        TargetLocked = false
        
        -- FAILSAFE TIMEOUT START
        local StartTime = os.clock()
        local function CheckTimeout()
            if os.clock() - StartTime > Config.SellTimeout then
                warn(">> AUTO SELL STUCK! Restarting process...")
                IsSelling = false
                return true
            end
            return false
        end

        local Char = LocalPlayer.Character
        local Root = Char and Char:FindFirstChild("HumanoidRootPart")
        if Root then
            local arrived = false
            while not arrived and Config.AutoSell and Root.Parent do
                if CheckTimeout() then return end -- Failsafe
                arrived = SkyHopMove(Root, Config.MerchantPos, 0.03)
                task.wait(0.03)
            end
        end
        
        -- [FIX] DYNAMIC BILLBOARD PATH
        local Path_Billboard = "game.Players."..pName..".PlayerGui.DialogueUI.ResponseBillboard"
        local bb = GetObject(Path_Billboard)
        local startInteract = os.clock()
        
        while (not bb or not bb.Visible) and (os.clock() - startInteract < 10) do
            if CheckTimeout() then return end -- Failsafe
            PressE()
            task.wait(0.5)
            bb = GetObject(Path_Billboard)
        end
        task.wait(0.5)
        
        -- [FIX] DYNAMIC UI PATHS
        local Path_DialogueBtn   = "game.Players."..pName..".PlayerGui.DialogueUI.ResponseBillboard.Response.Button"
        local Path_SellUI        = "game.Players."..pName..".PlayerGui.Sell.MiscSell"
        local Path_SelectAll     = "game.Players."..pName..".PlayerGui.Sell.MiscSell.Frame.SelectAll"
        local Path_SelectTitle   = "game.Players."..pName..".PlayerGui.Sell.MiscSell.Frame.SelectAll.Frame.Title"
        local Path_Accept        = "game.Players."..pName..".PlayerGui.Sell.MiscSell.Frame.Accept"
        
        -- Step 1
        local timeout = 0
        while timeout < 20 do
            if CheckTimeout() then return end
            local sellUI = GetObject(Path_SellUI)
            if sellUI and sellUI.Visible then break end
            local diagBtn = GetObject(Path_DialogueBtn)
            if diagBtn then ClickObject(diagBtn) end
            task.wait(0.5); timeout = timeout + 1
        end
        -- Step 2
        timeout = 0
        while timeout < 20 do
            if CheckTimeout() then return end
            local titleObj = GetObject(Path_SelectTitle)
            local selectBtn = GetObject(Path_SelectAll)
            if titleObj then
                local txt = GetTextMemory(titleObj)
                if txt == "Unselect All" then break end
                if selectBtn then ClickObject(selectBtn) end
            end
            task.wait(0.5); timeout = timeout + 1
        end
        -- Step 3
        timeout = 0
        while timeout < 20 do
            if CheckTimeout() then return end
            local bb2 = GetObject(Path_Billboard)
            if bb2 and bb2.Visible then break end
            local accBtn = GetObject(Path_Accept)
            if accBtn then ClickObject(accBtn) end
            task.wait(0.5); timeout = timeout + 1
        end
        -- Step 4
        timeout = 0
        while timeout < 20 do
             if CheckTimeout() then return end
             local bb3 = GetObject(Path_Billboard)
             if not bb3 or not bb3.Visible then break end
             local diagBtn = GetObject(Path_DialogueBtn)
             if diagBtn then ClickObject(diagBtn) end
             task.wait(0.5); timeout = timeout + 1
        end
        
        IsSelling = false
    end
end

-- ============================================================================
-- 6. SCANNERS
-- ============================================================================

local function PerformScan()
    local MainFolder = Workspace:FindFirstChild(Config.FolderName)
    if not MainFolder then return end 
    
    local ScanTarget = MainFolder
    if Config.OnlyLava then
        local Lava = MainFolder:FindFirstChild(Config.LavaFolder)
        if Lava then ScanTarget = Lava else ActiveRocks = {}; return end
    end
    
    local FoundInstances = {}
    local Descendants = ScanTarget:GetDescendants()
    
    for _, Obj in ipairs(Descendants) do
        if Obj.ClassName == "Model" then
            -- [CRASH FIX] Validation
            if IsValid(Obj) then
                local H = Obj:GetAttribute("Health")
                if H and tonumber(H) > 0 then
                    table.insert(FoundInstances, Obj)
                    local N = Obj.Name
                    if not RockNamesSet[N] then
                        RockNamesSet[N] = true
                        table.insert(RockList, N)
                        table.sort(RockList) 
                        if EnabledRocks[N] == nil then EnabledRocks[N] = false end
                    end
                end
            end
        end
    end
    ActiveRocks = FoundInstances
end

task.spawn(function()
    while true do
        PerformScan() 
        task.spawn(PerformAutoSell)
        if Config.EspEnabled then
            local FoundOres = {}
            local Target = Workspace:FindFirstChild(Config.FolderName)
            if Config.OnlyLava and Target then Target = Target:FindFirstChild(Config.LavaFolder) end

            if Target then
                local Descendants = Target:GetDescendants()
                for _, Obj in ipairs(Descendants) do
                    if Obj.Name == "Ore" then table.insert(FoundOres, Obj) end
                end
                ActiveOres = FoundOres
            end
        else
            ActiveOres = {}
        end
        task.wait(Config.AutoScanRate)
    end
end)

-- ============================================================================
-- 7. RENDER LOOP
-- ============================================================================

local function UpdateLoop()
    GarbageCollect() 
    local DeltaTime = 0.03
    local MousePos = getmouseposition()
    local Clicked = CheckClick()
    local IsLeftDown = false
    if isleftpressed then IsLeftDown = isleftpressed() end

    -- DRAG LOGIC
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
    DrawingImmediate.Text(vector.create(MainUI.ToggleBtn.X + 20, MainUI.ToggleBtn.Y + 12, 0), 14, Color3.new(0,0,0), 1, "Ore", true, nil)
    if Clicked and IsMouseInRect(MousePos, MainUI.ToggleBtn.X, MainUI.ToggleBtn.Y, MainUI.ToggleBtn.W, MainUI.ToggleBtn.H) then MainUI.Visible = not MainUI.Visible end

    -- MAIN WINDOW
    if MainUI.Visible then
        local ItemCount = math.max(1, #RockList)
        local TotalHeight = MainUI.BaseHeight + (ItemCount * 22) + 20
        DrawingImmediate.FilledRectangle(vector.create(MainUI.X, MainUI.Y, 0), vector.create(MainUI.Width, TotalHeight, 0), Colors.Bg, 0.95)
        DrawingImmediate.FilledRectangle(vector.create(MainUI.X, MainUI.Y, 0), vector.create(MainUI.Width, 30, 0), Colors.Header, 1)
        DrawingImmediate.OutlinedText(vector.create(MainUI.X + 10, MainUI.Y + 8, 0), 16, Colors.Text, 1, "Ore Farm", false, nil)
        
        local Y = 35
        local function MainBtn(Txt, Col, Act)
            DrawingImmediate.FilledRectangle(vector.create(MainUI.X + 10, MainUI.Y + Y, 0), vector.create(MainUI.Width - 20, 25, 0), Col, 1)
            DrawingImmediate.Text(vector.create(MainUI.X + 20, MainUI.Y + Y + 5, 0), 16, Colors.Text, 1, Txt, false, nil)
            if Clicked and IsMouseInRect(MousePos, MainUI.X + 10, MainUI.Y + Y, MainUI.Width - 20, 25) then Act() end
            Y = Y + 30
        end

        MainBtn(Config.MainEnabled and "FARMING: ON" or "FARMING: OFF", Config.MainEnabled and Colors.On or Colors.Off, function() 
            Config.MainEnabled = not Config.MainEnabled; CurrentTarget = nil; TargetLocked = false
        end)
        
        local LavaTxt = Config.OnlyLava and "ONLY LAVA: ON" or "ONLY LAVA: OFF"
        MainBtn(LavaTxt, Config.OnlyLava and Colors.On or Colors.Off, function() 
            Config.OnlyLava = not Config.OnlyLava; ActiveRocks = {}; ActiveOres = {}; RockNamesSet = {}; RockList = {}; CurrentTarget = nil; TargetLocked = false
        end)

        local PrioTxt = Config.PriorityVolcanic and "PRIO VOLCANIC: ON" or "PRIO VOLCANIC: OFF"
        MainBtn(PrioTxt, Config.PriorityVolcanic and Colors.On or Colors.Off, function()
            Config.PriorityVolcanic = not Config.PriorityVolcanic; CurrentTarget = nil; TargetLocked = false
        end)

        local PosTxt = "MINE POS: " .. (Config.MiningPosition == "Under" and "UNDER" or "ABOVE")
        MainBtn(PosTxt, Colors.Btn, function()
            Config.MiningPosition = (Config.MiningPosition == "Under") and "Above" or "Under"
            CurrentTarget = nil 
        end)
        
        local SellTxt = Config.AutoSell and "AUTO SELL: ON" or "AUTO SELL: OFF"
        MainBtn(SellTxt, Config.AutoSell and Colors.On or Colors.Off, function() Config.AutoSell = not Config.AutoSell end)

        MainBtn(Config.EspEnabled and "ORE ESP: ON" or "ORE ESP: OFF", Config.EspEnabled and Colors.On or Colors.Off, function() Config.EspEnabled = not Config.EspEnabled end)
        MainBtn(Config.AutoEquip and "Auto Pickaxe: ON" or "Auto Pickaxe: OFF", Config.AutoEquip and Colors.On or Colors.Off, function() Config.AutoEquip = not Config.AutoEquip end)
        MainBtn(FilterUI.Visible and "Close Filter Menu" or "Open Filter Menu", Colors.Gold, function() FilterUI.Visible = not FilterUI.Visible end)

        Y = Y + 10
        DrawingImmediate.OutlinedText(vector.create(MainUI.X + 10, MainUI.Y + Y, 0), 14, Colors.Text, 1, "Select Rocks to Farm:", false, nil)
        Y = Y + 20
        
        for i, Name in ipairs(RockList) do
            local IsOn = EnabledRocks[Name]
            DrawingImmediate.FilledRectangle(vector.create(MainUI.X + 10, MainUI.Y + Y, 0), vector.create(MainUI.Width - 20, 20, 0), IsOn and Colors.On or Colors.Off, 1)
            DrawingImmediate.Text(vector.create(MainUI.X + 20, MainUI.Y + Y + 2, 0), 14, Colors.Text, 1, Name, false, nil)
            if Clicked and IsMouseInRect(MousePos, MainUI.X + 10, MainUI.Y + Y, MainUI.Width - 20, 20) then
                EnabledRocks[Name] = not EnabledRocks[Name]; CurrentTarget = nil; TargetLocked = false
            end
            Y = Y + 22
        end
    end

    -- FILTER WINDOW
    if FilterUI.Visible then
        local CatList = OreDatabase[FilterUI.CurrentCategory] or {}
        local F_TotalHeight = FilterUI.BaseHeight + (#CatList * 22)
        DrawingImmediate.FilledRectangle(vector.create(FilterUI.X, FilterUI.Y, 0), vector.create(FilterUI.Width, F_TotalHeight, 0), Colors.Bg, 0.95)
        DrawingImmediate.FilledRectangle(vector.create(FilterUI.X, FilterUI.Y, 0), vector.create(FilterUI.Width, 30, 0), Colors.Header, 1)
        DrawingImmediate.OutlinedText(vector.create(FilterUI.X + 10, FilterUI.Y + 8, 0), 16, Colors.Text, 1, "Ore Filter", false, nil)
        
        local FY = 35
        -- Filter Enabled Toggle
        local F_Txt = Config.FilterEnabled and "FILTER: ACTIVE" or "FILTER: DISABLED"
        local F_Col = Config.FilterEnabled and Colors.On or Colors.Off
        DrawingImmediate.FilledRectangle(vector.create(FilterUI.X + 10, FilterUI.Y + FY, 0), vector.create(FilterUI.Width - 20, 25, 0), F_Col, 1)
        DrawingImmediate.Text(vector.create(FilterUI.X + 60, FilterUI.Y + FY + 5, 0), 16, Colors.Text, 1, F_Txt, false, nil)
        if Clicked and IsMouseInRect(MousePos, FilterUI.X + 10, FilterUI.Y + FY, FilterUI.Width - 20, 25) then Config.FilterEnabled = not Config.FilterEnabled end
        FY = FY + 30

        -- [NEW BUTTON] FILTER VOLCANIC ONLY
        local V_Txt = Config.FilterVolcanicOnly and "VOLCANIC ONLY: ON" or "VOLCANIC ONLY: OFF"
        local V_Col = Config.FilterVolcanicOnly and Colors.On or Colors.Off
        DrawingImmediate.FilledRectangle(vector.create(FilterUI.X + 10, FilterUI.Y + FY, 0), vector.create(FilterUI.Width - 20, 25, 0), V_Col, 1)
        DrawingImmediate.Text(vector.create(FilterUI.X + 60, FilterUI.Y + FY + 5, 0), 16, Colors.Text, 1, V_Txt, false, nil)
        if Clicked and IsMouseInRect(MousePos, FilterUI.X + 10, FilterUI.Y + FY, FilterUI.Width - 20, 25) then Config.FilterVolcanicOnly = not Config.FilterVolcanicOnly end
        FY = FY + 35

        -- Categories
        local btnW = (FilterUI.Width - 30) / 3 
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
            DrawingImmediate.FilledRectangle(vector.create(FilterUI.X + 10, FilterUI.Y + FY, 0), vector.create(FilterUI.Width - 20, 20, 0), IsWhitelisted and Colors.On or Colors.Off, 1)
            DrawingImmediate.Text(vector.create(FilterUI.X + 20, FilterUI.Y + FY + 2, 0), 14, Colors.Text, 1, OreName, false, nil)
            if Clicked and IsMouseInRect(MousePos, FilterUI.X + 10, FilterUI.Y + FY, FilterUI.Width - 20, 20) then
                Config.FilterWhitelist[OreName] = not Config.FilterWhitelist[OreName]; CurrentTarget = nil; TargetLocked = false
            end
            FY = FY + 22
        end
    end

    if Config.EspEnabled then
        for _, OreObj in ipairs(ActiveOres) do
            if IsValid(OreObj) then
                local OreName = SafeGetAttribute(OreObj, "Ore")
                if OreName then
                    local Pos = GetPosition(OreObj)
                    if Pos then
                        local ScreenPos, Visible = Camera:WorldToScreenPoint(Pos)
                        if Visible then
                            DrawingImmediate.OutlinedText(vector.create(ScreenPos.X, ScreenPos.Y, 0), Config.EspTextSize, Config.EspTextColor, 1, "[" .. tostring(OreName) .. "]", true, nil)
                        end
                    end
                end
            end
        end
    end

    if IsSelling then return end

    local Char = LocalPlayer.Character
    if Char then CheckAutoEquip(Char) end

    if Char and Char:FindFirstChild("HumanoidRootPart") then
        local MyRoot = Char.HumanoidRootPart
        if Config.MainEnabled then
            if CurrentTarget then
                if not IsValid(CurrentTarget) then CurrentTarget = nil; TargetLocked = false; return end
                local HP = GetRockHealth(CurrentTarget)
                if HP <= 0 then CurrentTarget = nil; TargetLocked = false; return end

                local MaxHP = GetRockMaxHealth(CurrentTarget)
                local OrePos = GetPosition(CurrentTarget)
                if not OrePos then CurrentTarget = nil; TargetLocked = false; return end
                
                local Y_Offset = (Config.MiningPosition == "Under") and -Config.UnderOffset or Config.AboveOffset
                local GoalPos = vector.create(OrePos.x, OrePos.y + Y_Offset, OrePos.z)
                
                local DistToRock = vector.magnitude(MyRoot.Position - OrePos)
                if DistToRock > 15 and MaxHP > 0 and HP < MaxHP and not TargetLocked then
                      CurrentTarget = nil; return
                end

                if Config.PriorityVolcanic and not IsVolcanic(CurrentTarget) then
                    local PriorityRock = FindVolcanicRock()
                    if PriorityRock then CurrentTarget = PriorityRock; TargetLocked = false; return end
                end

                -- [CRITICAL UPDATE] LOGIC FOR VOLCANIC FILTER
                local RevealedOre = GetRevealedOreType(CurrentTarget)
                if Config.FilterEnabled and RevealedOre then
                    local ApplyFilter = true
                    if Config.FilterVolcanicOnly and not IsVolcanic(CurrentTarget) then
                        ApplyFilter = false
                    end
                    
                    if ApplyFilter then
                        if not IsOreWanted(RevealedOre) then
                            CurrentTarget = nil; TargetLocked = false; return
                        end
                    end
                end

                local Diff = MyRoot.Position - GoalPos
                local Dist = vector.magnitude(Diff)
                
                if Dist > Config.MineDistance then
                    SkyHopMove(MyRoot, GoalPos, DeltaTime)
                else
                    local CurrentHP = GetRockHealth(CurrentTarget)
                    local MaxHP_Real = GetRockMaxHealth(CurrentTarget)

                    if CurrentHP <= 0 then CurrentTarget = nil; TargetLocked = false; return end

                    if not TargetLocked then
                        if MaxHP_Real > 0 and CurrentHP < MaxHP_Real then
                            CurrentTarget = nil; return
                        else
                            TargetLocked = true
                        end
                    end

                    local LookAt = Vector3.new(OrePos.x, OrePos.y, OrePos.z)
                    local Pos = Vector3.new(GoalPos.x, GoalPos.y, GoalPos.z)
                    MyRoot.CFrame = CFrame.lookAt(Pos, LookAt)
                    MyRoot.Velocity = vector.zero
                    
                    if os.clock() - LastMineClick > Config.ClickDelay then
                        if mouse1click then mouse1click() end
                        LastMineClick = os.clock()
                    end
                end
            else
                CurrentTarget = FindNearestRock()
                TargetLocked = false 
            end
        end
    end
end

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
