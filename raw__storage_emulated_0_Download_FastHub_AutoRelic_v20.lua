-- Fast Hub Auto Relic v20  (FASTHUB_RELIC_V20_MARKER)
local HOP_TIME     = 43      -- seconds on each server before hopping
local EARLY_HOP    = false   -- false = ONLY the hop timer decides when to leave (fixes hopping with time left)
local EMPTY_HOP    = 8       -- only used if EARLY_HOP = true
local VISITED_FILE = "FastHub_Visited.json"
local SCRIPT_FILE  = ""      -- optional: this script's filename in your executor workspace (auto-detected if left empty)
local SAVE_FILE    = "DragonSphere_UseTime.txt"
local RELIC_FILE   = "FastHub_Relics.txt"
local LOADER_URL   = ""

if not game:IsLoaded() then game.Loaded:Wait() end

local Players           = game:GetService("Players")
local RunService        = game:GetService("RunService")
local HttpService       = game:GetService("HttpService")
local TeleportService   = game:GetService("TeleportService")
local StarterGui        = game:GetService("StarterGui")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local lp = Players.LocalPlayer

local env = (getgenv and getgenv()) or _G
local token = {}
env.FH_TOKEN = token
local halted = false
local runId = 0 -- bumped on every (re)start; loops that belong to an older run end by themselves
local function alive(run)
    return env.FH_TOKEN == token and not halted and (run == nil or run == runId)
end

-- re-execute after every hop: queue_on_teleport runs this script again on the next server.
-- Source = LOADER_URL, else SCRIPT_FILE, else the script finds its own file in your workspace.
local qot = queue_on_teleport or queueonteleport
    or (syn and syn.queue_on_teleport) or (fluxus and fluxus.queue_on_teleport)
local MARKER = "FASTHUB_RELIC_V20_MARKER"
local SOURCE_MEMO = "FastHub_Source.txt"

local function findSelf()
    if SCRIPT_FILE ~= "" then return SCRIPT_FILE end
    if not (isfile and readfile) then return nil end
    local remembered
    pcall(function()
        if isfile(SOURCE_MEMO) then remembered = readfile(SOURCE_MEMO) end
    end)
    if remembered and remembered ~= "" then
        local okf, exists = pcall(isfile, remembered)
        if okf and exists then return remembered end
    end
    if not listfiles then return nil end
    local found
    pcall(function()
        local checked = 0
        for _, path in ipairs(listfiles("")) do
            local low = path:lower()
            if low:match("%.lua$") or low:match("%.luau$") or low:match("%.txt$") then
                checked += 1
                if checked > 400 then break end
                local okr, data = pcall(readfile, path)
                if okr and type(data) == "string" and #data < 700000 and data:find(MARKER, 1, true) then
                    found = path
                    break
                end
            end
        end
    end)
    if found then pcall(function() if writefile then writefile(SOURCE_MEMO, found) end end) end
    return found
end

local reloadQueued = false
local function queueReload()
    if reloadQueued then return true end
    if not qot then return false end
    local code
    if LOADER_URL ~= "" then
        code = ("loadstring(game:HttpGet(%q))()"):format(LOADER_URL)
    else
        local f = findSelf()
        if f then code = ("loadstring(readfile(%q))()"):format(f) end
    end
    if not code then return false end
    local ok = pcall(qot, "pcall(function() " .. code .. " end)")
    if ok then reloadQueued = true end
    return ok
end
queueReload()

local total = 0
pcall(function()
    if isfile and isfile(SAVE_FILE) then
        total = tonumber(readfile(SAVE_FILE)) or 0
    end
end)

local relicsTotal = 0
pcall(function()
    if isfile and isfile(RELIC_FILE) then
        relicsTotal = tonumber(readfile(RELIC_FILE)) or 0
    end
end)

local function save()
    pcall(function()
        if writefile then
            writefile(SAVE_FILE, tostring(math.floor(total)))
            writefile(RELIC_FILE, tostring(math.floor(relicsTotal)))
        end
    end)
end

local function fmtNum(n)
    local r = tostring(math.floor(n)):reverse():gsub("(%d%d%d)", "%1,"):reverse()
    return (r:gsub("^,", ""))
end

local function fmtTime(t)
    t = math.floor(t)
    return ("%02d:%02d:%02d"):format(math.floor(t / 3600), math.floor((t % 3600) / 60), t % 60)
end

local function uiParent()
    local ok, p = pcall(function()
        return (gethui and gethui()) or game:GetService("CoreGui")
    end)
    if ok and p then return p end
    return lp:WaitForChild("PlayerGui")
end

local parent = uiParent()
for _, holder in ipairs({ parent, lp:FindFirstChild("PlayerGui") }) do
    for _, n in ipairs({ "FastHubUI", "DragonSphereUI" }) do
        local old = holder and holder:FindFirstChild(n)
        if old then pcall(function() old:Destroy() end) end
    end
end


-- ============================================================
--  Fast Hub  •  interface v8
--  End = Emergency Stop    Home = Restart (after a stop)    RightShift = hide / show window
--  Double-click the title bar to minimize
-- ============================================================
local TweenService     = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local C = {
    bg      = Color3.fromRGB(28, 28, 30),
    sub     = Color3.fromRGB(152, 152, 157),
    white   = Color3.fromRGB(255, 255, 255),
    green   = Color3.fromRGB(48, 209, 88),
    red     = Color3.fromRGB(255, 69, 58),
    redHot  = Color3.fromRGB(255, 99, 90),
    redDeep = Color3.fromRGB(205, 48, 40),
    yellow  = Color3.fromRGB(255, 214, 10),
    orange  = Color3.fromRGB(255, 159, 10),
    blue    = Color3.fromRGB(10, 132, 255),
    gray    = Color3.fromRGB(58, 58, 60),
    track   = Color3.fromRGB(118, 118, 128),
    thumb   = Color3.fromRGB(99, 99, 102),
}

-- layout grid: every gap in the window is 16 (sections) or 12 (neighbours)
local WIDTH, HEIGHT, BAR = 328, 458, 36
local PAD, GAP = 20, 12
local PAGE_H = 348          -- height of the Home / Settings page area
local FOOT_DIV = 354        -- footer divider (body space)
local FOOT_Y = 364          -- footer row (body space)
local conns = {}
local farmConns = {} -- relic listeners, dropped on stop and rebuilt on restart
local relicCleanup  -- set by the relic engine (tween, noclip, ESP)

-- feature switches, read by the farm / walk / skill loops below
local flags = { instantTp = true, esp = false, autoHop = true, farmMobs = true }
local setESP -- set by the relic engine
local mobTarget -- mob root part currently being farmed (also used to aim the punch)

-- live info shown on the Home page
local activity, mobsKilled, hopCount = "Starting", 0, 0
local refreshInfo -- set by the info chip below
local refreshSubs -- set by the Settings page: refreshes toggle text + section hints
local liveRelics, liveMobs = 0, 0 -- counted once a second by the engine
local function setActivity(text)
    if activity == text then return end
    activity = text
    if refreshInfo then refreshInfo() end
end

-- glide (tween) speed in studs per second. Medium on purpose: too fast gets noticed, too slow wastes time.
local GLIDE_FILE = "FastHub_Glide.txt"
local GLIDE_MIN, GLIDE_MAX, GLIDE_SPEED = 30, 100, 60
pcall(function()
    if isfile and isfile(GLIDE_FILE) then
        GLIDE_SPEED = math.clamp(tonumber(readfile(GLIDE_FILE)) or GLIDE_SPEED, GLIDE_MIN, GLIDE_MAX)
    end
end)
local HOP_FILE = "FastHub_HopTime.txt"
pcall(function()
    if isfile and isfile(HOP_FILE) then
        HOP_TIME = math.clamp(tonumber(readfile(HOP_FILE)) or HOP_TIME, 15, 120)
    end
end)
local function saveHop()
    pcall(function() if writefile then writefile(HOP_FILE, tostring(HOP_TIME)) end end)
end
local function saveGlide()
    pcall(function() if writefile then writefile(GLIDE_FILE, tostring(GLIDE_SPEED)) end end)
end

local function tween(obj, t, props, style, dir)
    local tw = TweenService:Create(
        obj,
        TweenInfo.new(t, style or Enum.EasingStyle.Quint, dir or Enum.EasingDirection.Out),
        props
    )
    tw:Play()
    return tw
end

local function new(class, props, parent)
    local i = Instance.new(class)
    if class == "TextButton" then i.Selectable = false end
    if class == "TextButton" or class == "TextLabel" then i.AutoLocalize = false end
    for k, v in pairs(props) do i[k] = v end
    i.Parent = parent
    return i
end

local function guard(name, fn) -- one broken section must never stop the rest of the script
    local ok, err = pcall(fn)
    if not ok then warn("[Fast Hub] " .. name .. ": " .. tostring(err)) end
end

local function corner(r, parent)
    return new("UICorner", { CornerRadius = UDim.new(0, r) }, parent)
end

local function hairline(parent, transparency)
    return new("UIStroke", {
        Thickness = 1,
        Color = C.white,
        Transparency = transparency or 0.93,
        ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
    }, parent)
end

-- a horizontal row that spaces its children evenly and sizes itself
local function autoRow(props, parent, spacing)
    local f = new("Frame", {
        Position = props.Position,
        AnchorPoint = props.AnchorPoint or Vector2.new(0, 0),
        Size = UDim2.fromOffset(0, props.Height),
        AutomaticSize = Enum.AutomaticSize.X,
        BackgroundTransparency = 1,
        ZIndex = 2,
    }, parent)
    new("UIListLayout", {
        FillDirection = Enum.FillDirection.Horizontal,
        VerticalAlignment = Enum.VerticalAlignment.Center,
        SortOrder = Enum.SortOrder.LayoutOrder,
        Padding = UDim.new(0, spacing),
    }, f)
    return f
end

local gui = new("ScreenGui", {
    Name = "FastHubUI",
    ResetOnSpawn = false,
    IgnoreGuiInset = true,
    DisplayOrder = 999,
    ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
})
if not pcall(function() gui.Parent = parent end) then
    gui.Parent = lp:WaitForChild("PlayerGui")
end

-- window ------------------------------------------------------
local root = new("Frame", {
    Name = "Root",
    AnchorPoint = Vector2.new(0.5, 0),
    Position = UDim2.new(0.5, 0, 0.5, -HEIGHT / 2),
    Size = UDim2.fromOffset(WIDTH, HEIGHT),
    BackgroundTransparency = 1,
}, gui)
local rootScale = new("UIScale", { Scale = 0.9 }, root)
local function fitScale()
    local cam = workspace.CurrentCamera
    if not cam then return 1 end
    local vp = cam.ViewportSize
    return math.clamp(math.min((vp.X - 24) / WIDTH, (vp.Y - 40) / HEIGHT), 0.6, 1)
end

guard("shadow", function()
local function makeShadow(grow, drop, transparency, radius)
    local s = new("Frame", {
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.new(0.5, 0, 0.5, drop),
        Size = UDim2.new(1, grow, 1, grow - 6),
        BackgroundColor3 = Color3.new(0, 0, 0),
        BackgroundTransparency = transparency,
        ZIndex = 0,
    }, root)
    corner(radius, s)
end
makeShadow(56, 16, 0.95, 38)
makeShadow(38, 10, 0.9, 30)
makeShadow(18, 5, 0.82, 23)
end)

local main = new("Frame", {
    Name = "Main",
    Size = UDim2.fromScale(1, 1),
    BackgroundColor3 = C.white,
    BackgroundTransparency = 0.6,
    ClipsDescendants = true,
    ZIndex = 1,
}, root)
corner(22, main)
new("UIGradient", {
    Color = ColorSequence.new(Color3.fromRGB(46, 46, 49), Color3.fromRGB(22, 22, 24)),
    Rotation = 90,
}, main)
local mainStroke = hairline(main, 0.86)
new("UIGradient", { -- brighter rim on top, fading down (like light catching glass)
    Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0.55),
        NumberSequenceKeypoint.new(0.35, 0.86),
        NumberSequenceKeypoint.new(1, 0.93),
    }),
    Rotation = 90,
}, mainStroke)

