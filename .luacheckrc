std = "lua51"
max_line_length = false

-- Standard WoW addon patterns, not real issues.
ignore = {
    "431",  -- shadowing upvalue
    "432",  -- shadowing upvalue argument
}

-- Globals this addon sets
globals = {
    "EasyFindATTDB",
    "EasyFindATT",
}

-- The game, EasyFind and All The Things (read-only)
read_globals = {
    "EasyFind", "AllTheThings",
    "C_AddOns", "IsAddOnLoaded", "C_Map", "C_MountJournal", "C_SuperTrack", "C_Timer", "UiMapPoint", "WorldMapFrame",
    "CreateVector2D", "RETRIEVING_DATA", "CreateFrame", "IsAltKeyDown",
    "debugprofilestop", "debugstack", "geterrorhandler",
}

-- The tests run on the lua in PATH (5.4) and stand in for the game's globals.
files["tests"] = { std = "max", ignore = { "111", "112", "113", "121", "122", "212" } }

-- The dev probe stays local (gitignored) and never ships.
exclude_files = { "dev/**" }
