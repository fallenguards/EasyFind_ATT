-- Runs every tests/test_*.lua. From the addon's folder: lua tests/Run.lua
-- A test's fake environment replaces the global print: ours is kept.
local print = print
local source = debug.getinfo(1, "S").source:sub(2)
local DIR = source:gsub("[/\\]Run%.lua$", "")
package.path = DIR .. "/?.lua;" .. package.path

local files = {}
local handle = io.popen(string.format([[ls "%s"/test_*.lua 2>/dev/null]], DIR:gsub("\\", "/")))
if handle then
    for line in handle:lines() do files[#files + 1] = line end
    handle:close()
end
table.sort(files)

local pass, fail = 0, 0
for _, file in ipairs(files) do
    local chunk, err = loadfile(file)
    local tests = chunk and chunk()
    if not tests then
        print("LOAD ERROR " .. file .. ": " .. tostring(err))
        fail = fail + 1
    else
        local names = {}
        for name in pairs(tests) do names[#names + 1] = name end
        table.sort(names)
        for _, name in ipairs(names) do
            local ok, e = xpcall(tests[name], debug.traceback)
            if ok then
                pass = pass + 1
            else
                fail = fail + 1
                print("FAIL " .. name .. "\n  " .. tostring(e))
            end
        end
    end
end
print(string.format("%d passed, %d failed", pass, fail))
os.exit(fail == 0 and 0 or 1)