guard("sheen", function()
local sheen = new("Frame", {
    Size = UDim2.new(1, 0, 0, 100),
    BackgroundColor3 = C.white,
    BorderSizePixel = 0,
    ZIndex = 1,
}, main)
new("UIGradient", {
    Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0.94),
        NumberSequenceKeypoint.new(1, 1),
    }),
    Rotation = 90,
}, sheen)
end)

-- toast (snackbar that slides up from the bottom, never covers the timer)
local toast = function() end
guard("toast", function()
local TOAST_HIDDEN = UDim2.new(0.5, 0, 1, 8)
local TOAST_SHOWN  = UDim2.new(0.5, 0, 1, -46)

local toastFrame = new("Frame", {
    AnchorPoint = Vector2.new(0.5, 0),
    Position = TOAST_HIDDEN,
    Size = UDim2.fromOffset(0, 32),
    AutomaticSize = Enum.AutomaticSize.X,
    BackgroundColor3 = C.gray,
    ZIndex = 20,
}, main)
corner(16, toastFrame)
hairline(toastFrame, 0.82)
new("UIPadding", {
    PaddingLeft = UDim.new(0, 16),
    PaddingRight = UDim.new(0, 20),
}, toastFrame)
new("UIListLayout", {
    FillDirection = Enum.FillDirection.Horizontal,
    VerticalAlignment = Enum.VerticalAlignment.Center,
    SortOrder = Enum.SortOrder.LayoutOrder,
    Padding = UDim.new(0, 10),
}, toastFrame)

local toastDot = new("Frame", {
    Size = UDim2.fromOffset(8, 8),
    BackgroundColor3 = C.green,
    LayoutOrder = 1,
    ZIndex = 21,
}, toastFrame)
corner(4, toastDot)

local toastTxt = new("TextLabel", {
    Size = UDim2.fromOffset(0, 32),
    AutomaticSize = Enum.AutomaticSize.X,
    BackgroundTransparency = 1,
    Text = "",
    Font = Enum.Font.GothamMedium,
    TextSize = 12,
    TextColor3 = C.white,
    LayoutOrder = 2,
    ZIndex = 21,
}, toastFrame)

local toastId = 0
function toast(text, color)
    if main.AbsoluteSize.Y < 100 then return end -- window is minimized
    toastId += 1
    local id = toastId
    toastTxt.Text = text
    toastDot.BackgroundColor3 = color or C.green
    tween(toastFrame, 0.38, { Position = TOAST_SHOWN }, Enum.EasingStyle.Back)
    task.delay(2, function()
        if toastId == id and toastFrame.Parent then
            tween(toastFrame, 0.28, { Position = TOAST_HIDDEN },
                Enum.EasingStyle.Quint, Enum.EasingDirection.In)
        end
    end)
end
end)

-- title bar ---------------------------------------------------
local titleBar = new("Frame", {
    Name = "TitleBar",
    Size = UDim2.new(1, 0, 0, BAR),
    BackgroundTransparency = 1,
    Active = true,
    ZIndex = 2,
}, main)

new("Frame", {
    Position = UDim2.new(0, 0, 1, -1),
    Size = UDim2.new(1, 0, 0, 1),
    BackgroundColor3 = C.white,
    BackgroundTransparency = 0.93,
    BorderSizePixel = 0,
    ZIndex = 2,
}, titleBar)

local closeBtn, minBtn, maxBtn
guard("title buttons", function()
local dots = new("Frame", {
    Name = "Dots",
    Position = UDim2.fromOffset(6, 0),
    Size = UDim2.fromOffset(68, BAR),
    BackgroundTransparency = 1,
    ZIndex = 2,
}, titleBar)

local function makeDot(color, glyph, x)
    local b = new("TextButton", {
        Size = UDim2.fromOffset(12, 12),
        Position = UDim2.fromOffset(x, 12),
        BackgroundColor3 = color,
        Text = "",
        AutoButtonColor = false,
        ZIndex = 3,
    }, dots)
    corner(6, b)
    local g = new("TextLabel", {
        Size = UDim2.fromScale(1, 1),
        BackgroundTransparency = 1,
        Text = glyph,
        Font = Enum.Font.GothamBold,
        TextSize = 11,
        TextColor3 = Color3.fromRGB(40, 20, 20),
        TextTransparency = 1,
        ZIndex = 3,
    }, b)
    return b, g
end

local closeG; closeBtn, closeG = makeDot(C.red, "×", 8)
local minG; minBtn, minG = makeDot(C.yellow, "–", 28)
local maxG; maxBtn, maxG = makeDot(C.green, "+", 48)

local function glyphs(on)
    for _, g in ipairs({ closeG, minG, maxG }) do
        tween(g, 0.15, { TextTransparency = on and 0.25 or 1 })
    end
end
dots.MouseEnter:Connect(function() glyphs(true) end)
dots.MouseLeave:Connect(function() glyphs(false) end)
end)

-- window controls: close / minimize / reset and drag ----------
local onClose = function() end
local toggleWindow = function() end
guard("window controls", function()
    local collapsed = false
    local function setCollapsed(v)
        collapsed = v
        tween(root, 0.35, { Size = UDim2.fromOffset(WIDTH, v and BAR or HEIGHT) })
    end

    minBtn.Activated:Connect(function() setCollapsed(not collapsed) end)
    maxBtn.Activated:Connect(function()
        tween(root, 0.4, { Position = UDim2.new(0.5, 0, 0.5, -HEIGHT / 2) })
        setCollapsed(false)
    end)
    closeBtn.Activated:Connect(function()
        pcall(onClose)
        tween(rootScale, 0.18, { Scale = 0.9 }, Enum.EasingStyle.Quint, Enum.EasingDirection.In)
        task.delay(0.2, function()
            if env.FH_TOKEN == token then env.FH_TOKEN = nil end -- stops every loop
            for _, c in ipairs(conns) do pcall(function() c:Disconnect() end) end
            for _, c in ipairs(farmConns) do pcall(function() c:Disconnect() end) end
            if relicCleanup then pcall(relicCleanup) end
            pcall(function() gui:Destroy() end)
        end)
    end)

    -- dragging: mouse + touch, keeps the title bar on screen, double-click title to minimize
    local dragging, dragInput, dragStart, startPos
    local lastClick = 0

    local function clampPos(pos)
        local cam = workspace.CurrentCamera
        if not cam then return pos end
        local vp = cam.ViewportSize
        local half = WIDTH * rootScale.Scale / 2
        local minX = -vp.X * pos.X.Scale + half
        local maxX = vp.X * (1 - pos.X.Scale) - half
        if maxX < minX then maxX = minX end
        local minY = -vp.Y * pos.Y.Scale
        local maxY = vp.Y * (1 - pos.Y.Scale) - BAR * rootScale.Scale
        if maxY < minY then maxY = minY end
        return UDim2.new(pos.X.Scale, math.clamp(pos.X.Offset, minX, maxX),
            pos.Y.Scale, math.clamp(pos.Y.Offset, minY, maxY))
    end

    local function overControls(x) -- the dots and the Home/Settings switch are buttons, not handles
        for _, nm in ipairs({ "Dots", "Seg" }) do
            local f = titleBar:FindFirstChild(nm)
            if f and x >= f.AbsolutePosition.X and x <= f.AbsolutePosition.X + f.AbsoluteSize.X then
                return true
            end
        end
        return false
    end

    titleBar.InputBegan:Connect(function(input)
        local t = input.UserInputType
        if t ~= Enum.UserInputType.MouseButton1 and t ~= Enum.UserInputType.Touch then return end
        if overControls(input.Position.X) then return end
        local now = os.clock()
        if now - lastClick < 0.3 then
            lastClick = 0
            setCollapsed(not collapsed)
            return
        end
        lastClick = now
        dragging, dragInput = true, input
        dragStart, startPos = input.Position, root.Position
    end)
    conns[#conns + 1] = UserInputService.InputChanged:Connect(function(input)
        if not dragging then return end
        if input == dragInput or input.UserInputType == Enum.UserInputType.MouseMovement then
            local d = input.Position - dragStart
            root.Position = clampPos(UDim2.new(
                startPos.X.Scale, startPos.X.Offset + d.X,
                startPos.Y.Scale, startPos.Y.Offset + d.Y))
        end
    end)
    conns[#conns + 1] = UserInputService.InputEnded:Connect(function(input)
        if dragging and (input == dragInput
            or input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch) then
            dragging = false
        end
    end)

    -- hide / show the whole window with RightShift
    local shown = true
    toggleWindow = function()
        shown = not shown
        root.Visible = shown
    end
end)

