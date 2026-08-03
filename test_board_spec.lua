local DIR = debug.getinfo(1, "S").source:sub(2):match("(.*[/\\])") or "./"

package.preload["gettext"] = function()
    return setmetatable({}, { __call = function(_, s) return s end })
end
package.path = DIR .. "common/?.lua;" .. DIR .. "?.lua;" .. package.path

describe("BalanceBoard", function()
    local Board

    setup(function()
        Board = require("board")
    end)

    describe("new / newGame", function()
        it("applies the easy preset by default", function()
            local b = Board:new()
            assert.are.equal(8, b.num_balls)
            assert.are.equal(3, b.max_weighings)
        end)

        it("picks an odd ball within range", function()
            math.randomseed(42)
            local b = Board:new()
            assert.is_true(b.odd_ball >= 1 and b.odd_ball <= b.num_balls)
        end)

        it("switches preset via newGame", function()
            local b = Board:new()
            b:newGame("medium")
            assert.are.equal(12, b.num_balls)
        end)
    end)

    describe("cycleBall", function()
        it("cycles a ball through none -> left -> right -> none", function()
            local b = Board:new()
            assert.are.equal(0, b:getBallState(1))
            b:cycleBall(1)
            assert.are.equal(1, b:getBallState(1))
            b:cycleBall(1)
            assert.are.equal(2, b:getBallState(1))
            b:cycleBall(1)
            assert.are.equal(0, b:getBallState(1))
        end)
    end)

    describe("weigh", function()
        it("returns nil when both pans are empty", function()
            local b = Board:new()
            assert.is_nil(b:weigh())
        end)

        it("reports the odd (heavier) ball tipping its pan down", function()
            local b = Board:new()
            b.odd_ball = 1
            b.odd_heavier = true
            b:cycleBall(1)              -- ball 1 -> left
            b:cycleBall(2); b:cycleBall(2)  -- ball 2 -> left -> right
            assert.are.equal("L", b:weigh())
            assert.are.equal(1, b.weighings_used)
        end)

        it("reports balance when neither pan holds the odd ball", function()
            local b = Board:new()
            b.odd_ball = 5
            b:cycleBall(1)
            b:cycleBall(2); b:cycleBall(2)  -- ball 2 -> right
            assert.are.equal("=", b:weigh())
        end)

        it("returns nil once weighings are exhausted", function()
            local b = Board:new()
            for _ = 1, b.max_weighings do
                b:cycleBall(1)
                b:cycleBall(2); b:cycleBall(2)
                b:weigh()
                b:clearPans()
            end
            assert.is_true(b:weighingsExhausted())
            assert.is_nil(b:weigh())
        end)
    end)

    describe("makeGuess", function()
        it("wins when guessing the correct ball and direction", function()
            local b = Board:new()
            b.odd_ball = 3
            b.odd_heavier = true
            assert.is_true(b:makeGuess(3, true))
            assert.is_true(b.won)
            assert.is_false(b.lost)
        end)

        it("loses when guessing the wrong ball", function()
            local b = Board:new()
            b.odd_ball = 3
            b.odd_heavier = true
            assert.is_false(b:makeGuess(4, true))
            assert.is_true(b.lost)
            assert.is_false(b.won)
        end)
    end)

    describe("serialize / load", function()
        it("round-trips odd ball, history and guess", function()
            local b = Board:new()
            b.odd_ball, b.odd_heavier = 2, false
            b:cycleBall(1)
            b:weigh()
            b:makeGuess(2, false)
            local data = b:serialize()

            local b2 = Board:new()
            assert.is_true(b2:load(data))
            assert.are.equal(2, b2.odd_ball)
            assert.are.equal(1, #b2.history)
            assert.is_true(b2.won)
        end)

        it("load returns false for invalid data", function()
            local b = Board:new()
            assert.is_false(b:load(nil))
            assert.is_false(b:load({}))
        end)
    end)
end)
