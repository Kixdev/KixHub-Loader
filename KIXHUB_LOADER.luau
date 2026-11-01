-- KIXHUB Universal Loader
-- Main entry point for game detection, payload routing, and runtime startup.

local CONFIG = {
    -- development = branch ref; production = tagged or immutable ref.
    Channel = "development",
    RequestAttempts = 3,
    RetryDelay = 1,
}

local shared = (type(getgenv) == "function" and getgenv()) or _G
local STATE_KEY = "KixHubUniversalLoader"

-- Session guard.
local previous = shared[STATE_KEY]
if type(previous) == "table" and (previous.State == "loading" or previous.State == "ready") then
    warn("[KixHub Loader] A loader or payload is already active.")
    return
end

local state = {
    State = "loading",
    StartedAt = os.clock(),
    Retire = nil,
}
shared[STATE_KEY] = state

if type(previous) == "table" and type(previous.Retire) == "function" then
    pcall(previous.Retire)
end

local function release()
    if shared[STATE_KEY] == state then
        shared[STATE_KEY] = nil
    end
end

local function fail(message)
    state.State = "failed"
    warn("[KixHub Loader] " .. tostring(message))
    release()
end

-- ============================================================================
-- GAME REGISTRY
-- ============================================================================

local Games = {
    ["79546208627805"] = {
        Name = "99 Nights in the Forest",
        GameId = "7326934954",

        -- Branch URL for active development.
        DevelopmentUrl = "PASTE_RAW_GITHACK_DEVELOPMENT_URL_HERE",

        -- Tagged or commit URL for production.
        ProductionUrl = "PASTE_RAWCDN_GITHACK_PRODUCTION_URL_HERE",
    },

    --[[ Copy for a new game.
    ["PLACE_ID_HERE"] = {
        Name = "New Game Name",
        GameId = "OPTIONAL_UNIVERSE_ID",
        DevelopmentUrl = "https://raw.githack.com/USER/REPOSITORY/main/payload.luau",
        ProductionUrl = "https://rawcdn.githack.com/USER/REPOSITORY/v1.0.0/payload.luau",
    },
    ]]
}

-- ============================================================================
-- STATUS UI
-- ============================================================================

local function createStatus(message, isError)
    local players = game:GetService("Players")
    local player = players.LocalPlayer
    if not player then return function() end end

    local parent = player:FindFirstChildOfClass("PlayerGui") or player:WaitForChild("PlayerGui", 5)
    if not parent then return function() end end

    local gui = Instance.new("ScreenGui")
    gui.Name = "KixHubLoaderStatus"
    gui.ResetOnSpawn = false
    gui.DisplayOrder = 999
    gui.Parent = parent

    local card = Instance.new("Frame")
    card.AnchorPoint = Vector2.new(0.5, 0.5)
    card.Position = UDim2.fromScale(0.5, 0.5)
    card.Size = UDim2.fromOffset(360, 120)
    card.BackgroundColor3 = Color3.fromRGB(22, 24, 32)
    card.BorderSizePixel = 0
    card.Parent = gui

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 10)
    corner.Parent = card

    local title = Instance.new("TextLabel")
    title.BackgroundTransparency = 1
    title.Position = UDim2.fromOffset(18, 14)
    title.Size = UDim2.new(1, -36, 0, 24)
    title.Font = Enum.Font.GothamBold
    title.Text = "KIXHUB"
    title.TextColor3 = Color3.fromRGB(255, 255, 255)
    title.TextSize = 17
    title.TextXAlignment = Enum.TextXAlignment.Left
    title.Parent = card

    local body = Instance.new("TextLabel")
    body.BackgroundTransparency = 1
    body.Position = UDim2.fromOffset(18, 46)
    body.Size = UDim2.new(1, -36, 0, 54)
    body.Font = Enum.Font.Gotham
    body.Text = tostring(message)
    body.TextColor3 = isError and Color3.fromRGB(255, 130, 130) or Color3.fromRGB(190, 198, 215)
    body.TextSize = 13
    body.TextWrapped = true
    body.TextXAlignment = Enum.TextXAlignment.Left
    body.TextYAlignment = Enum.TextYAlignment.Top
    body.Parent = card

    return function(nextMessage, nextIsError)
        if not gui.Parent then return end
        body.Text = tostring(nextMessage)
        body.TextColor3 = nextIsError and Color3.fromRGB(255, 130, 130) or Color3.fromRGB(190, 198, 215)
    end, function()
        if gui.Parent then gui:Destroy() end
    end
