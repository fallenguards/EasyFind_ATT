-- Loads the addon's toc files against a stubbed game, a recording EasyFind.API and a small stand-in
-- All The Things, then checks what it registered: the extension and the decorator on EasyFind's rows,
-- and what a row says and does.
-- Usage: lua smoke_test.lua <addon dir> <toc> <addon name> [noapi|oldapi|noatt|notready]
-- noapi: no EasyFind; oldapi: EasyFind before API MINOR 6; noatt: All The Things not installed (the
-- extension loads beside it and must say nothing); notready: All The Things without the functions it reads.
-- luacheck: std lua54
-- luacheck: ignore 111 112 113 121 122 212
local dir, tocName, addon, mode = arg[1], arg[2], arg[3], arg[4] or "normal"

local Stub
local stubMeta = {}
stubMeta.__index = function(t, k)
    if k == "GetName" then return function() return nil end end
    if k == "GetWidth" or k == "GetHeight" or k == "GetScale" or k == "GetStringWidth" then
        return function() return 1 end
    end
    if k == "IsShown" or k == "IsVisible" or k == "GetChecked" or k == "IsEventRegistered" then
        return function() return false end
    end
    local v = Stub()
    rawset(t, k, v)
    return v
end
stubMeta.__call = function() return Stub() end
stubMeta.__concat = function(a, b) return tostring(type(a) == "table" and "" or a) .. tostring(type(b) == "table" and "" or b) end
for _, op in ipairs({ "__add", "__sub", "__mul", "__div", "__unm", "__mod", "__pow" }) do stubMeta[op] = function() return 0 end end
stubMeta.__lt = function() return false end
stubMeta.__le = function() return false end
stubMeta.__len = function() return 0 end
function Stub() return setmetatable({}, stubMeta) end