-- status pill (title bar, right) ------------------------------
local pillDot, pulse, setStatus
guard("status pill", function()
local pill = new("Frame", {
    AnchorPoint = Vector2.new(1, 0.5),
    Position = UDim2.new(1, -14, 0.5, 0),
    Size = UDim2.fromOffset(74, 20),
    BackgroundColor3 = C.green,
    BackgroundTransparency = 0.84,
    ZIndex = 3,
}, titleBar)
corner(10, pill)

pillDot = new("Frame", {
    AnchorPoint = Vector2.new(0, 0.5),
    Position = UDim2.new(0, 10, 0.5, 0),
    Size = UDim2.fromOffset(6, 6),
    BackgroundColor3 = C.green,
    ZIndex = 4,
}, pill)
corner(3, pillDot)

local pillTxt = new("TextLabel", {
    Position = UDim2.fromOffset(23, 0),
    Size = UDim2.new(1, -25, 1, 0),
    BackgroundTransparency = 1,
    Text = "Active",
    Font = Enum.Font.GothamMedium,
    TextSize = 11,
    TextColor3 = C.green,
    TextXAlignment = Enum.TextXAlignment.Left,
    ZIndex = 4,
}, pill)

pulse = TweenService:Create(
    pillDot,
    TweenInfo.new(1.1, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
    { BackgroundTransparency = 0.65 }
)
pulse:Play()

function setStatus(text, color)
    pillTxt.Text = text
    tween(pillTxt, 0.25, { TextColor3 = color })
    tween(pillDot, 0.25, { BackgroundColor3 = color })
    tween(pill, 0.25, { BackgroundColor3 = color })
end
end)

-- body + pages ------------------------------------------------
local body = new("Frame", {
    Name = "Body",
    Position = UDim2.fromOffset(0, BAR),
    Size = UDim2.new(1, 0, 0, HEIGHT - BAR),
    BackgroundTransparency = 1,
    ZIndex = 2,
}, main)

local pageHome, pageSettings
local showPage = function() end
guard("pages", function()
local function makePage(name, hidden)
    local ok, page = pcall(Instance.new, "CanvasGroup")
    if not ok or not page then page = Instance.new("Frame") end
    page.Name = name
    page.Size = UDim2.new(1, 0, 0, PAGE_H)
    page.BackgroundTransparency = 1
    page.ZIndex = 2
    if hidden then
        page.Visible = false
        if page:IsA("CanvasGroup") then page.GroupTransparency = 1 end
    end
    page.Parent = body
    return page
end

local function fadePage(page, t, value)
    if page:IsA("CanvasGroup") then
        tween(page, t, { GroupTransparency = value })
    end
end

pageHome = makePage("Home", false)
pageSettings = makePage("Settings", true)

-- segmented control (Home | Settings) in the title bar
local seg = new("Frame", {
    Name = "Seg",
    AnchorPoint = Vector2.new(0.5, 0.5),
    Position = UDim2.new(0.5, 0, 0.5, 0),
    Size = UDim2.fromOffset(140, 24),
    BackgroundColor3 = C.track,
    BackgroundTransparency = 0.76,
    ZIndex = 3,
}, titleBar)
corner(8, seg)

local thumb = new("Frame", {
    Position = UDim2.fromOffset(2, 2),
    Size = UDim2.fromOffset(68, 20),
    BackgroundColor3 = C.thumb,
    ZIndex = 4,
}, seg)
corner(6, thumb)
hairline(thumb, 0.88)

local function makeSegBtn(text, x, active)
    return new("TextButton", {
        Position = UDim2.fromOffset(x, 2),
        Size = UDim2.fromOffset(68, 20),
        BackgroundTransparency = 1,
        Text = text,
        Font = Enum.Font.GothamMedium,
        TextSize = 12,
        TextColor3 = active and C.white or C.sub,
        AutoButtonColor = false,
        ZIndex = 5,
    }, seg)
end

local homeTab = makeSegBtn("Home", 2, true)
local setTab  = makeSegBtn("Settings", 70, false)

local currentPage = pageHome
function showPage(which)
    local target = which == "home" and pageHome or pageSettings
    if target == currentPage then return end
    local old = currentPage
    currentPage = target

    target.Visible = true
    if target:IsA("CanvasGroup") then target.GroupTransparency = 1 end
    target.Position = UDim2.fromOffset(which == "home" and -16 or 16, 0)
    tween(target, 0.32, { Position = UDim2.fromOffset(0, 0) })
    fadePage(target, 0.32, 0)
    fadePage(old, 0.2, 1)
    task.delay(0.22, function()
        if currentPage ~= old then old.Visible = false end
    end)

    tween(thumb, 0.28, { Position = UDim2.fromOffset(which == "home" and 2 or 70, 2) })
    tween(homeTab, 0.2, { TextColor3 = which == "home" and C.white or C.sub })
    tween(setTab, 0.2, { TextColor3 = which == "home" and C.sub or C.white })
end
homeTab.MouseButton1Click:Connect(function() showPage("home") end)
setTab.MouseButton1Click:Connect(function() showPage("settings") end)
end)

-- HOME: timer tiles (HH : MM : SS) ----------------------------
new("TextLabel", {
    BackgroundTransparency = 1,
    Position = UDim2.fromOffset(0, 8),
    Size = UDim2.new(1, 0, 0, 14),
    Text = "TOTAL TIME",
    TextSize = 11,
    Font = Enum.Font.GothamMedium,
    TextColor3 = C.sub,
    ZIndex = 2,
}, pageHome)

local cells, colons, colonBlink, setTime = {}, {}, {}, function() end
guard("timer tiles", function()
local TILE_W, TILE_H, TILE_Y = 76, 62, 26
local DIGIT_Y = 28
cells, colons, colonBlink = {}, {}, {}

local function makeCell(x, unit)
    local tile = new("Frame", {
        Position = UDim2.fromOffset(x, TILE_Y),
        Size = UDim2.fromOffset(TILE_W, TILE_H),
        BackgroundColor3 = C.white,
        BackgroundTransparency = 0.93,
        ClipsDescendants = true,
        ZIndex = 2,
    }, pageHome)
    corner(14, tile)
    hairline(tile, 0.93)
    new("UIGradient", {
        Transparency = NumberSequence.new({
            NumberSequenceKeypoint.new(0, 0.86),
            NumberSequenceKeypoint.new(1, 0.97),
        }),
        Rotation = 90,
    }, tile)
    local lbl = new("TextLabel", {
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.new(0.5, 0, 0, DIGIT_Y),
        Size = UDim2.new(1, 0, 0, 36),
        BackgroundTransparency = 1,
        Text = "00",
        Font = Enum.Font.GothamBold,
        TextSize = 30,
        TextColor3 = C.white,
        ZIndex = 3,
    }, tile)
    new("TextLabel", {
        Position = UDim2.fromOffset(0, 46),
        Size = UDim2.new(1, 0, 0, 12),
        BackgroundTransparency = 1,
        Text = unit,
        Font = Enum.Font.GothamMedium,
        TextSize = 10,
        TextColor3 = C.sub,
        ZIndex = 3,
    }, tile)
    return lbl
end

local function makeColon(x)
    return new("TextLabel", {
        Position = UDim2.fromOffset(x, TILE_Y + DIGIT_Y - 18),
        Size = UDim2.fromOffset(14, 36),
        BackgroundTransparency = 1,
        Text = ":",
        Font = Enum.Font.GothamBold,
        TextSize = 26,
        TextColor3 = C.sub,
        ZIndex = 2,
    }, pageHome)
end

cells[1] = makeCell(36, "HOURS")
cells[2] = makeCell(126, "MINUTES")
cells[3] = makeCell(216, "SECONDS")
colons[1] = makeColon(112)
colons[2] = makeColon(202)

for i, c in ipairs(colons) do
    colonBlink[i] = TweenService:Create(
        c,
        TweenInfo.new(1, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
        { TextTransparency = 0.7 }
    )
    colonBlink[i]:Play()
end

function setTime(t)
    t = math.floor(t)
    local vals = {
        ("%02d"):format(math.floor(t / 3600)),
        ("%02d"):format(math.floor((t % 3600) / 60)),
        ("%02d"):format(t % 60),
    }
    for i, lbl in ipairs(cells) do
        if lbl.Text ~= vals[i] then
            lbl.Text = vals[i]
            lbl.Position = UDim2.new(0.5, 0, 0, DIGIT_Y + 7)
            lbl.TextTransparency = 0.75
            tween(lbl, 0.28, { Position = UDim2.new(0.5, 0, 0, DIGIT_Y), TextTransparency = 0 })
        end
    end
end
setTime(total)
end)

-- HOME: stat cards --------------------------------------------
local CARD_W = (WIDTH - PAD * 2 - GAP) / 2
local CARD_Y, CARD_H = 104, 48

local function makeStat(x, caption, value)
    local card = new("Frame", {
        Position = UDim2.fromOffset(x, CARD_Y),
        Size = UDim2.fromOffset(CARD_W, CARD_H),
        BackgroundColor3 = C.white,
        BackgroundTransparency = 0.94,
        ZIndex = 2,
    }, pageHome)
    corner(12, card)
    hairline(card, 0.94)
    new("TextLabel", {
        Position = UDim2.fromOffset(14, 7),
        Size = UDim2.new(1, -28, 0, 12),
        BackgroundTransparency = 1,
        Text = caption,
        Font = Enum.Font.GothamMedium,
        TextSize = 10,
        TextColor3 = C.sub,
        TextXAlignment = Enum.TextXAlignment.Left,
        ZIndex = 3,
    }, card)
    local v = new("TextLabel", {
        Position = UDim2.fromOffset(14, 18),
        Size = UDim2.new(1, -28, 0, 20),
        BackgroundTransparency = 1,
        Text = value,
        Font = Enum.Font.GothamBold,
        TextSize = 16,
        TextColor3 = C.white,
        TextXAlignment = Enum.TextXAlignment.Left,
        ZIndex = 3,
    }, card)
    return card, v
end

-- HOME: relics card (gem icon, count, per-hour rate, +1 pop) ---
local GOLD = Color3.fromRGB(255, 200, 40)
local sessionRelics, rateStart = 0, os.clock()

local relicCard = new("Frame", {
    Name = "RelicsCard",
    Position = UDim2.fromOffset(PAD, CARD_Y),
    Size = UDim2.fromOffset(CARD_W, CARD_H),
    BackgroundColor3 = C.white,
    BackgroundTransparency = 0.94,
    ZIndex = 2,
}, pageHome)
corner(12, relicCard)
local relicStroke = hairline(relicCard, 0.94)

local GEM_X, GEM_Y = 26, 24
local gemHalo = new("Frame", {
    AnchorPoint = Vector2.new(0.5, 0.5),
    Position = UDim2.fromOffset(GEM_X, GEM_Y),
    Size = UDim2.fromOffset(28, 28),
    BackgroundColor3 = GOLD,
    BackgroundTransparency = 0.86,
    ZIndex = 3,
}, relicCard)
corner(14, gemHalo)

local gem = new("Frame", {
    AnchorPoint = Vector2.new(0.5, 0.5),
    Position = UDim2.fromOffset(GEM_X, GEM_Y),
    Size = UDim2.fromOffset(13, 13),
    Rotation = 45,
    BackgroundColor3 = GOLD,
    ZIndex = 4,
}, relicCard)
corner(3, gem)
new("UIGradient", {
    Color = ColorSequence.new(Color3.fromRGB(255, 255, 255), Color3.fromRGB(205, 205, 205)),
    Rotation = 90,
}, gem)
new("UIStroke", {
    Thickness = 1, Color = C.white, Transparency = 0.6,
    ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
}, gem)
local gemFacet = new("Frame", { -- little highlight on the gem
    AnchorPoint = Vector2.new(0.5, 0.5),
    Position = UDim2.fromOffset(GEM_X - 1, GEM_Y - 1),
    Size = UDim2.fromOffset(5, 5),
    Rotation = 45,
    BackgroundColor3 = C.white,
    BackgroundTransparency = 0.45,
    ZIndex = 5,
}, relicCard)
corner(1, gemFacet)

new("TextLabel", {
    Position = UDim2.fromOffset(46, 7),
    Size = UDim2.fromOffset(44, 12),
    BackgroundTransparency = 1,
    Text = "RELICS",
    Font = Enum.Font.GothamMedium,
    TextSize = 10,
    TextColor3 = C.sub,
    TextXAlignment = Enum.TextXAlignment.Left,
    ZIndex = 3,
}, relicCard)

local rateLbl = new("TextLabel", { -- relics per hour, top right
    AnchorPoint = Vector2.new(1, 0),
    Position = UDim2.fromOffset(CARD_W - 12, 7),
    Size = UDim2.fromOffset(52, 12),
    BackgroundTransparency = 1,
    Text = "--/h",
    Font = Enum.Font.GothamMedium,
    TextSize = 10,
    TextColor3 = C.sub,
    TextXAlignment = Enum.TextXAlignment.Right,
    ZIndex = 3,
}, relicCard)

local relicLbl = new("TextLabel", {
    AnchorPoint = Vector2.new(0, 0.5),
    Position = UDim2.fromOffset(46, 29),
    Size = UDim2.fromOffset(CARD_W - 56, 20),
    BackgroundTransparency = 1,
    Text = fmtNum(relicsTotal),
    Font = Enum.Font.GothamBold,
    TextSize = 16,
    TextColor3 = C.white,
    TextXAlignment = Enum.TextXAlignment.Left,
    ZIndex = 3,
}, relicCard)
local relicScale = new("UIScale", { Scale = 1 }, relicLbl)

local function updateRate()
    local secs = os.clock() - rateStart
    if secs < 20 or sessionRelics == 0 then
        rateLbl.Text = "--/h"
    else
        rateLbl.Text = fmtNum(sessionRelics / secs * 3600) .. "/h"
    end
end

local function resetRelicStats()
    relicsTotal, sessionRelics, rateStart = 0, 0, os.clock()
    mobsKilled, hopCount = 0, 0
    relicLbl.Text = "0"
    updateRate()
    if refreshInfo then refreshInfo() end
end
local hopCard, hopLbl = makeStat(PAD + CARD_W + GAP, "NEXT HOP", HOP_TIME .. "s")

local track = new("Frame", {
    Position = UDim2.new(0, 14, 1, -9),
    Size = UDim2.new(1, -28, 0, 3),
    BackgroundColor3 = C.white,
    BackgroundTransparency = 0.86,
    BorderSizePixel = 0,
    ZIndex = 3,
}, hopCard)
corner(2, track)

local fill = new("Frame", {
    Size = UDim2.fromScale(1, 1),
    BackgroundColor3 = C.blue,
    BorderSizePixel = 0,
    ZIndex = 4,
}, track)
corner(2, fill)

local function bumpRelics(gained)
    relicLbl.Text = fmtNum(relicsTotal)
    if not gained or halted then return end

    -- count pops and flashes gold
    relicLbl.TextColor3 = GOLD
    tween(relicLbl, 0.7, { TextColor3 = C.white })
    relicScale.Scale = 1.14
    tween(relicScale, 0.35, { Scale = 1 }, Enum.EasingStyle.Back)

    -- gem pulses
    gemHalo.BackgroundTransparency = 0.55
    tween(gemHalo, 0.6, { BackgroundTransparency = 0.86 })
    gem.Size = UDim2.fromOffset(17, 17)
    tween(gem, 0.35, { Size = UDim2.fromOffset(13, 13) }, Enum.EasingStyle.Back)

    -- card rim catches the light
    relicStroke.Color = GOLD
    relicStroke.Transparency = 0.55
    tween(relicStroke, 0.9, { Color = C.white, Transparency = 0.94 })

    -- floating +1
    local f = new("TextLabel", {
        AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.fromOffset(CARD_W - 12, 32),
        Size = UDim2.fromOffset(30, 14),
        BackgroundTransparency = 1,
        Text = "+1",
        Font = Enum.Font.GothamBold,
        TextSize = 12,
        TextColor3 = GOLD,
        TextXAlignment = Enum.TextXAlignment.Right,
        ZIndex = 6,
    }, relicCard)
    tween(f, 0.7, { Position = UDim2.fromOffset(CARD_W - 12, 14), TextTransparency = 1 })
    task.delay(0.8, function() f:Destroy() end)
end

local function setHop(left)
    if halted then return end
    left = math.max(0, left)
    hopLbl.Text = ("%ds"):format(math.ceil(left))
    tween(fill, 0.25, {
        Size = UDim2.fromScale(math.clamp(left / HOP_TIME, 0, 1), 1),
        BackgroundColor3 = left <= 10 and C.orange or C.blue,
    }, Enum.EasingStyle.Linear)
end

local function setHopOff()
    if halted or hopLbl.Text == "Off" then return end
    hopLbl.Text = "Off"
    tween(fill, 0.25, { Size = UDim2.fromScale(0, 1) }, Enum.EasingStyle.Linear)
end

-- HOME: buttons (Reset | Emergency Stop) ----------------------
local resetBtn, stopGlow, stopBtn, stopIcon, stopTxt
guard("buttons", function()
local BTN_Y, BTN_H = 168, 38
local RESET_W = 104
local STOP_W = WIDTH - PAD * 2 - RESET_W - GAP

resetBtn = new("TextButton", {
    Position = UDim2.fromOffset(PAD, BTN_Y),
    Size = UDim2.fromOffset(RESET_W, BTN_H),
    BackgroundColor3 = C.white,
    BackgroundTransparency = 0.9,
    Text = "Reset",
    Font = Enum.Font.GothamMedium,
    TextSize = 13,
    TextColor3 = C.white,
    AutoButtonColor = false,
    ZIndex = 2,
}, pageHome)
corner(12, resetBtn)
local resetScale = new("UIScale", { Scale = 1 }, resetBtn)

stopGlow = new("Frame", { -- soft red halo behind the button
    Position = UDim2.fromOffset(PAD + RESET_W + GAP - 5, BTN_Y - 3),
    Size = UDim2.fromOffset(STOP_W + 10, BTN_H + 10),
    BackgroundColor3 = C.red,
    BackgroundTransparency = 0.88,
    ZIndex = 1,
}, pageHome)
corner(17, stopGlow)

stopBtn = new("TextButton", {
    Position = UDim2.fromOffset(PAD + RESET_W + GAP, BTN_Y),
    Size = UDim2.fromOffset(STOP_W, BTN_H),
    BackgroundColor3 = C.red,
    Text = "",
    AutoButtonColor = false,
    ZIndex = 2,
}, pageHome)
corner(12, stopBtn)
new("UIGradient", {
    Color = ColorSequence.new(Color3.fromRGB(255, 255, 255), Color3.fromRGB(222, 222, 222)),
    Rotation = 90,
}, stopBtn)
local stopScale = new("UIScale", { Scale = 1 }, stopBtn)

stopIcon = new("Frame", {
    AnchorPoint = Vector2.new(0, 0.5),
    Position = UDim2.new(0, 20, 0.5, 0),
    Size = UDim2.fromOffset(10, 10),
    BackgroundColor3 = C.white,
    ZIndex = 3,
}, stopBtn)
corner(2, stopIcon)

stopTxt = new("TextLabel", {
    Position = UDim2.fromOffset(44, 0),
    Size = UDim2.new(1, -52, 1, 0),
    BackgroundTransparency = 1,
    Text = "Emergency Stop",
    Font = Enum.Font.GothamMedium,
    TextSize = 13,
    TextColor3 = C.white,
    TextXAlignment = Enum.TextXAlignment.Left,
    ZIndex = 3,
}, stopBtn)

hairline(resetBtn, 0.9)
resetBtn.MouseEnter:Connect(function() tween(resetBtn, 0.15, { BackgroundTransparency = halted and 0.68 or 0.82 }) end)
resetBtn.MouseLeave:Connect(function()
    tween(resetBtn, 0.15, { BackgroundTransparency = halted and 0.8 or 0.9 })
    tween(resetScale, 0.15, { Scale = 1 })
end)
resetBtn.MouseButton1Down:Connect(function()
    tween(resetBtn, 0.08, { BackgroundTransparency = halted and 0.55 or 0.72 })
    tween(resetScale, 0.08, { Scale = 0.97 })
end)
resetBtn.MouseButton1Up:Connect(function()
    tween(resetBtn, 0.15, { BackgroundTransparency = halted and 0.68 or 0.82 })
    tween(resetScale, 0.15, { Scale = 1 })
end)

stopBtn.MouseEnter:Connect(function()
    if not halted then
        tween(stopBtn, 0.15, { BackgroundColor3 = C.redHot })
        tween(stopGlow, 0.2, { BackgroundTransparency = 0.78 })
    end
end)
stopBtn.MouseLeave:Connect(function()
    if not halted then
        tween(stopBtn, 0.15, { BackgroundColor3 = C.red })
        tween(stopGlow, 0.2, { BackgroundTransparency = 0.88 })
    end
    tween(stopScale, 0.15, { Scale = 1 })
end)
stopBtn.MouseButton1Down:Connect(function()
    if not halted then tween(stopBtn, 0.08, { BackgroundColor3 = C.redDeep }) end
    tween(stopScale, 0.08, { Scale = 0.97 })
end)
stopBtn.MouseButton1Up:Connect(function()
    tween(stopScale, 0.15, { Scale = 1 })
end)
end)

-- SETTINGS: grouped list with iOS-style switches --------------
guard("settings", function()
local ROW_H = 46

local function makeGroup(y, h)
    local g = new("Frame", {
        Position = UDim2.fromOffset(PAD, y),
        Size = UDim2.new(1, -PAD * 2, 0, h),
        BackgroundColor3 = C.white,
        BackgroundTransparency = 0.94,
        ZIndex = 2,
    }, pageSettings)
    corner(14, g)
    hairline(g, 0.94)
    return g
end

local function makeSep(parent, y)
    new("Frame", {
        Position = UDim2.fromOffset(16, y),
        Size = UDim2.new(1, -16, 0, 1),
        BackgroundColor3 = C.white,
        BackgroundTransparency = 0.92,
        BorderSizePixel = 0,
        ZIndex = 3,
    }, parent)
end

local function rowText(parent, y, title, subtitle)
    new("TextLabel", {
        Position = UDim2.fromOffset(16, y + 7),
        Size = UDim2.new(1, -110, 0, 16),
        BackgroundTransparency = 1,
        Text = title,
        Font = Enum.Font.GothamMedium,
        TextSize = 13,
        TextColor3 = C.white,
        TextXAlignment = Enum.TextXAlignment.Left,
        ZIndex = 3,
    }, parent)
    return new("TextLabel", {
        Position = UDim2.fromOffset(16, y + 24),
        Size = UDim2.new(1, -110, 0, 14),
        BackgroundTransparency = 1,
        Text = subtitle,
        Font = Enum.Font.Gotham,
        TextSize = 11,
        TextColor3 = C.sub,
        TextXAlignment = Enum.TextXAlignment.Left,
        ZIndex = 3,
    }, parent)
end

local subRefreshers = {}

local function makeSwitch(parent, y, title, subtitle, key, onChange, subFn)
    local subLbl = rowText(parent, y, title, subtitle)
    local sw = new("TextButton", {
        AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.new(1, -16, 0, y + ROW_H / 2),
        Size = UDim2.fromOffset(44, 26),
        BackgroundColor3 = C.green,
        Text = "",
        AutoButtonColor = false,
        ZIndex = 3,
    }, parent)
    corner(13, sw)
    local knob = new("Frame", {
        AnchorPoint = Vector2.new(0, 0.5),
        Position = UDim2.new(1, -24, 0.5, 0),
        Size = UDim2.fromOffset(22, 22),
        BackgroundColor3 = C.white,
        ZIndex = 4,
    }, sw)
    corner(11, knob)
    new("UIStroke", { -- knob drop shadow
        Thickness = 1, Color = Color3.new(0, 0, 0), Transparency = 0.85,
        ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
    }, knob)

    -- ON / OFF badge next to the switch, and a subtitle that describes the current state
    local badge = new("TextLabel", {
        AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.new(1, -68, 0, y + ROW_H / 2),
        Size = UDim2.fromOffset(30, 14),
        BackgroundTransparency = 1,
        Text = "",
        Font = Enum.Font.GothamBold,
        TextSize = 10,
        TextColor3 = C.green,
        TextXAlignment = Enum.TextXAlignment.Right,
        ZIndex = 3,
    }, parent)
    local function refreshText()
        local on = flags[key]
        badge.Text = on and "ON" or "OFF"
        badge.TextColor3 = on and C.green or C.sub
        if subFn then subLbl.Text = subFn(on) end
    end
    subRefreshers[#subRefreshers + 1] = refreshText
    refreshText()

    local function render(v, animate)
        local pos = v and UDim2.new(1, -24, 0.5, 0) or UDim2.new(0, 2, 0.5, 0)
        local col = v and C.green or C.gray
        if animate then
            tween(knob, 0.32, { Position = pos, Size = UDim2.fromOffset(22, 22) }, Enum.EasingStyle.Back)
            tween(sw, 0.25, { BackgroundColor3 = col })
        else
            knob.Position = pos
            knob.Size = UDim2.fromOffset(22, 22)
            sw.BackgroundColor3 = col
        end
    end
    render(flags[key], false)

    sw.MouseButton1Down:Connect(function() -- knob stretches while pressed
        local on = flags[key]
        tween(knob, 0.1, {
            Size = UDim2.fromOffset(28, 22),
            Position = on and UDim2.new(1, -30, 0.5, 0) or UDim2.new(0, 2, 0.5, 0),
        })
    end)
    sw.MouseLeave:Connect(function()
        if knob.Size.X.Offset ~= 22 then render(flags[key], true) end
    end)

    sw.MouseButton1Click:Connect(function()
        if halted then
            toast("Stopped. Tap Restart", C.red)
            return
        end
        flags[key] = not flags[key]
        render(flags[key], true)
        refreshText()
        if onChange then onChange(flags[key]) end
    end)
end

local function makeCaption(y, text)
    new("TextLabel", {
        Position = UDim2.fromOffset(PAD + 16, y),
        Size = UDim2.fromOffset(120, 12),
        BackgroundTransparency = 1,
        Text = text,
        Font = Enum.Font.GothamMedium,
        TextSize = 10,
        TextColor3 = C.sub,
        TextXAlignment = Enum.TextXAlignment.Left,
        ZIndex = 2,
    }, pageSettings)
    return new("TextLabel", { -- live hint, right side
        AnchorPoint = Vector2.new(1, 0),
        Position = UDim2.fromOffset(WIDTH - PAD - 16, y),
        Size = UDim2.fromOffset(150, 12),
        BackgroundTransparency = 1,
        Text = "",
        Font = Enum.Font.Gotham,
        TextSize = 10,
        TextColor3 = C.sub,
        TextXAlignment = Enum.TextXAlignment.Right,
        ZIndex = 2,
    }, pageSettings)
end

local autoCap = makeCaption(6, "AUTOMATION")
local groupA = makeGroup(22, ROW_H * 4)
makeSwitch(groupA, 0, "Instant teleport", "Snap straight to targets", "instantTp", function(on)
    if on then
        toast("Instant teleport on  •  snapping to targets", C.green)
    else
        toast(("Glide on  •  %d studs/s"):format(GLIDE_SPEED), C.sub)
    end
end, function(on)
    return on and "Snap straight to targets" or ("Glide at %d studs/s"):format(GLIDE_SPEED)
end)
makeSep(groupA, ROW_H)
makeSwitch(groupA, ROW_H, "Relic ESP", "Show relics through walls", "esp", function(on)
    if setESP then setESP(on) end
    toast(on and ("Relic ESP on  •  %d relics"):format(liveRelics) or "Relic ESP off", on and C.green or C.sub)
end, function(on)
    return on and ("%d relics glowing"):format(liveRelics) or "Show relics through walls"
end)
makeSep(groupA, ROW_H * 2)
makeSwitch(groupA, ROW_H * 2, "Auto hop", "Hop on the timer", "autoHop", function(on)
    toast(on and ("Auto hop on  •  every %ds"):format(HOP_TIME) or "Auto hop off  •  staying here", on and C.green or C.sub)
end, function(on)
    return on and ("Hop every %ds"):format(HOP_TIME) or "Stay on this server"
end)
makeSep(groupA, ROW_H * 3)
makeSwitch(groupA, ROW_H * 3, "Farm mobs", "Relics only, mobs ignored", "farmMobs", function(on)
    if not on then
        mobTarget = nil
        if relicCleanup then pcall(relicCleanup) end -- drop any glide/noclip in progress
        if flags.esp and setESP then setESP(true) end -- relicCleanup clears ESP, put it back
    end
    toast(on and "Farm mobs on  •  Bandit, Thug, Puriza" or "Farm mobs off  •  relics only", on and C.green or C.sub)
end, function(on)
    return on and ("%d mobs nearby"):format(liveMobs) or "Relics only, mobs ignored"
end)

local timeCap = makeCaption(22 + ROW_H * 4 + 12, "TIMING")
local SLIDER_H = 52
local groupB = makeGroup(22 + ROW_H * 4 + 12 + 16, SLIDER_H * 2 + 1)
makeSep(groupB, SLIDER_H)

-- one slider row: title, live value + tier on the right, bar with a highlighted zone.
-- drag anywhere on the bar (mouse or touch); the value snaps to `step`.
local function makeSlider(y0, title, min, max, step, getV, setV, fmt, tierFn, zone, onDone)
    new("TextLabel", {
        Position = UDim2.fromOffset(16, y0 + 8),
        Size = UDim2.fromOffset(120, 16),
        BackgroundTransparency = 1,
        Text = title,
        Font = Enum.Font.GothamMedium,
        TextSize = 13,
        TextColor3 = C.white,
        TextXAlignment = Enum.TextXAlignment.Left,
        ZIndex = 3,
    }, groupB)

    local valLbl = new("TextLabel", {
        AnchorPoint = Vector2.new(1, 0),
        Position = UDim2.new(1, -16, 0, y0 + 8),
        Size = UDim2.fromOffset(150, 16),
        BackgroundTransparency = 1,
        Text = "",
        Font = Enum.Font.GothamBold,
        TextSize = 13,
        TextColor3 = C.white,
        TextXAlignment = Enum.TextXAlignment.Right,
        ZIndex = 3,
    }, groupB)

    local track = new("Frame", {
        Position = UDim2.new(0, 16, 0, y0 + 33),
        Size = UDim2.new(1, -32, 0, 6),
        BackgroundColor3 = C.white,
        BackgroundTransparency = 0.86,
        BorderSizePixel = 0,
        ZIndex = 3,
    }, groupB)
    corner(3, track)

    local function frac(v) return (v - min) / (max - min) end

    local zoneBar = new("Frame", {
        Position = UDim2.fromScale(frac(zone[1]), 0),
        Size = UDim2.fromScale(frac(zone[2]) - frac(zone[1]), 1),
        BackgroundColor3 = zone[3],
        BackgroundTransparency = 0.6,
        BorderSizePixel = 0,
        ZIndex = 4,
    }, track)
    corner(3, zoneBar)

    local fillBar = new("Frame", {
        Size = UDim2.fromScale(0, 1),
        BackgroundColor3 = C.blue,
        BorderSizePixel = 0,
        ZIndex = 5,
    }, track)
    corner(3, fillBar)

    local knob = new("Frame", {
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.fromScale(0, 0.5),
        Size = UDim2.fromOffset(20, 20),
        BackgroundColor3 = C.white,
        ZIndex = 6,
    }, track)
    corner(10, knob)
    new("UIStroke", {
        Thickness = 1, Color = Color3.new(0, 0, 0), Transparency = 0.85,
        ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
    }, knob)
    local knobScale = new("UIScale", { Scale = 1 }, knob)

    local function render(animate)
        local v = getV()
        local f = frac(v)
        local tier, col = tierFn(v)
        valLbl.Text = ("%s  •  %s"):format(fmt(v), tier)
        valLbl.TextColor3 = col
        local pos, size = UDim2.fromScale(f, 0.5), UDim2.fromScale(f, 1)
        if animate then
            tween(knob, 0.08, { Position = pos }, Enum.EasingStyle.Linear)
            tween(fillBar, 0.08, { Size = size, BackgroundColor3 = col }, Enum.EasingStyle.Linear)
        else
            knob.Position = pos
            fillBar.Size = size
            fillBar.BackgroundColor3 = col
        end
    end
    render(false)

    local sliding = false
    local function setFromX(x)
        local w = track.AbsoluteSize.X
        if w <= 0 then return end
        local f = math.clamp((x - track.AbsolutePosition.X) / w, 0, 1)
        local v = min + math.floor(f * (max - min) / step + 0.5) * step
        v = math.clamp(v, min, max)
        if v ~= getV() then
            setV(v)
            render(true)
        end
    end

    local function endSlide()
        if not sliding then return end
        sliding = false
        tween(knobScale, 0.15, { Scale = 1 }, Enum.EasingStyle.Back)
        onDone()
    end

    local hit = new("TextButton", { -- generous touch area around the thin bar
        Position = UDim2.new(0, 6, 0, y0 + 22),
        Size = UDim2.new(1, -12, 0, 28),
        BackgroundTransparency = 1,
        Text = "",
        AutoButtonColor = false,
        ZIndex = 7,
    }, groupB)

    hit.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
            if halted then
                toast("Stopped. Tap Restart", C.red)
                return
            end
            sliding = true
            tween(knobScale, 0.1, { Scale = 1.15 })
            setFromX(input.Position.X)
            input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then endSlide() end
            end)
        end
    end)
    conns[#conns + 1] = UserInputService.InputChanged:Connect(function(input)
        if sliding and (input.UserInputType == Enum.UserInputType.MouseMovement
            or input.UserInputType == Enum.UserInputType.Touch) then
            setFromX(input.Position.X)
        end
    end)
end

-- hop timer: seconds on each server (15 - 120)
makeSlider(0, "Hop timer", 15, 120, 5,
    function() return HOP_TIME end,
    function(v) HOP_TIME = v; if refreshSubs then refreshSubs() end end,
    function(v) return v .. "s" end,
    function(v)
        if v < 30 then return "Quick", C.orange end
        if v <= 60 then return "Balanced", C.blue end
        return "Long", C.blue
    end,
    { 30, 60, C.blue },
    function()
        saveHop()
        toast(("Hop timer %ds"):format(HOP_TIME), C.blue)
    end)

-- glide speed: studs per second (30 - 100), medium is 50 - 70
makeSlider(SLIDER_H + 1, "Glide speed", GLIDE_MIN, GLIDE_MAX, 5,
    function() return GLIDE_SPEED end,
    function(v) GLIDE_SPEED = v; if refreshSubs then refreshSubs() end end,
    function(v) return tostring(v) end,
    function(v)
        if v < 50 then return "Slow", C.orange end
        if v <= 70 then return "Medium", C.green end
        return "Fast", C.orange
    end,
    { 50, 70, C.green },
    function()
        saveGlide()
        toast(("Glide speed %d"):format(GLIDE_SPEED), C.green)
    end)

refreshSubs = function()
    for _, f in ipairs(subRefreshers) do f() end
    local n = 0
    for _, k in ipairs({ "instantTp", "esp", "autoHop", "farmMobs" }) do
        if flags[k] then n += 1 end
    end
    autoCap.Text = ("%d of 4 on"):format(n)
    timeCap.Text = ("Hop %ds  •  Glide %d"):format(HOP_TIME, GLIDE_SPEED)
end
refreshSubs()
end)

-- HOME: server chip -------------------------------------------
guard("info cells", function()
local INFO_Y, INFO_H = 218, 36
local function makeInfoCell(x, w, caption)
    local cell = new("Frame", {
        Position = UDim2.fromOffset(x, INFO_Y),
        Size = UDim2.fromOffset(w, INFO_H),
        BackgroundColor3 = C.white,
        BackgroundTransparency = 0.94,
        ZIndex = 2,
    }, pageHome)
    corner(10, cell)
    hairline(cell, 0.94)
    new("TextLabel", {
        Position = UDim2.fromOffset(12, 5),
        Size = UDim2.new(1, -24, 0, 10),
        BackgroundTransparency = 1,
        Text = caption,
        Font = Enum.Font.GothamMedium,
        TextSize = 9,
        TextColor3 = C.sub,
        TextXAlignment = Enum.TextXAlignment.Left,
        ZIndex = 3,
    }, cell)
    return cell
end

local CELL_W, STATUS_W = 70, 136 -- 70 + 70 + 136 + two gaps of 6 = full width
local killsCell = makeInfoCell(PAD, CELL_W, "KILLS")
local hopsCell = makeInfoCell(PAD + CELL_W + 6, CELL_W, "HOPS")
local statusCell = makeInfoCell(PAD + CELL_W * 2 + 12, STATUS_W, "STATUS")

local function infoValue(parent, x)
    return new("TextLabel", {
        Position = UDim2.fromOffset(x, 15),
        Size = UDim2.new(1, -(x + 10), 0, 16),
        BackgroundTransparency = 1,
        Text = "",
        Font = Enum.Font.GothamBold,
        TextSize = 13,
        TextColor3 = C.white,
        TextXAlignment = Enum.TextXAlignment.Left,
        ZIndex = 3,
    }, parent)
end
local killsVal = infoValue(killsCell, 12)
local hopsVal = infoValue(hopsCell, 12)

local statusDot = new("Frame", {
    AnchorPoint = Vector2.new(0, 0.5),
    Position = UDim2.fromOffset(12, 23),
    Size = UDim2.fromOffset(6, 6),
    BackgroundColor3 = C.green,
    ZIndex = 3,
}, statusCell)
corner(3, statusDot)
local statusTxt = infoValue(statusCell, 24)
statusTxt.Font = Enum.Font.GothamMedium
statusTxt.TextSize = 12

local actColors = {
    ["Starting"] = C.blue,
    ["Collecting relics"] = GOLD,
    ["Fighting mobs"] = C.redHot,
    ["Looking for targets"] = C.sub,
    ["Hopping"] = C.orange,
    ["Stopped"] = C.red,
}
local lastKills = 0
refreshInfo = function()
    killsVal.Text = fmtNum(mobsKilled)
    hopsVal.Text = fmtNum(hopCount)
    statusTxt.Text = activity
    local col = actColors[activity] or C.green
    tween(statusTxt, 0.25, { TextColor3 = col })
    tween(statusDot, 0.25, { BackgroundColor3 = col })
    if mobsKilled > lastKills then -- a kill flashes the counter
        killsVal.TextColor3 = C.redHot
        tween(killsVal, 0.6, { TextColor3 = C.white })
    end
    lastKills = mobsKilled
end
refreshInfo()
end)

local srvChip = new("Frame", {
    Position = UDim2.fromOffset(PAD, 262),
    Size = UDim2.new(1, -PAD * 2, 0, 24),
    BackgroundColor3 = C.white,
    BackgroundTransparency = 0.95,
    ZIndex = 2,
}, pageHome)
corner(12, srvChip)
hairline(srvChip, 0.95)
local srvLbl = new("TextLabel", {
    Size = UDim2.fromScale(1, 1),
    BackgroundTransparency = 1,
    Text = "Server  •  -- players",
    Font = Enum.Font.Gotham,
    TextSize = 11,
    TextColor3 = C.sub,
    ZIndex = 3,
}, srvChip)

local sessionText, playersText = "00:00:00", "-- players"
local function refreshChip()
    srvLbl.Text = ("Session  %s  •  %s"):format(sessionText, playersText)
end
refreshChip()

-- credit, directly below the session chip: two name pills (tap one to copy the name)
new("TextLabel", {
    Position = UDim2.fromOffset(PAD, 296),
    Size = UDim2.new(1, -PAD * 2, 0, 12),
    BackgroundTransparency = 1,
    Text = "MADE BY",
    Font = Enum.Font.GothamMedium,
    TextSize = 10,
    TextColor3 = C.sub,
    ZIndex = 3,
}, pageHome)

guard("footer", function()
local function makeCredit(x, w, handle, color)
    local pillBtn = new("TextButton", {
        Position = UDim2.fromOffset(x, 310),
        Size = UDim2.fromOffset(w, 28),
        BackgroundColor3 = C.white,
        BackgroundTransparency = 0.94,
        Text = "",
        AutoButtonColor = false,
        ZIndex = 2,
    }, pageHome)
    corner(14, pillBtn)
    hairline(pillBtn, 0.92)

    local avatar = new("Frame", {
        AnchorPoint = Vector2.new(0, 0.5),
        Position = UDim2.new(0, 5, 0.5, 0),
        Size = UDim2.fromOffset(18, 18),
        BackgroundColor3 = color,
        ZIndex = 3,
    }, pillBtn)
    corner(9, avatar)
    new("TextLabel", {
        Size = UDim2.fromScale(1, 1),
        BackgroundTransparency = 1,
        Text = handle:sub(2, 2):upper(),
        Font = Enum.Font.GothamBold,
        TextSize = 10,
        TextColor3 = C.white,
        ZIndex = 4,
    }, avatar)
    new("TextLabel", {
        Position = UDim2.fromOffset(30, 0),
        Size = UDim2.new(1, -36, 1, 0),
        BackgroundTransparency = 1,
        Text = handle,
        Font = Enum.Font.GothamMedium,
        TextSize = 11,
        TextColor3 = C.white,
        TextXAlignment = Enum.TextXAlignment.Left,
        ZIndex = 3,
    }, pillBtn)

    pillBtn.MouseEnter:Connect(function() tween(pillBtn, 0.15, { BackgroundTransparency = 0.88 }) end)
    pillBtn.MouseLeave:Connect(function() tween(pillBtn, 0.15, { BackgroundTransparency = 0.94 }) end)
    pillBtn.MouseButton1Click:Connect(function()
        local ok = pcall(function() (setclipboard or toclipboard)(handle) end)
        toast(ok and ("Copied " .. handle) or handle, C.blue)
    end)
end
local CREDIT_W1 = 112
makeCredit(PAD, CREDIT_W1, "@siu70290", C.blue)
makeCredit(PAD + CREDIT_W1 + GAP, WIDTH - PAD * 2 - CREDIT_W1 - GAP, "@isabella_nyx9", Color3.fromRGB(191, 90, 242))

-- footer: performance (left) + hotkey hint (right) ------------
new("Frame", {
    Position = UDim2.fromOffset(PAD, FOOT_DIV),
    Size = UDim2.new(1, -PAD * 2, 0, 1),
    BackgroundColor3 = C.white,
    BackgroundTransparency = 0.93,
    BorderSizePixel = 0,
    ZIndex = 2,
}, body)

local footLeft = autoRow({ Position = UDim2.fromOffset(PAD, FOOT_Y), Height = 20 }, body, 8)
local perfDot = new("Frame", {
    Size = UDim2.fromOffset(6, 6),
    BackgroundColor3 = C.green,
    LayoutOrder = 1,
    ZIndex = 2,
}, footLeft)
corner(3, perfDot)
local perfLbl = new("TextLabel", {
    Size = UDim2.fromOffset(0, 20),
    AutomaticSize = Enum.AutomaticSize.X,
    BackgroundTransparency = 1,
    Text = "-- FPS  •  -- ms",
    Font = Enum.Font.Gotham,
    TextSize = 11,
    TextColor3 = C.sub,
    LayoutOrder = 2,
    ZIndex = 2,
}, footLeft)

local footRight = autoRow({
    Position = UDim2.new(1, -PAD, 0, FOOT_Y),
    AnchorPoint = Vector2.new(1, 0),
    Height = 20,
}, body, 8)
local keycap = new("Frame", {
    Size = UDim2.fromOffset(34, 18),
    BackgroundColor3 = C.white,
    BackgroundTransparency = 0.9,
    LayoutOrder = 1,
    ZIndex = 2,
}, footRight)
corner(5, keycap)
hairline(keycap, 0.86)
new("TextLabel", {
    Size = UDim2.fromScale(1, 1),
    BackgroundTransparency = 1,
    Text = "End",
    Font = Enum.Font.GothamMedium,
    TextSize = 10,
    TextColor3 = C.white,
    TextTransparency = 0.2,
    ZIndex = 3,
}, keycap)
new("TextLabel", {
    Size = UDim2.fromOffset(0, 20),
    AutomaticSize = Enum.AutomaticSize.X,
    BackgroundTransparency = 1,
    Text = "Emergency stop",
    Font = Enum.Font.Gotham,
    TextSize = 11,
    TextColor3 = C.sub,
    LayoutOrder = 2,
    ZIndex = 2,
}, footRight)

-- second footer row: the other hotkeys
local footHints = autoRow({
    Position = UDim2.new(0.5, 0, 0, FOOT_Y + 24),
    AnchorPoint = Vector2.new(0.5, 0),
    Height = 18,
}, body, 6)
local hintOrder = 0
local function hintKey(label, w)
    hintOrder += 1
    local cap = new("Frame", {
        Size = UDim2.fromOffset(w, 18),
        BackgroundColor3 = C.white,
        BackgroundTransparency = 0.9,
        LayoutOrder = hintOrder,
        ZIndex = 2,
    }, footHints)
    corner(5, cap)
    hairline(cap, 0.86)
    new("TextLabel", {
        Size = UDim2.fromScale(1, 1),
        BackgroundTransparency = 1,
        Text = label,
        Font = Enum.Font.GothamMedium,
        TextSize = 10,
        TextColor3 = C.white,
        TextTransparency = 0.2,
        ZIndex = 3,
    }, cap)
end
local function hintText(text)
    hintOrder += 1
    new("TextLabel", {
        Size = UDim2.fromOffset(0, 18),
        AutomaticSize = Enum.AutomaticSize.X,
        BackgroundTransparency = 1,
        Text = text,
        Font = Enum.Font.Gotham,
        TextSize = 11,
        TextColor3 = C.sub,
        LayoutOrder = hintOrder,
        ZIndex = 2,
    }, footHints)
end
local function hintGap()
    hintOrder += 1
    new("Frame", { Size = UDim2.fromOffset(10, 1), BackgroundTransparency = 1, LayoutOrder = hintOrder }, footHints)
end
hintKey("Home", 38)
hintText("Restart")
hintGap()
hintKey("RShift", 48)
hintText("Hide / show")

local fpsAcc, fpsFrames, pingTxt = 0, 0, "--"
conns[#conns + 1] = RunService.Heartbeat:Connect(function(dt)
    fpsAcc += dt
    fpsFrames += 1
    if fpsAcc >= 0.5 then
        local fps = math.floor(fpsFrames / fpsAcc + 0.5)
        perfLbl.Text = ("%d FPS  •  %s ms"):format(fps, pingTxt)
        perfDot.BackgroundColor3 = fps >= 50 and C.green or (fps >= 30 and C.orange or C.red)
        fpsAcc, fpsFrames = 0, 0
    end
end)

task.spawn(function()
    local ok, item = pcall(function()
        return game:GetService("Stats").Network.ServerStatsItem["Data Ping"]
    end)
    while env.FH_TOKEN == token do
        pcall(function()
            playersText = ("%d / %d players"):format(#Players:GetPlayers(), Players.MaxPlayers)
            refreshChip()
        end)
        if ok and item then
            local okv, v = pcall(function() return item:GetValue() end)
            if okv and type(v) == "number" then pingTxt = tostring(math.floor(v + 0.5)) end
        end
        task.wait(2)
    end
end)
end)

-- timer logic -------------------------------------------------
local lastTick = os.clock()
local sessionStart = os.clock()

local function updateTime()
    local now = os.clock()
    total += now - lastTick
    lastTick = now
    setTime(total)
    sessionText = fmtTime(now - sessionStart)
    refreshChip()
    updateRate()
end

local restoreUI, restartAll -- defined below
onClose = function()
    if not halted then updateTime() end
    save()
end

resetBtn.MouseButton1Click:Connect(function()
    if halted then
        restartAll()
        return
    end
    total = 0
    resetRelicStats()
    lastTick = os.clock()
    setTime(total)
    save()
    resetBtn.Text = "Cleared"
    toast("Timer cleared", C.blue)
    task.delay(1, function()
        if resetBtn.Parent then resetBtn.Text = "Reset" end
    end)
end)

-- emergency stop ----------------------------------------------
local function emergencyStop()
    if halted then return end
    updateTime()
    save()
    halted = true -- every loop checks alive(), so all of them end
    setActivity("Stopped")
    if relicCleanup then pcall(relicCleanup) end

    pcall(function()
        local char = lp.Character
        local hum = char and char:FindFirstChildOfClass("Humanoid")
        local hrp = char and char:FindFirstChild("HumanoidRootPart")
        if hum then hum:Move(Vector3.zero, false) end
        if hrp then
            hrp.AssemblyLinearVelocity = Vector3.zero
            hrp.AssemblyAngularVelocity = Vector3.zero
        end
    end)

    showPage("home")
    pulse:Cancel()
    pillDot.BackgroundTransparency = 0
    for _, b in ipairs(colonBlink) do b:Cancel() end
    setStatus("Stopped", C.red)

    for _, lbl in ipairs(cells) do tween(lbl, 0.3, { TextColor3 = C.sub }) end
    for _, c in ipairs(colons) do c.TextTransparency = 0.5 end

    hopLbl.Text = "Paused"
    tween(hopLbl, 0.3, { TextColor3 = C.sub })
    tween(fill, 0.3, { BackgroundColor3 = C.gray })

    stopTxt.Text = "Stopped"
    for _, c in ipairs(farmConns) do c:Disconnect() end
    table.clear(farmConns)
    resetBtn.Text = "Restart"
    tween(resetBtn, 0.3, { BackgroundColor3 = C.green, BackgroundTransparency = 0.8, TextColor3 = C.green })
    tween(stopBtn, 0.3, { BackgroundColor3 = C.gray })
    tween(stopTxt, 0.3, { TextColor3 = C.sub })
    tween(stopIcon, 0.3, { BackgroundColor3 = C.sub })
    tween(stopGlow, 0.3, { BackgroundTransparency = 1 })
    tween(relicLbl, 0.3, { TextColor3 = C.sub })
    tween(gem, 0.3, { BackgroundColor3 = C.gray })
    tween(gemHalo, 0.3, { BackgroundTransparency = 1 })
    tween(gemFacet, 0.3, { BackgroundTransparency = 0.8 })

    mainStroke.Color = C.red
    mainStroke.Transparency = 0.2
    tween(mainStroke, 0.9, { Transparency = 0.65 })
    toast("All actions stopped", C.red)
end

restoreUI = function()
    pulse:Play()
    for _, b in ipairs(colonBlink) do b:Play() end
    pillDot.BackgroundTransparency = 0
    setStatus("Active", C.green)

    for _, lbl in ipairs(cells) do tween(lbl, 0.3, { TextColor3 = C.white }) end
    for _, c in ipairs(colons) do c.TextTransparency = 0 end

    hopLbl.Text = HOP_TIME .. "s"
    tween(hopLbl, 0.3, { TextColor3 = C.white })
    tween(relicLbl, 0.3, { TextColor3 = C.white })
    tween(gem, 0.3, { BackgroundColor3 = GOLD })
    tween(gemHalo, 0.3, { BackgroundTransparency = 0.86 })
    tween(gemFacet, 0.3, { BackgroundTransparency = 0.45 })
    tween(fill, 0.3, { BackgroundColor3 = C.blue, Size = UDim2.fromScale(1, 1) })

    stopTxt.Text = "Emergency Stop"
    tween(stopBtn, 0.3, { BackgroundColor3 = C.red })
    tween(stopTxt, 0.3, { TextColor3 = C.white })
    tween(stopIcon, 0.3, { BackgroundColor3 = C.white })
    tween(stopGlow, 0.3, { BackgroundTransparency = 0.88 })

    resetBtn.Text = "Reset"
    tween(resetBtn, 0.3, { BackgroundColor3 = C.white, BackgroundTransparency = 0.9, TextColor3 = C.white })

    mainStroke.Color = C.white
    tween(mainStroke, 0.5, { Transparency = 0.86 })
end

stopBtn.MouseButton1Click:Connect(emergencyStop)
conns[#conns + 1] = UserInputService.InputBegan:Connect(function(input, processed)
    if processed then return end
    if input.KeyCode == Enum.KeyCode.End then
        emergencyStop()
    elseif input.KeyCode == Enum.KeyCode.Home then
        if halted then restartAll() end
    elseif input.KeyCode == Enum.KeyCode.RightShift then
        toggleWindow()
    end
end)

-- open animation
tween(rootScale, 0.55, { Scale = fitScale() }, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
tween(main, 0.4, { BackgroundTransparency = 0.04 })
task.delay(1, function()
    if alive() then toast("Auto relic is on", C.green) end
end)
task.delay(3.6, function()
    if alive() and not halted then
        if reloadQueued then
            toast("Re-execute after hop: ready", C.green)
        else
            toast("Re-execute off: put file in workspace", C.orange)
        end
    end
end)

guard("viewport", function()
    local cam0 = workspace.CurrentCamera
    if cam0 then
        conns[#conns + 1] = cam0:GetPropertyChangedSignal("ViewportSize"):Connect(function()
            rootScale.Scale = fitScale()
        end)
    end
end)

-- cleanup watcher (window stays open after Emergency Stop; closing or re-running removes it)
task.spawn(function()
    while env.FH_TOKEN == token do task.wait(0.25) end
    for _, c in ipairs(conns) do c:Disconnect() end
    for _, c in ipairs(farmConns) do c:Disconnect() end
    if relicCleanup then pcall(relicCleanup) end
    gui:Destroy()
end)

local function startTimer()
    task.spawn(function()
        local run = runId
        local n = 0
        while alive(run) do
            task.wait(1)
            if not alive(run) then break end
            updateTime()
            n += 1
            if n % 5 == 0 then save() end
        end
    end)
end

local function notify(title, text, dur)
    for _ = 1, 10 do
        local ok = pcall(function()
            StarterGui:SetCore("SendNotification", {
                Title = title,
                Text = text,
                Duration = dur or 5,
            })
        end)
        if ok then return end
        task.wait(0.5)
    end
end

local hopping = false

-- servers already visited (never bounce back to the same one), remembered 30 min
local serverHop
guard("network", function()
local visited = {}
pcall(function()
    if isfile and isfile(VISITED_FILE) then
        local data = HttpService:JSONDecode(readfile(VISITED_FILE))
        for id, t in pairs(data) do
            if type(t) == "number" and os.time() - t < 1800 then visited[id] = t end
        end
    end
end)
visited[game.JobId] = os.time()

local function saveVisited()
    pcall(function()
        if writefile then writefile(VISITED_FILE, HttpService:JSONEncode(visited)) end
    end)
end

local function httpGet(url)
    local ok, body = pcall(function() return game:HttpGet(url) end)
    if ok and body then return body end
    local req = (syn and syn.request) or http_request or request
    if req then
        local ok2, res = pcall(req, { Url = url, Method = "GET" })
        if ok2 and res and res.Body then return res.Body end
    end
    return nil
end

local tpFailed = false
conns[#conns + 1] = TeleportService.TeleportInitFailed:Connect(function(player)
    if player == lp then tpFailed = true end
end)

function serverHop()
    if hopping then return end
    hopping = true
    local run = runId
    setStatus("Hopping", C.orange)
    setActivity("Hopping")
    task.spawn(function()
        while alive(run) do
            local picked, cursor
            local backoff = 2
            for _ = 1, 6 do
                local url = ("https://games.roblox.com/v1/games/%d/servers/Public?sortOrder=Asc&excludeFullGames=true&limit=100"):format(game.PlaceId)
                if cursor then url = url .. "&cursor=" .. cursor end

                local body = httpGet(url)
                local ok, res = pcall(function() return HttpService:JSONDecode(body) end)

                if body and ok and type(res) == "table" and res.data then
                    local pool = {}
                    for _, sv in ipairs(res.data) do
                        if sv.id ~= game.JobId and not visited[sv.id] and sv.playing and sv.maxPlayers
                            and sv.playing < sv.maxPlayers - 1 then
                            pool[#pool + 1] = sv.id
                        end
                    end
                    if #pool > 0 then
                        picked = pool[math.random(#pool)]
                        break
                    end
                    cursor = res.nextPageCursor
                    if not cursor then break end
                else
                    task.wait(backoff) -- rate limited: wait longer each time
                    backoff = math.min(backoff * 2, 10)
                end
                if not alive(run) then return end
            end

            if not alive(run) then return end
            updateTime()
            save()

            tpFailed = false
            if picked then
                visited[picked] = os.time()
                saveVisited()
                pcall(function()
                    TeleportService:TeleportToPlaceInstance(game.PlaceId, picked, lp)
                end)
            else
                pcall(function() TeleportService:Teleport(game.PlaceId, lp) end)
            end

            hopCount += 1
            refreshInfo()

            -- wait for the teleport, retry sooner if Roblox reports it failed
            local waited = 0
            while alive(run) and waited < 15 and not tpFailed do
                task.wait(0.5)
                waited += 0.5
            end
            if tpFailed then
                hopCount -= 1
                refreshInfo()
                task.wait(1.5)
            end
        end
    end)
end
end)

guard("hop card", function()
    local b = new("TextButton", {
        Size = UDim2.fromScale(1, 1),
        BackgroundTransparency = 1,
        Text = "",
        AutoButtonColor = false,
        ZIndex = 8,
    }, hopCard)
    b.Activated:Connect(function()
        if halted then toast("Stopped. Tap Restart", C.red) return end
        if hopping then return end
        toast("Hopping now", C.orange)
        serverHop()
    end)
end)

-- ============================================================
--  Auto Relic engine
-- ============================================================
local Workspace   = game:GetService("Workspace")
local VirtualUser = game:GetService("VirtualUser")

local CONFIG = {
    SearchRadius = 500,
    IdleScanInterval = 0.3,
    RelicKeyword = "relic",

    -- glide speed comes from the Glide speed setting (GLIDE_SPEED)
    MinTweenTime = 0.25,      -- never a blink-fast glide
    MaxTweenTime = 4,
    EasingStyle = Enum.EasingStyle.Sine,
    EasingDirection = Enum.EasingDirection.InOut,

    StopDistance = 3,
    HeightOffset = 2,

    CollectTimeout = 4,       -- max seconds to spend on ONE relic
    CollectInterval = 0.5,    -- how long to wait for the game to accept a pickup before retrying
    MaxFiresPerRelic = 4,     -- hard cap so one relic is never spammed
    PickupGap = 0.45,         -- minimum seconds between ANY two pickups (stays inside the game's cooldown)
    PickupGapMax = 1.6,       -- the gap grows up to this if the game keeps refusing pickups
    RemoteCollectRange = 25,
    Cooldown = 0.45,          -- pause after a successful collect
    FailBlacklistTime = 6,    -- skip an uncollectable relic for this long

    MobNames = { "bandit mad", "evil thug", "bandit", "puriza minion", "puriza" },
    MobRadius = 1000,         -- how far away a mob can be and still get farmed
    MobTimeout = 12,          -- give up on one mob after this many seconds
    MobStep = 0.08,           -- how often we re-stick to a moving mob

    Noclip = true,            -- only used while gliding (instant teleport off)
    ESPColor = Color3.fromRGB(255, 215, 0),
}

local activeTween, noclipConn
local prompts, highlights = {}, {}
local collected = setmetatable({}, { __mode = "k" }) -- parts already collected
local failed = setmetatable({}, { __mode = "k" })    -- part -> retry time
local mobs = {}                                        -- Humanoid -> true (matching mobs)
local mobFailed = setmetatable({}, { __mode = "k" })  -- mob root -> retry time

local function wipe(t) for k in pairs(t) do t[k] = nil end end

local function getCharacter()
    local char = lp.Character
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if hum and hrp and hum.Health > 0 then
        return char, hum, hrp
    end
end

local function isRelicPart(part)
    if not part or not part:IsA("BasePart") then return false end
    if part.Name:lower():find(CONFIG.RelicKeyword, 1, true) then return true end
    return part:FindFirstChildWhichIsA("ParticleEmitter") ~= nil
        or part:FindFirstChildWhichIsA("PointLight") ~= nil
end

local function isSkipped(part)
    if collected[part] then return true end
    local retryAt = failed[part]
    if retryAt then
        if os.clock() >= retryAt then
            failed[part] = nil
            return false
        end
        return true
    end
    return false
end

-- collected = prompt/part is gone or the prompt is disabled
local function isGone(prompt, part)
    return not prompt.Parent
        or not prompt.Enabled
        or not part.Parent
        or not part:IsDescendantOf(Workspace)
end

local function addESP(part)
    if not flags.esp or highlights[part] then return end
    local hl = Instance.new("Highlight")
    hl.FillColor = CONFIG.ESPColor
    hl.OutlineColor = Color3.new(1, 1, 1)
    hl.FillTransparency = 0.5
    hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
    hl.Adornee = part
    hl.Parent = part
    highlights[part] = hl
end

local function removeESP(part)
    local hl = highlights[part]
    if hl then
        hl:Destroy()
        highlights[part] = nil
    end
end

local function clearESP()
    for part in pairs(highlights) do removeESP(part) end
end

setESP = function(on)
    if not on then
        clearESP()
        return
    end
    for prompt in pairs(prompts) do
        local part = prompt.Parent
        if part and prompt.Enabled and isRelicPart(part) and not collected[part] then
            addESP(part)
        end
    end
end

local register
guard("mob names", function()
local mobNameSet = {}
for _, n in ipairs(CONFIG.MobNames) do mobNameSet[n] = true end

-- "Bandit 2", "Bandit_3", "Bandit (4)" all count as "bandit"
local function isMobName(name)
    local n = name:lower()
    n = (n:gsub("[%s_%-#%(%)]*%d+[%s%)]*$", ""))
    n = n:match("^%s*(.-)%s*$")
    return mobNameSet[n] == true
end

function register(obj)
    if obj:IsA("Humanoid") then
        local model = obj.Parent
        if model and isMobName(model.Name) and not Players:GetPlayerFromCharacter(model) then
            mobs[obj] = true
        end
        return
    end
    if not obj:IsA("ProximityPrompt") then return end
    prompts[obj] = true

    -- instant prompts: no hold, no line of sight needed
    pcall(function()
        obj.HoldDuration = 0
        obj.RequiresLineOfSight = false
        obj.MaxActivationDistance = math.max(obj.MaxActivationDistance, CONFIG.RemoteCollectRange)
    end)

    local part = obj.Parent
    if isRelicPart(part) and obj.Enabled and not collected[part] then
        addESP(part)
    end

    -- a relic that respawns (prompt re-enabled) can be collected again
    farmConns[#farmConns + 1] = obj:GetPropertyChangedSignal("Enabled"):Connect(function()
        local p = obj.Parent
        if not p then return end
        if obj.Enabled then
            collected[p] = nil
            failed[p] = nil
            if isRelicPart(p) then addESP(p) end
        else
            removeESP(p)
        end
    end)
end
end)

local function getSortedRelics(hrp)
    local list = {}
    for prompt in pairs(prompts) do
        local part = prompt.Parent
        if prompt.Enabled and part and part:IsDescendantOf(Workspace)
            and isRelicPart(part) and not isSkipped(part) then
            local dist = (hrp.Position - part.Position).Magnitude
            if dist <= CONFIG.SearchRadius then
                list[#list + 1] = { part = part, prompt = prompt, dist = dist }
            end
        end
    end
    table.sort(list, function(a, b) return a.dist < b.dist end)
    return list
end

local function setNoclip(on)
    if noclipConn then
        noclipConn:Disconnect()
        noclipConn = nil
    end
    if not (on and CONFIG.Noclip) then return end
    noclipConn = RunService.Stepped:Connect(function()
        local char = lp.Character
        if not char then return end
        for _, p in ipairs(char:GetDescendants()) do
            if p:IsA("BasePart") then p.CanCollide = false end
        end
    end)
end

local function cancelTween()
    if activeTween then
        activeTween:Cancel()
        activeTween = nil
    end
    setNoclip(false)
    local _, _, hrp = getCharacter()
    if hrp then hrp.Anchored = false end
end

local function moveTo(hrp, goal, distance)
    if flags.instantTp then
        hrp.CFrame = goal
        hrp.AssemblyLinearVelocity = Vector3.zero
        hrp.AssemblyAngularVelocity = Vector3.zero
        return true
    end

    local duration = math.clamp(distance / GLIDE_SPEED, CONFIG.MinTweenTime, CONFIG.MaxTweenTime)
    local tw = TweenService:Create(
        hrp,
        TweenInfo.new(duration, CONFIG.EasingStyle, CONFIG.EasingDirection),
        { CFrame = goal }
    )
    activeTween = tw
    hrp.Anchored = true
    setNoclip(true)
    tw:Play()
    local state = tw.Completed:Wait()
    activeTween = nil
    setNoclip(false)

    if hrp.Parent then
        hrp.Anchored = false
        hrp.AssemblyLinearVelocity = Vector3.zero
        hrp.AssemblyAngularVelocity = Vector3.zero
    end
    return state == Enum.PlaybackState.Completed
end

local function goNextTo(part)
    local _, _, hrp = getCharacter()
    if not hrp then return false end

    local distance = (part.Position - hrp.Position).Magnitude
    if distance <= CONFIG.StopDistance then return true end

    local direction = (part.Position - hrp.Position).Unit
    local stopPoint = part.Position - direction * CONFIG.StopDistance
        + Vector3.new(0, CONFIG.HeightOffset, 0)
    return moveTo(hrp, CFrame.lookAt(stopPoint, part.Position), distance - CONFIG.StopDistance)
end

local lastFire = 0
local pickupGap = CONFIG.PickupGap -- adapts: grows when the game refuses pickups, shrinks back after a success

local function firePrompt(prompt)
    local gap = pickupGap + math.random() * 0.08
    local waitFor = gap - (os.clock() - lastFire)
    if waitFor > 0 then task.wait(waitFor) end
    lastFire = os.clock()
    if typeof(fireproximityprompt) == "function" then
        fireproximityprompt(prompt)
    else
        prompt:InputHoldBegin()
        task.wait(0.03)
        prompt:InputHoldEnd()
    end
end

-- stays on ONE relic until it is confirmed collected (or times out)
local function collect(prompt, part, run)
    pcall(function()
        prompt.HoldDuration = 0
        prompt.RequiresLineOfSight = false
        prompt.MaxActivationDistance = math.max(prompt.MaxActivationDistance, CONFIG.RemoteCollectRange)
    end)

    local startTime = os.clock()
    local fires = 0
    while alive(run) and os.clock() - startTime < CONFIG.CollectTimeout
        and fires < CONFIG.MaxFiresPerRelic do
        if isGone(prompt, part) then return true end

        local _, _, hrp = getCharacter()
        if not hrp then return false end

        -- pushed away? go back to the relic
        if (hrp.Position - part.Position).Magnitude > CONFIG.RemoteCollectRange then
            if not goNextTo(part) then return false end
        end

        firePrompt(prompt)
        fires += 1

        -- give the game time to accept the pickup; stop waiting the moment it is collected
        local t0 = os.clock()
        while alive(run) and os.clock() - t0 < CONFIG.CollectInterval and not isGone(prompt, part) do
            task.wait(0.05)
        end
        if isGone(prompt, part) then return true end

        -- not accepted: most likely the game's pickup cooldown, so slow down instead of spamming
        pickupGap = math.min(pickupGap * 1.4, CONFIG.PickupGapMax)
    end
    return isGone(prompt, part)
end

local function processRelic(entry, run)
    local part, prompt = entry.part, entry.prompt

    if not goNextTo(part) then
        if alive(run) then failed[part] = os.clock() + CONFIG.FailBlacklistTime end
        return
    end
    if not alive(run) then return end

    if not getCharacter() or isGone(prompt, part) then
        collected[part] = true
        removeESP(part)
        return
    end

    if collect(prompt, part, run) then
        collected[part] = true
        removeESP(part)
        if alive(run) then
            relicsTotal += 1
            sessionRelics += 1
            bumpRelics(true)
            updateRate()
        end
        pickupGap = math.max(CONFIG.PickupGap, pickupGap * 0.8) -- accepted: ease back toward normal
        task.wait(CONFIG.Cooldown)
    elseif alive(run) then
        failed[part] = os.clock() + CONFIG.FailBlacklistTime -- skip briefly, move on
    end
end

-- nearest living mobs first
local function getSortedMobs(hrp)
    local list = {}
    for hum in pairs(mobs) do
        local model = hum.Parent
        local root = model and model:FindFirstChild("HumanoidRootPart")
        if hum.Health > 0 and root and root:IsDescendantOf(Workspace) then
            local retryAt = mobFailed[root]
            if retryAt and os.clock() >= retryAt then
                mobFailed[root] = nil
                retryAt = nil
            end
            if not retryAt then
                local dist = (hrp.Position - root.Position).Magnitude
                if dist <= CONFIG.MobRadius then
                    list[#list + 1] = { hum = hum, root = root, dist = dist }
                end
            end
        end
    end
    table.sort(list, function(a, b) return a.dist < b.dist end)
    return list
end

-- stays on ONE mob until it dies (or times out), using the same teleport as the relics
local function farmMob(entry, run)
    local hum, root = entry.hum, entry.root
    local startTime = os.clock()
    mobTarget = root

    -- glide mode only: if the mob dies, disappears or Farm mobs is switched off
    -- mid-glide, cancel the tween right away instead of finishing the trip
    local watching = true
    task.spawn(function()
        while watching and alive(run) do
            if not hum.Parent or hum.Health <= 0 or not flags.farmMobs then
                if activeTween then activeTween:Cancel() end
                break
            end
            task.wait(0.05)
        end
    end)

    while alive(run) and flags.farmMobs
        and hum.Parent and hum.Health > 0 and root.Parent
        and os.clock() - startTime < CONFIG.MobTimeout do

        local _, _, hrp = getCharacter()
        if not hrp then break end

        -- a relic showed up: relics always come first
        if #getSortedRelics(hrp) > 0 then
            watching = false
            mobTarget = nil
            return
        end

        if not goNextTo(root) then break end
        task.wait(CONFIG.MobStep)
    end

    watching = false
    mobTarget = nil
    if alive(run) and hum.Health <= 0 then
        mobsKilled += 1
        refreshInfo()
    end
    if alive(run) and flags.farmMobs and hum.Parent and hum.Health > 0 then
        mobFailed[root] = os.clock() + CONFIG.FailBlacklistTime -- skip it for a moment, move on
    end
end

relicCleanup = function()
    cancelTween()
    clearESP()
end

local function startRelic()
    local run = runId
    for _, c in ipairs(farmConns) do c:Disconnect() end
    table.clear(farmConns)
    wipe(prompts)
    wipe(collected)
    wipe(failed)
    wipe(mobs)
    wipe(mobFailed)
    mobTarget = nil
    clearESP()

    for _, obj in ipairs(Workspace:GetDescendants()) do register(obj) end
    farmConns[#farmConns + 1] = Workspace.DescendantAdded:Connect(register)
    farmConns[#farmConns + 1] = Workspace.DescendantRemoving:Connect(function(obj)
        if obj:IsA("Humanoid") then mobs[obj] = nil end
        if obj:IsA("ProximityPrompt") then
            prompts[obj] = nil
            if obj.Parent then removeESP(obj.Parent) end
        end
    end)

    -- main collect loop
    task.spawn(function()
        local emptySince
        while alive(run) do
            local _, _, hrp = getCharacter()
            if hrp then
                local relics = getSortedRelics(hrp)
                if #relics > 0 then
                    emptySince = nil
                    if not hopping then setActivity("Collecting relics") end
                    local ok, err = pcall(processRelic, relics[1], run)
                    if not ok then
                        warn("[Fast Hub] " .. tostring(err))
                        cancelTween()
                        failed[relics[1].part] = os.clock() + CONFIG.FailBlacklistTime
                    end
                    task.wait()
                elseif flags.farmMobs and #getSortedMobs(hrp) > 0 then
                    emptySince = nil -- still busy, not an empty server
                    if not hopping then setActivity("Fighting mobs") end
                    local ok, err = pcall(farmMob, getSortedMobs(hrp)[1], run)
                    if not ok then
                        warn("[Fast Hub] " .. tostring(err))
                        mobTarget = nil
                        cancelTween()
                    end
                    task.wait()
                else
                    emptySince = emptySince or os.clock()
                    if not hopping then setActivity("Looking for targets") end
                    if EARLY_HOP and flags.autoHop and not hopping and os.clock() - emptySince >= EMPTY_HOP then
                        serverHop() -- nothing left here, move on early
                    end
                    task.wait(CONFIG.IdleScanInterval)
                end
            else
                emptySince = nil
                task.wait(1)
            end
        end
    end)

    -- hop countdown
    task.spawn(function()
        repeat task.wait(0.25) until getCharacter() or not alive(run)
        local start = os.clock()
        while alive(run) and not hopping do
            if not flags.autoHop then
                start = os.clock()
                setHopOff()
                task.wait(0.25)
            else
                local left = HOP_TIME - (os.clock() - start)
                setHop(left)
                if left <= 0 then break end
                task.wait(0.25)
            end
        end
        if alive(run) and not hopping then serverHop() end
    end)

    -- auto punch: always on, runs together with the relic farm.
    -- Tied to this run, so Emergency Stop ends it and Restart (Home) starts it again.
    task.spawn(function()
        local remotes = ReplicatedStorage:WaitForChild("Remotes", 15)
        local PunchRemote = remotes and remotes:WaitForChild("SkillRemote", 15)
        if not PunchRemote then
            warn("[Fast Hub] SkillRemote not found, auto punch is off")
            return
        end

        while alive(run) do
            local character = lp.Character
            local root = character and character:FindFirstChild("HumanoidRootPart")
            local camera = workspace.CurrentCamera

            if root and camera then
                pcall(function()
                    PunchRemote:FireServer({
                        Camera = camera.CFrame,
                        SkillId = "1",
                        Began = true,
                        CFrame = root.CFrame,
                        ["Typ\208\181"] = 1,
                        Aim = (mobTarget and mobTarget.Parent and mobTarget.Position)
                            or (root.Position + camera.CFrame.LookVector * 100),
                    })
                end)
            end

            task.wait()
        end
    end)
end

conns[#conns + 1] = lp.CharacterAdded:Connect(function()
    cancelTween()
end)

conns[#conns + 1] = lp.Idled:Connect(function() -- anti-AFK
    pcall(function()
        VirtualUser:CaptureController()
        VirtualUser:ClickButton2(Vector2.new())
    end)
end)

-- live counts for the Settings text (relics glowing / mobs nearby), refreshed every second
task.spawn(function()
    while env.FH_TOKEN == token do
        if not halted then
            local r, m = 0, 0
            for prompt in pairs(prompts) do
                local part = prompt.Parent
                if prompt.Enabled and part and part:IsDescendantOf(Workspace)
                    and isRelicPart(part) and not collected[part] then
                    r += 1
                end
            end
            local _, _, hrp = getCharacter()
            for hum in pairs(mobs) do
                local root = hum.Parent and hum.Parent:FindFirstChild("HumanoidRootPart")
                if hum.Health > 0 and root
                    and (not hrp or (hrp.Position - root.Position).Magnitude <= CONFIG.MobRadius) then
                    m += 1
                end
            end
            liveRelics, liveMobs = r, m
            if refreshSubs then refreshSubs() end
        end
        task.wait(1)
    end
end)

-- launches every loop; each one is tied to this run id
local function startAll(isRestart)
    runId += 1
    hopping = false
    setActivity("Starting")
    startTimer()
    startRelic()
    if not isRestart then
        task.spawn(notify, "Auto relic", "On  •  End = stop, Home = restart, RightShift = hide", 5)
    end
end

-- Reset after a stop: wipes timer, session and relic count, restores the UI, starts again
restartAll = function()
    if env.FH_TOKEN ~= token or not halted then return end
    total = 0
    lastTick = os.clock()
    sessionStart = os.clock()
    save()
    setTime(0)
    halted = false
    restoreUI()
    sessionText = "00:00:00"
    refreshChip()
    resetRelicStats()
    save()
    toast("Restarted", C.green)
    startAll(true)
end

startAll(false)
