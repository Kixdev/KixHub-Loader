-- KIXHUB 99 Nights payload
-- Channel: development

local __modules = {}
local __cache = {}

function KixRequire(name)
    if __cache[name] ~= nil then return __cache[name] end
    local factory = __modules[name]
    assert(factory, 'Unknown module: ' .. tostring(name))
    local value = factory()
    __cache[name] = value
    return value
end

__modules["Core.ConnectionBag"] = function()
local ConnectionBag = {}
ConnectionBag.__index = ConnectionBag

function ConnectionBag.new()
    return setmetatable({ Items = {} }, ConnectionBag)
end

function ConnectionBag:Add(item)
    self.Items[#self.Items + 1] = item
    return item
end

function ConnectionBag:Cleanup()
    for index = #self.Items, 1, -1 do
        local item = self.Items[index]
        if type(item) == "function" then
            pcall(item)
        elseif type(item) == "table" then
            if type(item.Disconnect) == "function" then
                pcall(item.Disconnect, item)
            elseif type(item.Destroy) == "function" then
                pcall(item.Destroy, item)
            end
        end
        self.Items[index] = nil
    end
end

return ConnectionBag
end

__modules["Core.FeatureManager"] = function()
local FeatureManager = {}
FeatureManager.__index = FeatureManager

function FeatureManager.new(runtime)
    return setmetatable({ Runtime = runtime, Features = {} }, FeatureManager)
end

function FeatureManager:Register(name, feature)
    assert(type(name) == "string" and type(feature) == "table", "Invalid feature")
    self.Features[name] = feature
end

function FeatureManager:Start(name)
    local feature = self.Features[name]
    if not feature or type(feature.Start) ~= "function" then return false end
    if feature.Active then return true end
    feature.Active = feature.Start(self.Runtime) ~= false
    return feature.Active
end

function FeatureManager:Stop(name, reason)
    local feature = self.Features[name]
    if not feature or not feature.Active then return end
    if type(feature.Stop) == "function" then
        feature:Stop(reason)
    end
    feature.Active = false
end

function FeatureManager:StopAll(reason)
    for name in pairs(self.Features) do
        self:Stop(name, reason)
    end
end

return FeatureManager
end

__modules["Core.Runtime"] = function()
local ConnectionBag = KixRequire("Core.ConnectionBag")

local Runtime = {}
Runtime.__index = Runtime

function Runtime.new(context)
    return setmetatable({
        Context = context,
        State = "idle",
        Connections = ConnectionBag.new(),
    }, Runtime)
end

function Runtime:Start()
    if self.State ~= "idle" then return false end
    self.State = "running"
    return true
end

function Runtime:Stop(reason)
    if self.State == "stopped" then return end
    self.State = "stopped"
    self.StopReason = reason
    self.Connections:Cleanup()
end

return Runtime
end

__modules["Games.99Nights.entry"] = function()
local Runtime = KixRequire("Core.Runtime")
local FeatureManager = KixRequire("Core.FeatureManager")
local WindUIProvider = KixRequire("UI.WindUIProvider")
local UIAdapter = KixRequire("UI.WindUIAdapter")

local Entry = {}

function Entry.Start(context)
    context = context or {}

    local runtime = Runtime.new(context)
    local features = FeatureManager.new(runtime)
    local windUI = WindUIProvider.Load(context.WindUIUrl)
    local ui = UIAdapter.Build(windUI, {
        Title = "KixHub | 99 Nights",
        Author = "KixHub",
        WatermarkTitle = "99 Nights",
    })

    runtime.Features = features
    runtime.UI = ui
    runtime:Start()

    local status = ui.Tabs.Main:Section({
        Title = "Runtime",
        Opened = true,
    })

    status:Paragraph({
        Title = "Interface ready",
        Content = "Feature modules will be loaded independently.",
    })

    return function(reason)
        features:StopAll(reason or "shutdown")
        runtime:Stop(reason or "shutdown")
        if ui.Watermark and ui.Watermark.Destroy then
            ui.Watermark:Destroy()
        end
        if ui.Window and ui.Window.Destroy then
            ui.Window:Destroy()
        end
    end
end

return Entry
end

__modules["Games.99Nights.manifest"] = function()
return {
    Name = "99 Nights in the Forest",
    Slug = "99nights",
    PlaceIds = { "79546208627805" },
    GameIds = { "7326934954" },
    TemplateVersion = 1,
    Version = "0.1.0",
}
end

__modules["Shared.Cache"] = function()
local Cache = {}
Cache.__index = Cache

function Cache.new()
    return setmetatable({ Values = {} }, Cache)
end

function Cache:Get(key)
    return self.Values[key]
end

function Cache:Set(key, value)
    self.Values[key] = value
    return value
end

function Cache:Clear()
    table.clear(self.Values)
end

return Cache
end

__modules["Shared.RateLimiter"] = function()
local RateLimiter = {}
RateLimiter.__index = RateLimiter

function RateLimiter.new(interval)
    return setmetatable({ Interval = interval or 0.1, Last = 0 }, RateLimiter)
end

function RateLimiter:Allow(now)
    now = now or os.clock()
    if now - self.Last < self.Interval then return false end
    self.Last = now
    return true
end

return RateLimiter
end

__modules["Shared.Scheduler"] = function()
local Scheduler = {}
Scheduler.__index = Scheduler

function Scheduler.new()
    return setmetatable({ Jobs = {}, Running = false }, Scheduler)
end

function Scheduler:Add(name, callback, interval)
    self.Jobs[name] = {
        Callback = callback,
        Interval = interval or 1,
    }
end

function Scheduler:Remove(name)
    self.Jobs[name] = nil
end

function Scheduler:Clear()
    table.clear(self.Jobs)
end

return Scheduler
end

__modules["UI.WindUIAdapter"] = function()
local UI = {}

function UI.Build(WindUI, options)
    options = options or {}

    local window = WindUI:CreateWindow({
        Title = options.Title or "KixHub",
        Author = options.Author or "KixHub",
        Theme = options.Theme or "Dark",
        Size = options.Size or UDim2.fromOffset(860, 580),
        TwoColumns = true,
        BackgroundBlur = false,
        Resizable = true,
        HideSearchBar = false,
    })

    local tabs = {}
    local orderedTabs = {}

    local function addTab(key, title, icon)
        local tab = window:Tab({ Title = title, Icon = icon })
        tabs[key] = tab
        orderedTabs[#orderedTabs + 1] = tab
        return tab
    end

    addTab("Community", "Community", "messages-square")
    addTab("Updates", "What's New", "sparkles")
    addTab("Support", "Support", "heart-handshake")

    window:Divider()

    addTab("Main", "Main", "house")
    addTab("Bring", "Bring", "package-open")
    addTab("Teleport", "Teleport", "map-pin")
    addTab("Player", "Player", "user-round")
    addTab("Base", "Base", "warehouse")
    addTab("Tree", "Tree", "trees")

    window:Divider()

    addTab("Settings", "Settings", "sliders-horizontal")

    for _, tab in ipairs(orderedTabs) do
        tab:AddSearch("Search features...")
    end

    local watermark = window:Watermark({
        Title = options.WatermarkTitle or "KixHub",
        FPS = true,
        Ping = true,
    })

    return {
        Window = window,
        Tabs = tabs,
        Watermark = watermark,
    }
end

return UI
end

__modules["UI.WindUIProvider"] = function()
local Provider = {}

Provider.SourceUrl = "https://raw.githubusercontent.com/caomod2077/Windui-better/main/windui.lua"

function Provider.Load(url)
    url = url or Provider.SourceUrl

    assert(type(loadstring) == "function", "loadstring is unavailable")
    assert(type(game.HttpGet) == "function", "HTTP requests are unavailable")

    local source = game:HttpGet(url)
    assert(type(source) == "string" and #source > 0, "WindUI source is empty")

    local chunk = assert(loadstring(source, "=WindUI-Better"))
    local ok, library = pcall(chunk)
    assert(ok and type(library) == "table", "WindUI-Better failed to initialise")

    return library
end

return Provider
end

local __entry = KixRequire("Games.99Nights.entry")
local __context = {
    PlaceId = tostring(game.PlaceId),
    GameId = tostring(game.GameId),
    Channel = "development",
}
local __shutdown = __entry.Start(__context)
local __shared = (type(getgenv) == "function" and getgenv()) or _G
__shared.KixHub99NightsShutdown = __shutdown