local frames = {}
local function NewFrame()
    local f = Stub()
    local scripts, events = {}, {}
    rawset(f, "SetScript", function(self, which, fn) scripts[which] = fn end)
    rawset(f, "HookScript", function(self, which, fn) scripts[which] = scripts[which] or fn end)
    rawset(f, "RegisterEvent", function(self, e) events[e] = true end)
    rawset(f, "UnregisterEvent", function(self, e) events[e] = nil end)
    rawset(f, "IsEventRegistered", function(self, e) return events[e] == true end)
    f.scripts, f.events = scripts, events
    frames[#frames + 1] = f
    return f
end

local toc = assert(io.open(dir .. "/" .. tocName)):read("a")
-- Saved variables start empty, as on a first login.
local saved = {}
for list in toc:gmatch("## SavedVariables[%w]*:%s*([^\r\n]+)") do
    for name in list:gmatch("[%w_]+") do saved[name] = true end
end

-- The game's own strings (MOUNTS and the like) are absent here, so the addon's English fallbacks show.
local env = setmetatable({}, { __index = function(t, k)
    local v = rawget(_G, k)
    if v ~= nil or saved[k] or k:match("^[A-Z][A-Z0-9_]+$") then return v end
    v = Stub()
    rawset(t, k, v)
    return v
end })
_G.CreateFrame = NewFrame
_G.GetLocale = function() return "enUS" end
_G.IsShiftKeyDown = function() return false end
_G.IsAltKeyDown = function() return false end
_G.debugprofilestop = function() return os.clock() * 1000 end
_G.C_Timer = { After = function(_, fn) fn() end }
_G.C_AddOns = { IsAddOnLoaded = function(name) return name == "AllTheThings" and mode ~= "noatt" end }
_G.C_Map = {
    GetBestMapForUnit = function() return 37 end,
    GetPlayerMapPosition = function() return nil end,
}

local printed = {}
_G.print = function(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[i] = tostring(select(i, ...)) end
    printed[#printed + 1] = table.concat(parts, " ")
end
local function Say(s) io.stdout:write(s, "\n") end

-- EasyFind.API as an extension sees it, every registration kept.
local registered = { extensions = {}, providers = {}, decorators = {} }
local navigated = {}
if mode ~= "noapi" then
    local API = { VERSION = 1, MINOR = mode == "oldapi" and 5 or 6 }
    function API.RefreshSearchProvider() end
    function API.RegisterExtension(def) registered.extensions[def.id] = def return true end
    function API.RegisterSearchProvider(def) registered.providers[def.key] = def return true end
    function API.RegisterRowDecorator(def) registered.decorators[def.id] = def return true end
    function API.RefreshRowDecorations() end
    function API.HasAction(id, name) return id == "gps" and name == "navigate" end
    function API.CallAction(id, name, dest) if id == "gps" and name == "navigate" then navigated[#navigated + 1] = dest end end
    _G.EasyFind = { API = API }
end

-- A stand-in All The Things: one mount dropped by a boss in an instance with coordinates, its field
-- caches, and its ready signal.
local handlers = {}
local mount = { key = "mountID", mountID = 72286, name = "Invincible's Reins", icon = 1001, collectible = true }
local boss = { key = "npcID", npcID = 36597, name = "The Lich King", g = { mount } }
local icc = { key = "instanceID", instanceID = 758, name = "Icecrown Citadel", coords = { [118] = { { 54, 86 } } }, g = { boss } }
mount.parent, boss.parent, icc.parent = boss, icc, { key = "ROOT" }
local cache = { mountID = { [72286] = { mount } }, npcID = { [36597] = { boss } }, instanceID = { [758] = { icc } } }
local att = {
    SearchForField = function(field, id) return cache[field] and cache[field][id] or {} end,
    GetRawField = function(field, id) return cache[field] and cache[field][id] end,
    GetRawFieldContainer = function(field) return cache[field] end,
    SearchForObject = function(field, id) local list = cache[field] and cache[field][id] return list and list[1] end,
    AddEventHandler = function(name, fn) handlers[name] = handlers[name] or {} table.insert(handlers[name], fn) end,
}
if mode == "notready" then att.SearchForObject = nil end
if mode ~= "noatt" then _G.AllTheThings = att end

local ns = {}
local count = 0
for line in toc:gmatch("[^\r\n]+") do
    if line:match("%.lua") and not line:match("^#") then
        local file = line:match("^(%S+)")
        local path = dir .. "/" .. file:gsub("\\", "/")
        local chunk, err = loadfile(path, "t", env)
        if not chunk then Say("LOAD " .. err) os.exit(1) end
        local ok, runErr = pcall(chunk, addon, ns)
        if not ok then Say("RUN " .. file .. ": " .. tostring(runErr)) os.exit(1) end
        count = count + 1
    end
end
Say("loaded " .. count .. " files (" .. mode .. ")")

local failed = false
local function Check(ok, what)
    Say((ok and "PASS " or "FAIL ") .. what)
    if not ok then failed = true end
end

local function Fire(name)
    for _, fn in ipairs(handlers[name] or {}) do
        local ok, err = pcall(fn)
        if not ok then Check(false, name .. ": " .. tostring(err)) end
    end
end

local ext, P = registered.extensions.att, registered.providers.attquests
if mode == "noapi" or mode == "oldapi" or mode == "noatt" then
    Check(ext == nil and P == nil and next(registered.decorators) == nil, "nothing registered (" .. mode .. ")")
    if mode == "noatt" or mode == "noapi" then Check(printed[1] == nil, "nothing said") end
    if mode == "oldapi" then
        Check(printed[1] ~= nil and printed[1]:find("newer EasyFind", 1, true) ~= nil, "says EasyFind needs an update")
    end
    os.exit(failed and 1 or 0)
end

Check(ext ~= nil and type(ext.name) == "string" and ext.icon ~= nil and ext.open == nil and ext.scope == "att",
      "the extension, its button on the @att scope")
Check(P ~= nil and P.extension == "att" and P.aliases == nil, "quest rows of its own, without a scope of their own")
local early = registered.decorators.att
Check(early ~= nil and early.aliases and early.aliases[1] == "att", "the decorator holds @att from load")
local journalRow = { category = "Mount", spellID = 72286, name = "Invincible" }
Check(early and early.applies(journalRow) == false, "and takes nothing before All The Things is ready")

Fire("OnReady")
if mode == "notready" then
    Check(printed[1] ~= nil and printed[1]:find("nothing is added", 1, true) ~= nil, "says it adds nothing")
    Check(early and early.applies(journalRow) == false, "takes nothing")
    os.exit(failed and 1 or 0)
end

local D = registered.decorators.att
Check(D ~= nil and D.slot == nil and D.text == nil, "the decorator paints no slot of its own")
Check(D and D.submenu == nil and D.label == "All The Things", "one entry, in the menu itself")
Check(D and type(D.applies) == "function" and type(D.subtext) == "function" and type(D.tooltip) == "function"
      and type(D.menu) == "function", "the decorator's hooks")
Check(D and D.applies(journalRow) == true and D.applies({ category = "Mount", spellID = 1 }) == false, "it takes the mount row All The Things knows")
Check(D and D.subtext(journalRow) == "ATT: from The Lich King, Icecrown Citadel", "and adds its source, named as its own")
local menu = D and D.menu(journalRow)
Check(menu == nil or (#menu == 1 and menu[1].label == "Open in All The Things"), "the menu: its window only, no directions")

Fire("OnThingCollected")
for i = 1, #frames do
    local f = frames[i]
    if f.scripts.OnEvent then
        for _, e in ipairs({ "PLAYER_LOGIN" }) do
            local okEvent, err = pcall(f.scripts.OnEvent, f, e)
            if not okEvent then Check(false, "event " .. e .. ": " .. tostring(err)) end
        end
    end
end
os.exit(failed and 1 or 0)
