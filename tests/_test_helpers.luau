-- tests/_test_helpers.luau
-- Minimal describe/it wrapper around Luau's built-in assert.

local M = {}

local indent = ""
local failures = 0
local total = 0

function M.describe(name, fn)
    print(indent .. "▸ " .. name)
    indent = indent .. "  "
    fn()
    indent = indent:sub(1, -3)
end

function M.it(name, fn)
    total += 1
    local ok, err = pcall(fn)
    if ok then
        print(indent .. "✓ " .. name)
    else
        failures += 1
        print(indent .. "✗ " .. name .. " — " .. tostring(err))
    end
end

function M.assertEq(actual, expected, msg)
    if actual ~= expected then
        error((msg or "") .. " expected " .. tostring(expected) .. ", got " .. tostring(actual), 2)
    end
end

function M.assertDeepEq(actual, expected, msg)
    local function deepEq(a, b)
        if type(a) ~= type(b) then return false end
        if type(a) ~= "table" then return a == b end
        for k, v in a do
            if not deepEq(v, b[k]) then return false end
        end
        for k, v in b do
            if not deepEq(v, a[k]) then return false end
        end
        return true
    end
    if not deepEq(actual, expected) then
        error((msg or "") .. " deep mismatch", 2)
    end
end

function M.summary()
    print(string.format("\n%d/%d passed (%d failed)", total - failures, total, failures))
    if failures > 0 then
        error("test failures", 0)
    end
end

return M
