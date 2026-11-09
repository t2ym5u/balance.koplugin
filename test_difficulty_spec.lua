-- Difficulty guarantees of Balance (docs/dev/TESTING.md, "Difficulty
-- specs"). A level is a number of balls and of weighings; the puzzle is to
-- name the odd ball AND whether it is heavier or lighter. Each level must be
-- winnable without guessing, i.e. some weighing strategy always pins down
-- the one (ball, heavier/lighter) case within max_weighings -- and it must
-- take all of them, or the level would be easier than it says. The search
-- below plays the board's own weigh() on every remaining case, grouping the
-- balls by what is still known about them (could be heavy or light, heavy
-- only, light only, known normal), so it stays a few thousand weighings.
local DIR = debug.getinfo(1, "S").source:sub(2):match("(.*[/\\])") or "./"

package.preload["gettext"] = function()
    return setmetatable({}, { __call = function(_, s) return s end })
end
package.path = DIR .. "common/?.lua;" .. DIR .. "?.lua;" .. package.path

local Board = require("board")

-- Outcome of putting `left`/`right` on the scale if the odd ball is
-- case.ball (heavier or not), as the board's weigh() reports it.
local function outcome(board, left, right, case)
    board.won, board.lost = false, false
    board.weighings_used, board.history = 0, {}
    board.odd_ball, board.odd_heavier = case.ball, case.heavy
    board.left_pan, board.right_pan = left, right
    return board:weigh()
end

-- Can the cases still open be told apart in `w` weighings?
-- Ball classes: 1 = heavy or light, 2 = heavy only, 3 = light only,
-- 4 = known normal. A weighing is fully described (up to relabelling) by how
-- many balls of each class go on each pan, so the search runs on those counts.
local function solvable(board, cases, w, memo)
    if #cases <= 1 then return true end
    if w == 0 or #cases > 3 ^ w then return false end
    local heavy, light = {}, {}
    for _, cs in ipairs(cases) do
        if cs.heavy then heavy[cs.ball] = true else light[cs.ball] = true end
    end
    local class = { {}, {}, {}, {} }
    for b = 1, board.num_balls do
        local k = (heavy[b] and light[b]) and 1 or heavy[b] and 2 or light[b] and 3 or 4
        class[k][#class[k] + 1] = b
    end
    local key = w .. ":" .. #class[1] .. "," .. #class[2] .. "," .. #class[3] .. "," .. #class[4]
    if memo[key] ~= nil then return memo[key] end

    local result = false
    local lc, rc = {}, {}
    -- Enumerate left counts lc[k], then right counts rc[k] <= class size - lc[k].
    local function tryRight(k, nl, nr)
        if result then return end
        if k > 4 then
            if nl ~= nr or nl == 0 then return end
            local left, right = {}, {}
            for j = 1, 4 do
                for i = 1, lc[j] do left[#left + 1] = class[j][i] end
                for i = lc[j] + 1, lc[j] + rc[j] do right[#right + 1] = class[j][i] end
            end
            local parts = { L = {}, R = {}, ["="] = {} }
            for _, cs in ipairs(cases) do
                local p = parts[outcome(board, left, right, cs)]
                p[#p + 1] = cs
            end
            for _, p in pairs(parts) do
                if #p == #cases then return end   -- learns nothing
            end
            for _, p in pairs(parts) do
                if not solvable(board, p, w - 1, memo) then return end
            end
            result = true
            return
        end
        for x = 0, #class[k] - lc[k] do
            rc[k] = x
            tryRight(k + 1, nl, nr + x)
        end
    end
    local function tryLeft(k, nl)
        if result then return end
        if k > 4 then return tryRight(1, nl, 0) end
        for x = 0, #class[k] do
            lc[k] = x
            tryLeft(k + 1, nl + x)
        end
    end
    tryLeft(1, 0)
    memo[key] = result
    return result
end

local function allCases(n)
    local cases = {}
    for b = 1, n do
        cases[#cases + 1] = { ball = b, heavy = true }
        cases[#cases + 1] = { ball = b, heavy = false }
    end
    return cases
end

describe("Balance difficulty", function()

    it("offers easy and medium only, each a real preset", function()
        assert.are.same({ "easy", "medium" }, Board.PRESET_ORDER)
        for _, id in ipairs(Board.PRESET_ORDER) do assert.truthy(Board.PRESETS[id]) end
        assert.is_nil(Board.PRESETS.hard)
    end)

    it("orders its presets: more balls (more cases) for no more weighings", function()
        local prev
        for _, id in ipairs(Board.PRESET_ORDER) do
            local p = Board.PRESETS[id]
            if prev then
                assert.is_true(p.num_balls > prev.num_balls)
                assert.is_true(p.max_weighings <= prev.max_weighings)
            end
            prev = p
        end
    end)

    for _, id in ipairs({ "easy", "medium" }) do
        it(id .. " can always be won without guessing, and needs every weighing", function()
            local b = Board:new{ preset = id }
            local w = b.max_weighings
            assert.is_true(solvable(b, allCases(b.num_balls), w, {}),
                id .. ": no strategy in " .. w .. " weighings")
            assert.is_false(solvable(b, allCases(b.num_balls), w - 1, {}),
                id .. ": solvable in " .. (w - 1) .. " weighings")
        end)
    end

    it("finds the classic limit: 13 balls cannot be done in 3 weighings", function()
        -- Checks the search itself: 12 balls is the famous maximum for 3
        -- weighings when heavier/lighter must be named too (26 cases fit in
        -- 3^3 = 27 outcomes, yet the first weighing cannot split them evenly).
        local b = Board:new{ preset = "medium" }
        b.num_balls = 13
        assert.is_false(solvable(b, allCases(13), 3, {}))
    end)

    it("hides the same odd ball for the same seed, without reading the clock", function()
        local clock, time = os.clock, os.time
        local ok, err = pcall(function()
            os.clock = function() error("newGame read os.clock") end
            os.time  = function() error("newGame read os.time") end
            for _, id in ipairs(Board.PRESET_ORDER) do
                for seed = 1, 5 do
                    math.randomseed(seed)
                    local a = Board:new{ preset = id }
                    math.randomseed(seed)
                    local b = Board:new{ preset = id }
                    assert.are.equal(a.odd_ball, b.odd_ball)
                    assert.are.equal(a.odd_heavier, b.odd_heavier)
                end
            end
        end)
        os.clock, os.time = clock, time
        assert.is_true(ok, err)
    end)

    it("hides every ball, heavier and lighter, over many games", function()
        for _, id in ipairs(Board.PRESET_ORDER) do
            math.randomseed(7)
            local b, seen, count = Board:new{ preset = id }, {}, 0
            for _ = 1, 400 do
                b:newGame()
                local key = b.odd_ball .. (b.odd_heavier and "H" or "L")
                if not seen[key] then seen[key], count = true, count + 1 end
            end
            assert.are.equal(2 * b.num_balls, count)
        end
    end)
end)