end

local updateStatus, destroyStatus = createStatus("Checking current game...")
state.Retire = destroyStatus

-- ============================================================================
-- PAYLOAD LOADING
-- ============================================================================

local function getRequestFunction()
    if type(request) == "function" then return request end
    if type(http_request) == "function" then return http_request end
    if type(syn) == "table" and type(syn.request) == "function" then return syn.request end
    return nil
end

local requestFunction = getRequestFunction()

local function download(url)
    if type(url) ~= "string" or url == "" or url:find("PASTE_", 1, true) then
        return false, "Payload URL has not been configured yet."
    end

    local lastError = "unknown download error"

    for attempt = 1, CONFIG.RequestAttempts do
        local ok, result = pcall(function()
            if requestFunction then
                local response = requestFunction({
                    Url = url,
                    Method = "GET",
                })
                local body = response and (response.Body or response.body)
                if type(body) ~= "string" or #body == 0 then
                    error("empty HTTP response")
                end
                return body
            end

            if type(game.HttpGet) ~= "function" then
                error("no supported HTTP request function")
            end

            local body = game:HttpGet(url)
            if type(body) ~= "string" or #body == 0 then
                error("empty HTTP response")
            end
            return body
        end)

        if ok and type(result) == "string" and #result > 0 then
            return true, result
        end

        lastError = tostring(result)
        if attempt < CONFIG.RequestAttempts then
            task.wait(CONFIG.RetryDelay * attempt)
        end
    end

    return false, lastError
end

local function runPayload(entry, source)
    if type(loadstring) ~= "function" then
        return false, "loadstring is not available in this executor."
    end

    local compiled, chunk, compileError = pcall(
        loadstring,
        source,
        "=KixHub/" .. tostring(entry.Name)
    )

    if not compiled or type(chunk) ~= "function" then
        return false, "payload compile failed: " .. tostring(compileError or chunk)
    end

    local ran, runtimeError = pcall(chunk)
    if not ran then
        return false, "payload runtime failed: " .. tostring(runtimeError)
    end

    return true
end

-- ============================================================================
-- DISPATCH
-- ============================================================================

local placeId = tostring(game.PlaceId)
local entry = Games[placeId]

if not entry then
    updateStatus("Game belum didukung.\nPlaceId: " .. placeId, true)
    warn("[KixHub Loader] Unsupported PlaceId: " .. placeId)
    task.delay(4, function()
        if destroyStatus then destroyStatus() end
        release()
    end)
    return
end

local url = CONFIG.Channel == "production"
    and entry.ProductionUrl
    or entry.DevelopmentUrl

updateStatus("Loading " .. entry.Name .. "...\nPlaceId: " .. placeId)

local downloaded, sourceOrError = download(url)
if not downloaded then
    updateStatus(sourceOrError, true)
    fail(sourceOrError)
    task.delay(5, function()
        if destroyStatus then destroyStatus() end
    end)
    return
end

updateStatus("Compiling " .. entry.Name .. "...")

local ran, runError = runPayload(entry, sourceOrError)
if not ran then
    updateStatus(runError, true)
    fail(runError)
    task.delay(5, function()
        if destroyStatus then destroyStatus() end
    end)
    return
end

state.State = "ready"
state.PlaceId = placeId
state.Game = entry.Name
state.Retire = nil

if destroyStatus then
    destroyStatus()
end

-- The payload may call this on shutdown.
shared.KixHubLoaderRelease = function()
    if shared[STATE_KEY] == state then
        shared[STATE_KEY] = nil
    end
end
