-- Things.lua against a fake EasyFind.API and a fake All The Things tree:
-- the decorator on EasyFind's rows, its @att scope, its own quest rows,
-- tooltips, menus and directions.
local source = debug.getinfo(1, "S").source:sub(2)
local ROOT = source:gsub("[/\\]?tests[/\\]test_things%.lua$", "")
if ROOT == "" then ROOT = "." end

local function assertEq(got, want, label)
    if got ~= want then
        error(string.format("%s: got %s, wanted %s", label or "value", tostring(got), tostring(want)), 2)
    end
end

-- ==== fakes =================================================================

local timers, printed, navigated, popouts = {}, {}, {}, {}
local captured = {}
local world = { map = 37, now = 0, gps = true, minor = 6, mapShown = false, questie = false }

-- The clock moves on by the given seconds; every timer due by then runs,
-- earliest first, including the ones those schedule.
local function FlushTimers(seconds)
    world.now = world.now + (seconds or 1)
    local guard = 0
    while guard < 10000 do
        local due, at
        for i = 1, #timers do
            if timers[i].at <= world.now and (not at or timers[i].at < at) then due, at = i, timers[i].at end
        end
        if not due then return end
        table.remove(timers, due).fn()
        guard = guard + 1
    end
end

local function FakeAPI()
    return {
        VERSION = 1, MINOR = world.minor,
        RegisterExtension = function(def) captured.extension = def; return true end,
        RegisterSearchProvider = function(def) captured.provider = def; return true end,
        RefreshSearchProvider = function() captured.refreshes = (captured.refreshes or 0) + 1 end,
        RegisterRowDecorator = function(def) captured.decorator = def end,
        RefreshRowDecorations = function() captured.decorRefreshes = (captured.decorRefreshes or 0) + 1 end,
        HasAction = function(id, name) return world.gps and id == "gps" and (name == "navigate" or name == "canNavigate") end,
        CallAction = function(id, name, dest)
            if id == "gps" and name == "navigate" then navigated[#navigated + 1] = dest; return true end
            if id == "gps" and name == "canNavigate" then return true end
        end,
    }
end

local waypoints = {}
local function FakeWaypoints()
    C_Map.CanSetUserWaypointOnMap = function() return true end
    C_Map.SetUserWaypoint = function(point) waypoints[#waypoints + 1] = point end
    UiMapPoint = { CreateFromCoordinates = function(mapID, x, y) return { mapID = mapID, x = x, y = y } end }
    WorldMapFrame = { IsShown = function() return world.mapShown end }
    C_SuperTrack = { SetSuperTrackedUserWaypoint = function(on) waypoints.tracked = on end }
end

-- A tree in ATT's shape: groups with a key, parents and children, and
-- the field caches ATT keeps for them.
local caches, handlers = {}, {}
local function CacheField(g, field, value)
    caches[field] = caches[field] or {}
    caches[field][value] = caches[field][value] or {}
    local list = caches[field][value]
    list[#list + 1] = g
end

local FIELDS = { "mountID", "speciesID", "toyID", "illusionID", "titleID", "achievementID", "decorID", "recipeID",
                 "npcID", "objectID", "mapID", "instanceID", "sourceID", "itemID", "questID" }
local function Cache(g)
    for _, f in ipairs(FIELDS) do
        if rawget(g, f) then CacheField(g, f, g[f]) end
    end
    if g.maps then for _, m in ipairs(g.maps) do CacheField(g, "mapID", m) end end
    for _, kid in ipairs(g.g or {}) do
        kid.parent = g
        Cache(kid)
    end
end

local function FakeATT()
    return {
        SearchForField = function(field, id) return caches[field] and caches[field][id] or {} end,
        GetRawFieldContainer = function(field) return caches[field] end,
        SearchForObject = function(field, id, require, allowMultiple)
            local list = caches[field] and caches[field][id] or {}
            local out = {}
            for _, g in ipairs(list) do
                if require == nil or (require == "field" and g[field] == id) or (require == "key" and g.key == field and g[field] == id) then
                    out[#out + 1] = g
                end
            end
            if allowMultiple then return out end
            return out[1]
        end,
        AddEventHandler = function(name, fn)
            handlers[name] = handlers[name] or {}
            table.insert(handlers[name], fn)
        end,
        CreateMiniListForGroup = function(_, g) popouts[#popouts + 1] = g end,
        Modules = {
            RetrievingData = { IsRetrieving = function(s) return s == "Retrieving Data" end },
            Filter = { Filters = {
                RecursiveDefaultCharacterRequirementsFilter = function(g) return not g.otherFaction end,
                RecursiveUnobtainableFilter = function(g) return not g.removed end,
            } },
        },
    }
end

local function Fire(name)
    for _, fn in ipairs(handlers[name] or {}) do fn() end
end

local tree = {}
local function BuildTree()
    tree.invincible = { key = "mountID", mountID = 72286, itemID = 50818, name = "Invincible's Reins", icon = 1001, collectible = true }
    tree.lk = { key = "npcID", npcID = 36597, name = "The Lich King", g = { tree.invincible } }
    tree.heroic = { key = "difficultyID", difficultyID = 2, name = "Heroic", g = { tree.lk } }
    -- A questline under its header, the last quest rewarding the weapon.
    tree.reward = { key = "itemID", itemID = 49623, name = "Shadowmourne" }
    tree.sacred = { key = "questID", questID = 24548, name = "The Sacred and the Corrupt", icon = 1004,
                    coords = { [118] = { { 50, 50 } } }, g = { tree.reward } }
    tree.smHeader = { key = "headerID", headerID = -10, text = "Shadowmourne", g = { tree.sacred } }
    tree.icc = { key = "instanceID", instanceID = 758, name = "Icecrown Citadel", mapID = 186, maps = { 187 },
                 coords = { [118] = { { 54, 86 } } }, g = { tree.heroic, tree.smHeader } }
    tree.dungeons = { key = "headerID", headerID = -1, text = "|cffffffffDungeons & Raids|r", g = { tree.icc } }
    tree.pet = { key = "speciesID", speciesID = 5, name = "Pocket Pet", icon = 1002, collectible = true, collected = 1 }
    tree.toy = { key = "toyID", toyID = 9, collectible = true }
    tree.bob = { key = "npcID", npcID = 100, name = "Vendor Bob", coords = { [37] = { { 40, 60 } } }, g = { tree.pet } }
    tree.done = { key = "questID", questID = 100, name = "Done Quest", saved = 1 }
    tree.unnamed = { key = "questID", questID = 101 }
    tree.hordeQuest = { key = "questID", questID = 103, name = "Horde Quest", otherFaction = true }
    tree.removedQuest = { key = "questID", questID = 104, name = "Removed Quest", removed = true }
    -- A hidden trigger outside ATT's hidden window whose name errors when read.
    tree.bonusRep = setmetatable({ key = "questID", questID = 102, isHQT = true }, { __index = function(_, k)
        if k == "name" or k == "text" then error("bad argument #2 to 'format' (string expected, got nil)") end
    end })
    tree.elwynn = { key = "mapID", mapID = 37, name = "Elwynn Forest", g = { tree.bob, tree.toy, tree.done, tree.unnamed, tree.bonusRep, tree.hordeQuest, tree.removedQuest } }
    tree.zones = { key = "headerID", headerID = -2, text = "Zones", g = { tree.elwynn } }
    tree.ach = { key = "achievementID", achievementID = 1, name = "Loremaster", collectible = false }
    tree.achievements = { key = "headerID", headerID = -3, text = "Achievements", g = { tree.ach } }
    -- A mount sold in a shop with no coordinates anywhere above it, but
    -- a provider creature that stands somewhere.
    tree.shopMount = { key = "mountID", mountID = 500, name = "Shop Mount", collectible = true, providers = { { "n", 100 } } }
    -- A quest whose giver stands somewhere, with no coordinates of its own.
    tree.escort = { key = "questID", questID = 105, name = "Escort Quest", providers = { { "n", 100 } } }
    tree.shop = { key = "headerID", headerID = -4, text = "In-Game Shop", g = { tree.shopMount, tree.escort } }
    -- An item ATT files under a category only: nothing to go to.
    tree.linen = { key = "itemID", itemID = 2589, name = "Linen Cloth" }
    tree.reagents = { key = "headerID", headerID = -30, text = "Reagent", g = { tree.linen } }
    tree.lamp = { key = "decorID", decorID = 300, name = "Lamp", icon = 1003, collectible = true, collected = 1 }
    tree.housing = { key = "headerID", headerID = -6, text = "Housing", g = { tree.lamp } }
    -- Bookkeeping quests under ATT's hidden triggers: never rows.
    tree.tracking = { key = "questID", questID = 777, name = "Tracking Quest" }
    tree.hidden = { key = "headerID", headerID = -20, text = "Hidden Quest Triggers", _hqt = true, g = { tree.tracking } }
    tree.root = { key = "ROOT", text = "All The Things", g = { tree.dungeons, tree.zones, tree.achievements, tree.shop, tree.housing, tree.hidden, tree.reagents } }
    Cache(tree.root)
end

local function Env()
    caches, handlers, timers, printed, navigated, popouts, captured = {}, {}, {}, {}, {}, {}, {}
    waypoints, world.gps, world.minor, world.mapShown, world.questie, world.map = {}, true, 6, false, false, 37
    WorldMapFrame, C_SuperTrack, UiMapPoint = nil, nil, nil
    EasyFind = { API = FakeAPI() }
    AllTheThings = FakeATT()
    C_AddOns = { IsAddOnLoaded = function(name)
        if name == "Questie" or name == "EasyFind_Questie" then return world.questie end
        return name == "AllTheThings" and AllTheThings ~= nil
    end }
    RETRIEVING_DATA = "Retrieving Data"
    -- The client's secret strings, stood in for by one word.
    issecretvalue = function(v) return v == "WITHHELD" end
    EasyFindATTDB = nil
    C_Timer = { After = function(delay, fn) timers[#timers + 1] = { at = world.now + delay, fn = fn } end }
    C_Map = {
        GetBestMapForUnit = function() return world.map end,
        GetPlayerMapPosition = function() return nil end,
        GetWorldPosFromMapPos = function() return nil end,
        GetMapInfo = function(id) return { name = "Map " .. id } end,
    }
    C_MountJournal = { GetMountInfoByID = function(id) if id == 42 then return "Invincible", 72286 end end }
    CreateVector2D = function(x, y) return { x = x, y = y } end
    CreateFrame = function() return { RegisterEvent = function() end, SetScript = function() end } end
    IsAltKeyDown = function() return world.alt end
    world.clock = nil
    debugprofilestop = function() return world.clock and world.clock() or os.clock() * 1000 end
    debugstack = function() return "" end
    geterrorhandler = function() return function(e) printed[#printed + 1] = "ERR " .. tostring(e) end end
    print = function(...) printed[#printed + 1] = table.concat({ ... }, " ") end
    BuildTree()
end

local function Load()
    Env()
    local ns = {}
    assert(loadfile(ROOT .. "/Locales/enUS.lua"))("EasyFind_ATT", ns)
    assert(loadfile(ROOT .. "/Things.lua"))("EasyFind_ATT", ns)
    Fire("OnReady")
    FlushTimers()
    return ns
end

local function LoadOnly()
    Env()
    local ns = {}
    assert(loadfile(ROOT .. "/Locales/enUS.lua"))("EasyFind_ATT", ns)
    assert(loadfile(ROOT .. "/Things.lua"))("EasyFind_ATT", ns)
    return ns
end

local MOUNT_ROW = { category = "Mount", mountID = 42, name = "Invincible" }

-- ==== tests =================================================================

local tests = {}

local function RowNamed(rows, name)
    for _, r in ipairs(rows) do
        if r.name == name then return r end
    end
    return nil
end

-- EasyFind asks for the rows (the first search); the build runs over frames.
local function QuestRows()
    captured.provider.rows()
    FlushTimers(1)
    return captured.provider.rows()
end

local function Switch(label)
    for _, o in ipairs(captured.provider.options) do
        if o.label == label then return o end
    end
    return nil
end

local function Has(list, word)
    for _, w in ipairs(list or {}) do
        if w == word then return true end
    end
    return false
end

function tests.decorator_registers_at_load_and_takes_rows_once_ready()
    LoadOnly()
    local d = captured.decorator
    assert(d, "registered at load, so the button finds @att from login")
    assertEq(d.applies(MOUNT_ROW), false, "nothing taken before ATT is ready")
    assertEq(next(d.candidates()), nil, "no candidates before ATT is ready")
    Fire("OnReady")
    assertEq(d.applies(MOUNT_ROW), true, "taken once ready")
    assert(d.candidates().spellID[72286], "its candidates are ATT's own tables")
    assert((captured.decorRefreshes or 0) >= 1, "rows asked again once ready")
end

-- Its settings page holds the switches its filter row holds, so neither
-- place has one the other lacks (2026-11-23: it had no page at all).
function tests.its_settings_page_shows_every_filter_switch()
    Load()
    local made = {}
    local function Region(kind, text)
        local r = { kind = kind, text = text }
        function r:SetPoint() end
        function r:SetText(t) self.text = t end
        made[#made + 1] = r
        return r
    end
    local page = { CreateFontString = function() return Region("header") end }
    local kit = {
        Font = function(name) return name end,
        Title = function() return Region("title") end,
        Checkbox = function(_, label) return Region("switch", label) end,
    }
    captured.extension.settings(page, kit)
    local want = {}
    for _, o in ipairs(captured.provider.options) do
        want[#want + 1] = (o.header and "header " .. o.header) or ("switch " .. o.label)
    end
    local got = {}
    for i = 2, #made do got[#got + 1] = made[i].kind .. " " .. made[i].text end
    assertEq(table.concat(got, " | "), table.concat(want, " | "), "the page lists the filter row's switches in order")
    assert(captured.extension.resetSettings, "and resets them")
end

function tests.its_button_opens_the_att_scope()
    Load()
    assertEq(captured.extension.scope, "att", "the extension's scope")
    assertEq(captured.extension.open, nil, "never ATT's own window")
    assertEq(captured.decorator.aliases[1], "att", "the decorator holds @att")
end

function tests.decorator_takes_easyfinds_rows_whose_thing_the_host_knows()
    Load()
    local d = captured.decorator
    assertEq(d.label, "All The Things", "its flyout's name")
    assertEq(d.submenu, nil, "one entry: in the menu itself, no flyout of one")
    assertEq(d.slot, nil, "no painted slot: EasyFind paints only prices")
    assertEq(d.applies(MOUNT_ROW), true, "a mount by its journal id")
    assertEq(d.applies({ category = "Mount", spellID = 72286 }), true, "a mount by its spell")
    assertEq(d.applies({ category = "Item", itemID = 50818 }), true, "the item that teaches it")
    assertEq(d.applies({ category = "Item", itemID = 49623 }), true, "an item a quest rewards")
    assertEq(d.applies({ category = "Pet", speciesID = 5 }), true, "a pet")
    assertEq(d.applies({ category = "Housing", housingRecordID = 300 }), true, "decor by its catalog record")
    assertEq(d.applies({ category = "Housing", housingRecordID = 300, isRoom = true }), false, "a room is no decor")
    assertEq(d.applies({ category = "Pet", speciesID = 999 }), false, "unknown to the host")
    assertEq(d.applies({ category = "Bag", itemID = 1 }), false, "a category it does not read")
end

function tests.subtext_names_att_and_a_source_a_player_can_go_to()
    Load()
    local d = captured.decorator
    assertEq(d.subtext(MOUNT_ROW), "ATT: from The Lich King, Icecrown Citadel", "the boss, then its instance")
    assertEq(d.subtext({ category = "Item", itemID = 50818 }), "ATT: from The Lich King, Icecrown Citadel", "the item")
    assertEq(d.subtext({ category = "Pet", speciesID = 5 }), "ATT: from Vendor Bob, Elwynn Forest", "a vendor in its zone")
    assertEq(d.applies({ category = "Item", itemID = 2589 }), true, "an item ATT knows")
    assertEq(d.subtext({ category = "Item", itemID = 2589 }), nil, "under a category only: no subtext")
end

-- A name the client withholds (a secret string, Forever 2026-11-09) is
-- left unread: the line goes on with the names it can read.
function tests.a_name_the_client_withholds_is_left_unread()
    Load()
    tree.lk.name = "WITHHELD"
    local d = captured.decorator
    assertEq(d.subtext(MOUNT_ROW), "ATT: from Icecrown Citadel", "the boss unread, the instance named")
    tree.icc.name = "WITHHELD"
    assertEq(d.subtext(MOUNT_ROW), nil, "nothing readable: no line, no error")
end

function tests.keep_drops_only_what_is_collected()
    Load()
    local d = captured.decorator
    assertEq(d.keep(MOUNT_ROW), true, "not collected")
    assertEq(d.keep({ category = "Pet", speciesID = 5 }), false, "collected")
    assertEq(d.keep({ category = "Achievement", achievementID = 1 }), true, "not counted: kept")
end

function tests.tooltip_heads_its_lines_and_skips_a_state_it_does_not_count()
    Load()
    local d = captured.decorator
    local lines = {}
    local tt = { AddLine = function(_, s) lines[#lines + 1] = s end }
    d.tooltip(MOUNT_ROW, nil, tt)
    assertEq(table.concat(lines, " | "),
        "  | All The Things | Not collected | Sources | Dungeons & Raids > Icecrown Citadel > The Lich King", "mount")
    lines = {}
    d.tooltip({ category = "Achievement", achievementID = 1 }, nil, tt)
    assertEq(table.concat(lines, " | "), "  | All The Things | Sources | Achievements", "not counted: no state")
end

function tests.no_tooltip_section_where_att_put_its_own_lines()
    Load()
    local lines = {}
    local tt = { ATT_AttachComplete = true, AddLine = function(_, s) lines[#lines + 1] = s end }
    captured.decorator.tooltip(MOUNT_ROW, nil, tt)
    assertEq(#lines, 0, "ATT's own lines stand alone")
    tt.ATT_AttachComplete = false
    captured.decorator.tooltip(MOUNT_ROW, nil, tt)
    assertEq(#lines, 0, "nor while ATT is still filling them")
end

function tests.menu_is_the_host_window_only()
    Load()
    local menu = captured.decorator.menu(MOUNT_ROW)
    assertEq(#menu, 1, "no directions entries: a row with a place has its GPS button")
    assertEq(menu[1].label, "Open in All The Things", "open")
    assertEq(menu[1].closes, true, "the host's window")
    menu[1].onClick()
    assertEq(popouts[1], tree.invincible, "the host's window on the thing")
    assertEq(#navigated, 0, "no route")
end

function tests.a_quest_with_no_place_routes_to_its_giver()
    Load()
    local P = captured.provider
    P.select(RowNamed(QuestRows(), "Escort Quest"))
    assertEq(navigated[1].mapID, 37, "Vendor Bob's map")
    assertEq(navigated[1].step, "Travel to Vendor Bob, Elwynn Forest", "step")
end

-- The giver of a quest still to take: the route's end wears the game's
-- quest-offer "!" in the GPS; one already taken or done does not.
function tests.a_quest_still_to_take_ends_on_the_quest_offer_mark()
    local onQuest, done = false, false
    C_QuestLog = { IsOnQuest = function() return onQuest end, IsQuestFlaggedCompleted = function() return done end }
    Load()
    local P = captured.provider
    P.select(RowNamed(QuestRows(), "Escort Quest"))
    assertEq(navigated[1].questMark, "offer")
    onQuest = true
    P.select(RowNamed(QuestRows(), "Escort Quest"))
    assertEq(navigated[2].questMark, nil, "taken: its giver is no offer")
    onQuest, done = false, true
    P.select(RowNamed(QuestRows(), "Escort Quest"))
    assertEq(navigated[3].questMark, nil, "done")
    C_QuestLog = nil
end

function tests.quests_easyfind_does_not_list_are_rows_of_its_own()
    Load()
    local P = captured.provider
    assert(P, "a quest provider")
    assertEq(P.aliases, nil, "no scope of its own: @att is the decorator's")
    assertEq(P.lowResults, true, "found by plain search, not only through @att")
    local rows = QuestRows()
    local sacred = RowNamed(rows, "The Sacred and the Corrupt")
    assert(sacred, "the quest is a row")
    assertEq(sacred.searchCommandDesc, "Quest: Icecrown Citadel", "kind and zone, as EasyFind's rows read")
    assert(Has(sacred.keywords, "shadowmourne"), "its questline's header finds it")
    assertEq(sacred.nameLower, "the sacred and the corrupt", "lowercased here, so EasyFind allocates nothing for it")
    assert(sacred.keywordsLower == sacred.keywords, "its words already lowercase, shared")
    assertEq(RowNamed(rows, "Done Quest"), nil, "Hide completed is on by default")
    assertEq(sacred.questId, 24548, "Questie's field, where EasyFind sees both rows of one quest")
    assertEq(RowNamed(rows, "Horde Quest"), nil, "another faction's quest is left out")
    assertEq(RowNamed(rows, "Removed Quest"), nil, "what ATT's settings count as removed is left out")
    assertEq(RowNamed(rows, "Tracking Quest"), nil, "hidden triggers are no rows")
end

function tests.a_flagged_hidden_trigger_is_skipped_before_its_name_is_read()
    Load()
    QuestRows()
    for _, line in ipairs(printed) do
        assert(not line:find("^ERR"), "no error reported: " .. line)
    end
    for _, row in ipairs(captured.provider.rows()) do
        assert(row.attQuestID ~= 102, "no row for it")
    end
end

function tests.an_unnamed_quest_arrives_on_a_later_pass()
    Load()
    assertEq(RowNamed(QuestRows(), "Late Quest"), nil, "no name yet")
    tree.unnamed.name = "Late Quest"
    FlushTimers(3)
    assert(RowNamed(captured.provider.rows(), "Late Quest"), "named on the retry")
end

-- A refresh has EasyFind index every quest row again (22,000 on retail):
-- the rows reach the search once, when the passes end.
function tests.the_quests_reach_the_search_once_when_the_passes_end()
    Load()
    local later = { key = "questID", questID = 106, parent = tree.elwynn }
    CacheField(later, "questID", 106)
    local before = captured.refreshes or 0
    QuestRows()
    assertEq((captured.refreshes or 0) - before, 0, "two quests unnamed after the first pass: no refresh yet")
    for _ = 1, 2 do FlushTimers(2) end
    assertEq((captured.refreshes or 0) - before, 0, "nothing named yet: no refresh")
    tree.unnamed.name = "Late Quest"
    FlushTimers(2)
    assertEq((captured.refreshes or 0) - before, 0, "one named, one still pending: the passes go on")
    later.name = "Later Quest"
    FlushTimers(2)
    assertEq((captured.refreshes or 0) - before, 1, "both named: one refresh as the passes end")
    assert(RowNamed(captured.provider.rows(), "Later Quest"), "the last-named quest is a row")
    for _ = 1, 3 do FlushTimers(2) end
    assertEq((captured.refreshes or 0) - before, 1, "no pass runs after the last name")
end

-- Names that never come end the passes too: the rows reach the search then.
function tests.quests_the_client_never_names_still_let_the_rest_reach_the_search()
    Load()
    local before = captured.refreshes or 0
    QuestRows()
    for _ = 1, 5 do FlushTimers(2) end
    assertEq((captured.refreshes or 0) - before, 0, "passes left: no refresh")
    FlushTimers(2)
    assertEq((captured.refreshes or 0) - before, 1, "the last pass over: one refresh")
    assert(RowNamed(captured.provider.rows(), "The Sacred and the Corrupt"), "the named quests are rows")
end

-- With every name at hand the first pass is the last: the rows reach the
-- search at once.
function tests.all_quests_named_reach_the_search_after_the_first_pass()
    Load()
    tree.unnamed.name = "Named Quest"
    local before = captured.refreshes or 0
    QuestRows()
    assertEq((captured.refreshes or 0) - before, 1, "one refresh, no passes to wait for")
end

-- A later pass over the unnamed quests reads on the first pass's budget,
-- not all in one frame.
function tests.a_later_pass_keeps_to_the_frame_budget()
    Load()
    CacheField({ key = "questID", questID = 106, parent = tree.elwynn }, "questID", 106)
    QuestRows()
    local clock = 0
    world.clock = function() clock = clock + 5; return clock end
    local frames, After = 0, C_Timer.After
    C_Timer.After = function(delay, fn)
        if delay == 0 then frames = frames + 1 end
        return After(delay, fn)
    end
    FlushTimers(2)
    assertEq(frames, 1, "two unnamed quests over budget: the pass spills into a second frame")
end

function tests.a_quest_click_routes_to_it_and_alt_opens_the_host_window()
    Load()
    local P = captured.provider
    local sacred = RowNamed(QuestRows(), "The Sacred and the Corrupt")
    P.select(sacred)
    assertEq(navigated[1].mapID, 118, "the quest's map")
    assertEq(navigated[1].x, 0.5, "its spot")
    assertEq(navigated[1].icon, 1004, "the quest's icon at the route's end")
    world.alt = true
    P.select(sacred)
    world.alt = false
    assertEq(popouts[1], tree.sacred, "ATT's window on the quest")
    assertEq(#navigated, 1, "no second route")
end

function tests.a_quest_tooltip_says_where_whether_done_and_its_path()
    Load()
    local P = captured.provider
    QuestRows()
    local lines = {}
    local tt = { SetText = function(_, s) lines[#lines + 1] = s end, AddLine = function(_, s) lines[#lines + 1] = s end }
    assertEq(P.tooltip(RowNamed(P.rows(), "The Sacred and the Corrupt"), tt), true, "shown")
    assertEq(table.concat(lines, " | "),
        "The Sacred and the Corrupt | Quest: Icecrown Citadel | Not completed |   | Sources | Dungeons & Raids > Icecrown Citadel > Shadowmourne",
        "tooltip")
end

function tests.its_own_rows_are_in_its_scope_without_a_second_tooltip_or_menu()
    Load()
    local d = captured.decorator
    local own = RowNamed(QuestRows(), "The Sacred and the Corrupt")
    assert(d.candidates().attQuestID[24548], "named for the scope")
    assertEq(d.applies(own), true, "in @att")
    assertEq(d.subtext(own), nil, "no second subtext")
    assertEq(d.menu(own), nil, "no second menu")
    local lines = {}
    d.tooltip(own, nil, { AddLine = function(_, s) lines[#lines + 1] = s end })
    assertEq(#lines, 0, "no second tooltip section")
end

-- Addons load in name order: one checked at load must be listed to load first.
function tests.every_addon_checked_at_load_loads_first()
    local toc = assert(io.open(ROOT .. "/EasyFind_ATT.toc")):read("a")
    local deps = {}
    for line in toc:gmatch("[^\r\n]+") do
        local list = line:match("^## OptionalDeps:%s*(.+)") or line:match("^## Dependencies:%s*(.+)")
        for name in (list or ""):gmatch("[^,%s]+") do deps[name] = true end
    end
    local src = assert(io.open(ROOT .. "/Things.lua")):read("a")
    local n = 0
    for name in src:gmatch('IsAddOnLoaded%("([^"]+)"%)') do
        n = n + 1
        assert(deps[name], name .. " is checked at load but not in the toc's OptionalDeps")
    end
    assert(n >= 3, "the checks were found")
end

function tests.with_questie_its_quests_go_onto_questies_rows()
    Env()
    world.questie = true
    local ns = {}
    assert(loadfile(ROOT .. "/Locales/enUS.lua"))("EasyFind_ATT", ns)
    assert(loadfile(ROOT .. "/Things.lua"))("EasyFind_ATT", ns)
    Fire("OnReady")
    FlushTimers(1)
    assert(captured.provider, "its filter row stands, for the info switches")
    captured.provider.rows()
    FlushTimers(1)
    assertEq(#captured.provider.rows(), 0, "no quest rows of its own beside Questie's")
    assertEq(Switch("Hide completed"), nil, "no switches for quest rows it does not list")
    local d = captured.decorator
    local questieRow = { questId = 24548, name = "The Sacred and the Corrupt", category = "questie" }
    assert(d.candidates().questId[24548], "Questie's rows named by quest id")
    assertEq(d.applies(questieRow), true, "Questie's row taken")
    assertEq(d.subtext(questieRow), nil, "Questie's subtext stands")
    local lines = {}
    d.tooltip(questieRow, nil, { AddLine = function(_, s) lines[#lines + 1] = s end })
    assertEq(lines[2], "All The Things", "its section")
    assertEq(lines[3], "Not completed", "whether done")
    Switch("Quests").set(false)
    assertEq(d.applies(questieRow), false, "the Quests switch takes its info off Questie's rows")
end

function tests.browse_lists_what_is_left_on_the_map_here()
    Load()
    QuestRows()
    local d = captured.decorator
    world.map = 37
    assertEq(d.browse({ category = "Toy", toyItemID = 9 }), true, "a toy still to get in Elwynn")
    assertEq(d.browse({ category = "Pet", speciesID = 5 }), false, "a pet already had")
    assertEq(d.browse(MOUNT_ROW), false, "a mount from elsewhere")
    assertEq(d.browse({ attQuestID = 100, questId = 100, name = "Done Quest" }), false, "a done quest")
    world.map = 186
    assertEq(d.browse(MOUNT_ROW), true, "the mount in its instance")
    assertEq(d.browse(RowNamed(captured.provider.rows(), "The Sacred and the Corrupt")), true, "the quest there")
end

function tests.its_own_switches_filter_its_quest_rows()
    Load()
    local P = captured.provider
    QuestRows()
    local before = captured.refreshes or 0
    Switch("Hide completed").set(false)
    assertEq(captured.refreshes, before + 1, "a switch hands the rows over again")
    assertEq(EasyFindATTDB.hideCompleted, false, "off is saved")
    assertEq(EasyFindATTDB.dbVersion, 1, "versioned")
    local rows = P.rows()
    assertEq(RowNamed(rows, "Done Quest").searchCommandDesc, "Quest: Elwynn Forest", "done quests back, the row unchanged")
    Switch("Near me").set(true)
    world.map = 37
    rows = P.rows()
    assert(RowNamed(rows, "Done Quest"), "Elwynn's quest near me")
    assertEq(RowNamed(rows, "The Sacred and the Corrupt"), nil, "Icecrown's not")
end

function tests.its_switches_turn_its_info_off_and_never_easyfinds_rows()
    Load()
    local d = captured.decorator
    assert(Switch("Mounts") and Switch("Items") and Switch("Quests"), "a switch per kind")
    assertEq(Switch("Pets"), nil, "no switch for a kind this client has no rows of")
    local refreshes = captured.refreshes or 0
    local repaints = captured.decorRefreshes or 0
    Switch("Mounts").set(false)
    assertEq(d.applies(MOUNT_ROW), false, "no info on mount rows")
    assertEq(d.applies({ category = "Item", itemID = 50818 }), true, "items keep it")
    assertEq(captured.refreshes or 0, refreshes, "no row is handed over or taken away")
    assert(captured.decorRefreshes > repaints, "the shown rows repaint")
    assertEq(EasyFindATTDB.infoOff.mounts, true, "saved")
    Switch("Mounts").set(true)
    assertEq(d.applies(MOUNT_ROW), true, "back on")
end

function tests.without_questie_the_quests_switch_hides_its_quest_rows()
    Load()
    assert(#QuestRows() > 0, "its quest rows")
    Switch("Quests").set(false)
    assertEq(#captured.provider.rows(), 0, "gone with the switch")
    Switch("Quests").set(true)
    assert(#captured.provider.rows() > 0, "back")
end

function tests.no_quest_is_read_until_the_search_asks()
    local ns = Load()
    FlushTimers(5)
    assertEq(ns.S.built, false, "nothing built at load")
    assertEq(#captured.provider.rows(), 0, "the first ask starts the build")
    FlushTimers(1)
    assertEq(ns.S.built, false, "the first pass over, a name still to come: not handed over yet")
    assertEq(captured.refreshes, nil, "EasyFind not told before the passes end")
    for _ = 1, 6 do FlushTimers(2) end
    assertEq(ns.S.built, true, "built once the passes end")
    assertEq(captured.refreshes, 1, "EasyFind told once the rows are in")
end

function tests.collection_changes_repaint_without_reloading_the_quests()
    Load()
    QuestRows()
    local refreshes = captured.refreshes
    local d = captured.decorator
    local before = captured.decorRefreshes or 0
    assertEq(d.keep(MOUNT_ROW), true, "not collected yet")
    tree.invincible.collected = 1
    Fire("OnThingCollected")
    FlushTimers(1)
    assert(captured.decorRefreshes > before, "repainted")
    assertEq(d.keep(MOUNT_ROW), false, "collected now")
    assertEq(captured.refreshes, refreshes, "the quest rows are not handed over again")
end

function tests.without_the_host_addon_nothing_registers_or_speaks()
    Env()
    AllTheThings = nil
    local ns = {}
    assert(loadfile(ROOT .. "/Locales/enUS.lua"))("EasyFind_ATT", ns)
    assert(loadfile(ROOT .. "/Things.lua"))("EasyFind_ATT", ns)
    assertEq(captured.extension, nil, "no extension")
    assertEq(captured.decorator, nil, "no decorator")
    assertEq(#printed, 0, "nothing said")
end

function tests.an_older_easyfind_gets_one_line_and_nothing_registered()
    Env()
    world.minor = 5
    EasyFind = { API = FakeAPI() }
    local ns = {}
    assert(loadfile(ROOT .. "/Locales/enUS.lua"))("EasyFind_ATT", ns)
    assert(loadfile(ROOT .. "/Things.lua"))("EasyFind_ATT", ns)
    assertEq(captured.extension, nil, "no extension")
    assert(printed[1] and printed[1]:find("newer EasyFind", 1, true), "said so in chat")
end

function tests.without_the_gps_a_waypoint_waits_for_the_world_map_to_close()
    Load()
    local P = captured.provider
    local sacred = RowNamed(QuestRows(), "The Sacred and the Corrupt")
    world.gps = false
    FakeWaypoints()
    world.mapShown = true
    P.select(sacred)
    P.select(sacred)
    FlushTimers(1)
    assertEq(#waypoints, 0, "nothing under the open map")
    world.mapShown = false
    FlushTimers(1)
    assertEq(#waypoints, 1, "one waypoint once it closed")
    assertEq(waypoints[1].mapID, 118, "at the quest")
    assertEq(waypoints.tracked, true, "tracked")
    C_SuperTrack = nil
    P.select(sacred)
    assertEq(#waypoints, 2, "a client without super tracking still gets the waypoint")
end

function tests.missing_host_functions_add_nothing()
    LoadOnly()
    AllTheThings.SearchForObject = nil
    Fire("OnReady")
    assertEq(captured.decorator.applies(MOUNT_ROW), false, "takes nothing")
    assertEq(#captured.provider.rows(), 0, "no quest rows")
    assert(printed[1] and printed[1]:find("nothing is added", 1, true), "said so in chat")
end

return tests
