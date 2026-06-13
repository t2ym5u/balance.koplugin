-- ---------------------------------------------------------------------------
-- BalanceBoard — logical weighing puzzle
-- ---------------------------------------------------------------------------

local BalanceBoard = {}
BalanceBoard.__index = BalanceBoard

local PRESETS = {
    easy   = { num_balls = 8,  max_weighings = 3 },
    medium = { num_balls = 12, max_weighings = 3 },
    hard   = { num_balls = 12, max_weighings = 3 },  -- same size, less info given
}

function BalanceBoard:new(opts)
    opts = opts or {}
    local preset = opts.preset or "easy"
    local cfg    = PRESETS[preset] or PRESETS.easy
    local o = setmetatable({}, self)
    o.preset         = preset
    o.num_balls      = cfg.num_balls
    o.max_weighings  = cfg.max_weighings
    o.balls          = {}
    for i = 1, o.num_balls do o.balls[i] = i end
    o.odd_ball       = nil
    o.odd_heavier    = nil
    o.left_pan       = {}
    o.right_pan      = {}
    o.history        = {}
    o.weighings_used = 0
    o.guess          = nil
    o.won            = false
    o.lost           = false
    o:newGame()
    return o
end

function BalanceBoard:newGame(preset)
    if preset then
        self.preset = preset
        local cfg = PRESETS[preset] or PRESETS.easy
        self.num_balls     = cfg.num_balls
        self.max_weighings = cfg.max_weighings
        self.balls = {}
        for i = 1, self.num_balls do self.balls[i] = i end
    end
    self.odd_ball       = math.random(self.num_balls)
    self.odd_heavier    = (math.random(2) == 1)
    self.left_pan       = {}
    self.right_pan      = {}
    self.history        = {}
    self.weighings_used = 0
    self.guess          = nil
    self.won            = false
    self.lost           = false
end

-- ball_state[b]: 0=none, 1=left, 2=right
function BalanceBoard:getBallState(b)
    for _, v in ipairs(self.left_pan) do
        if v == b then return 1 end
    end
    for _, v in ipairs(self.right_pan) do
        if v == b then return 2 end
    end
    return 0
end

-- Cycle ball through: none → left → right → none
function BalanceBoard:cycleBall(b)
    if self.won or self.lost then return end
    local st = self:getBallState(b)
    if st == 0 then
        self.left_pan[#self.left_pan + 1] = b
    elseif st == 1 then
        -- remove from left, add to right
        for i, v in ipairs(self.left_pan) do
            if v == b then table.remove(self.left_pan, i); break end
        end
        self.right_pan[#self.right_pan + 1] = b
    else
        -- remove from right
        for i, v in ipairs(self.right_pan) do
            if v == b then table.remove(self.right_pan, i); break end
        end
    end
end

function BalanceBoard:clearPans()
    self.left_pan  = {}
    self.right_pan = {}
end

-- Weigh: returns "L", "R", "=", or nil on error (no balls / exhausted / game over)
function BalanceBoard:weigh()
    if self.won or self.lost then return nil end
    if self:weighingsExhausted() then return nil end
    if #self.left_pan == 0 and #self.right_pan == 0 then return nil end
    -- compute weights: odd ball is ±1 different
    local lw, rw = 0, 0
    for _, b in ipairs(self.left_pan) do
        local weight = 10
        if b == self.odd_ball then
            weight = self.odd_heavier and 11 or 9
        end
        lw = lw + weight
    end
    for _, b in ipairs(self.right_pan) do
        local weight = 10
        if b == self.odd_ball then
            weight = self.odd_heavier and 11 or 9
        end
        rw = rw + weight
    end

    local result
    if lw > rw then
        result = "L"
    elseif rw > lw then
        result = "R"
    else
        result = "="
    end

    local hist_left  = {}
    local hist_right = {}
    for _, v in ipairs(self.left_pan)  do hist_left[#hist_left + 1]   = v end
    for _, v in ipairs(self.right_pan) do hist_right[#hist_right + 1] = v end
    self.history[#self.history + 1] = {
        left   = hist_left,
        right  = hist_right,
        result = result,
    }
    self.weighings_used = self.weighings_used + 1
    -- Do NOT set lost here: the player must still be able to make a guess.
    -- Lost is only set in makeGuess if the guess is wrong, or if the game
    -- ends without a guess (handled by UI/screen layer).
    return result
end

-- Returns true when the player has used all allowed weighings.
function BalanceBoard:weighingsExhausted()
    return self.weighings_used >= self.max_weighings
end

-- Player declares a guess
function BalanceBoard:makeGuess(ball, heavier)
    if self.won then return false end
    -- Allow a guess even after weighings are exhausted (player must commit).
    self.guess = { ball = ball, heavier = heavier }
    if ball == self.odd_ball and heavier == self.odd_heavier then
        self.won  = true
        self.lost = false
    else
        self.lost = true
        self.won  = false
    end
    return self.won
end

function BalanceBoard:serialize()
    local hist = {}
    for i, h in ipairs(self.history) do
        local l, r = {}, {}
        for _, v in ipairs(h.left)  do l[#l + 1] = v end
        for _, v in ipairs(h.right) do r[#r + 1] = v end
        hist[i] = { left = l, right = r, result = h.result }
    end
    local lp, rp = {}, {}
    for _, v in ipairs(self.left_pan)  do lp[#lp + 1] = v end
    for _, v in ipairs(self.right_pan) do rp[#rp + 1] = v end
    local g = nil
    if self.guess then
        g = { ball = self.guess.ball, heavier = self.guess.heavier }
    end
    return {
        preset         = self.preset,
        num_balls      = self.num_balls,
        max_weighings  = self.max_weighings,
        odd_ball       = self.odd_ball,
        odd_heavier    = self.odd_heavier,
        left_pan       = lp,
        right_pan      = rp,
        history        = hist,
        weighings_used = self.weighings_used,
        guess          = g,
        won            = self.won,
        lost           = self.lost,
    }
end

function BalanceBoard:load(data)
    if type(data) ~= "table" or not data.odd_ball then return false end
    self.preset         = data.preset        or "easy"
    self.num_balls      = data.num_balls     or 8
    self.max_weighings  = data.max_weighings or 3
    self.balls = {}
    for i = 1, self.num_balls do self.balls[i] = i end
    self.odd_ball       = data.odd_ball
    self.odd_heavier    = data.odd_heavier
    self.left_pan       = data.left_pan      or {}
    self.right_pan      = data.right_pan     or {}
    self.history        = data.history       or {}
    self.weighings_used = data.weighings_used or 0
    self.guess          = data.guess
    self.won            = data.won   or false
    self.lost           = data.lost  or false
    return true
end

BalanceBoard.PRESETS      = PRESETS
BalanceBoard.PRESET_ORDER = { "easy", "medium" }

return BalanceBoard
