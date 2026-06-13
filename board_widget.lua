local Blitbuffer     = require("ffi/blitbuffer")
local Font           = require("ui/font")
local GestureRange   = require("ui/gesturerange")
local Geom           = require("ui/geometry")
local InputContainer = require("ui/widget/container/inputcontainer")
local RenderText     = require("ui/rendertext")
local UIManager      = require("ui/uimanager")

local C_BG      = Blitbuffer.COLOR_WHITE
local C_PAN     = Blitbuffer.COLOR_GRAY_D
local C_PAN_BDR = Blitbuffer.COLOR_BLACK
local C_ARM     = Blitbuffer.COLOR_GRAY_5
local C_PIVOT   = Blitbuffer.COLOR_BLACK
local C_BALL_L  = Blitbuffer.COLOR_GRAY_9
local C_BALL_R  = Blitbuffer.COLOR_GRAY_B
local C_BALL_BD = Blitbuffer.COLOR_BLACK
local C_TEXT    = Blitbuffer.COLOR_BLACK

-- ---------------------------------------------------------------------------
-- BalanceBoardWidget  — draws the balance scale with pans
-- ---------------------------------------------------------------------------

local BalanceBoardWidget = InputContainer:extend{
    board      = nil,
    max_width  = 200,
    max_height = 150,
}

function BalanceBoardWidget:init()
    local w = self.max_width
    local h = self.max_height
    self.w = w
    self.h = h
    self.dimen     = Geom:new{ x = 0, y = 0, w = w, h = h }
    self.paint_rect = Geom:new{ x = 0, y = 0, w = w, h = h }

    local ball_sz = math.max(7, math.floor(h * 0.065))
    self.ball_face = Font:getFace("smallinfofont", ball_sz)

    -- No tap gestures — interaction is through screen buttons
end

function BalanceBoardWidget:refresh()
    local rect = self.paint_rect
    UIManager:setDirty(self, function()
        return "ui", Geom:new{ x = rect.x, y = rect.y, w = rect.w, h = rect.h }
    end)
end

-- Draw a small ball (circle approximated as filled square with 1px border) at cx,cy
function BalanceBoardWidget:_drawBall(bb, cx, cy, r, fill, label)
    bb:paintRect(cx - r, cy - r, 2 * r, 2 * r, fill)
    -- border
    bb:paintRect(cx - r, cy - r, 2 * r, 1, C_BALL_BD)
    bb:paintRect(cx - r, cy + r - 1, 2 * r, 1, C_BALL_BD)
    bb:paintRect(cx - r, cy - r, 1, 2 * r, C_BALL_BD)
    bb:paintRect(cx + r - 1, cy - r, 1, 2 * r, C_BALL_BD)
    if label and self.ball_face then
        local avail = 2 * r - 2
        local m  = RenderText:sizeUtf8Text(0, avail, self.ball_face, label, true, false)
        local tx = cx - math.floor(m.x / 2)
        local ty = cy + math.floor((m.y_bottom - m.y_top) / 2)
        RenderText:renderUtf8Text(bb, tx, ty, self.ball_face, label, true, false, C_TEXT)
    end
end

function BalanceBoardWidget:paintTo(bb, x, y)
    self.paint_rect = Geom:new{ x = x, y = y, w = self.w, h = self.h }
    local board = self.board
    local w, h  = self.w, self.h

    bb:paintRect(x, y, w, h, C_BG)

    -- Scale geometry
    local cx      = x + math.floor(w / 2)
    local pivot_y = y + math.floor(h * 0.20)
    local arm_len = math.floor(w * 0.38)
    local arm_h   = math.max(2, math.floor(h * 0.03))

    -- Determine tilt from last weighing result
    local tilt = 0   -- 0 = level, 1 = left down, -1 = right down
    if #board.history > 0 then
        local last = board.history[#board.history].result
        if last == "L" then tilt =  1
        elseif last == "R" then tilt = -1 end
    end
    local tilt_px = math.floor(h * 0.07) * tilt

    local left_arm_y  = pivot_y + tilt_px
    local right_arm_y = pivot_y - tilt_px

    -- Pivot post (vertical)
    local post_h = math.floor(h * 0.15)
    bb:paintRect(cx - 2, y + math.floor(h * 0.05), 4, post_h, C_ARM)

    -- Pivot triangle
    bb:paintRect(cx - 6, pivot_y - 3, 13, 6, C_PIVOT)

    -- Left arm
    local lax = x + math.floor(w * 0.12)
    bb:paintRect(lax, left_arm_y - arm_h, arm_len, arm_h, C_ARM)
    -- Right arm
    local rax = cx
    bb:paintRect(rax, right_arm_y - arm_h, arm_len, arm_h, C_ARM)

    -- Vertical strings to pans
    local string_len = math.floor(h * 0.12)
    local pan_w      = math.floor(arm_len * 0.80)
    local pan_h      = math.max(4, math.floor(h * 0.06))

    local left_pan_cx = lax + math.floor(pan_w / 2)
    local right_pan_cx = rax + arm_len - math.floor(pan_w / 2)

    local left_pan_y  = left_arm_y  + string_len
    local right_pan_y = right_arm_y + string_len

    -- String lines
    bb:paintRect(left_pan_cx  - 1, left_arm_y,  2, string_len, C_ARM)
    bb:paintRect(right_pan_cx - 1, right_arm_y, 2, string_len, C_ARM)

    -- Draw pans
    local lx = left_pan_cx  - math.floor(pan_w / 2)
    local rx = right_pan_cx - math.floor(pan_w / 2)
    bb:paintRect(lx, left_pan_y,  pan_w, pan_h, C_PAN)
    bb:paintRect(rx, right_pan_y, pan_w, pan_h, C_PAN)
    -- pan borders
    bb:paintRect(lx, left_pan_y,  pan_w, 1, C_PAN_BDR)
    bb:paintRect(lx, left_pan_y + pan_h - 1, pan_w, 1, C_PAN_BDR)
    bb:paintRect(lx, left_pan_y,  1, pan_h, C_PAN_BDR)
    bb:paintRect(lx + pan_w - 1, left_pan_y,  1, pan_h, C_PAN_BDR)
    bb:paintRect(rx, right_pan_y, pan_w, 1, C_PAN_BDR)
    bb:paintRect(rx, right_pan_y + pan_h - 1, pan_w, 1, C_PAN_BDR)
    bb:paintRect(rx, right_pan_y, 1, pan_h, C_PAN_BDR)
    bb:paintRect(rx + pan_w - 1, right_pan_y, 1, pan_h, C_PAN_BDR)

    -- Draw balls on pans
    local ball_r = math.max(4, math.floor(pan_w / (math.max(#board.left_pan, 1) * 2 + 1)))
    ball_r = math.min(ball_r, math.floor(pan_w / 4))
    ball_r = math.max(ball_r, 4)

    local function draw_pan_balls(pan, pan_cx, pan_y_top, fill)
        local n = #pan
        if n == 0 then return end
        local spacing = math.floor(pan_w / (n + 1))
        for i, b in ipairs(pan) do
            local bx = pan_cx - math.floor(pan_w / 2) + i * spacing
            local by = pan_y_top - ball_r - 1
            self:_drawBall(bb, bx, by, ball_r, fill, tostring(b))
        end
    end

    draw_pan_balls(board.left_pan,  left_pan_cx,  left_pan_y,  C_BALL_L)
    draw_pan_balls(board.right_pan, right_pan_cx, right_pan_y, C_BALL_R)

    -- Labels
    local lbl_y = y + h - 2
    local m_l   = RenderText:sizeUtf8Text(0, pan_w, self.ball_face, "L", true, false)
    local m_r   = RenderText:sizeUtf8Text(0, pan_w, self.ball_face, "R", true, false)
    RenderText:renderUtf8Text(bb, left_pan_cx  - math.floor(m_l.x / 2), lbl_y, self.ball_face, "L", true, false, C_TEXT)
    RenderText:renderUtf8Text(bb, right_pan_cx - math.floor(m_r.x / 2), lbl_y, self.ball_face, "R", true, false, C_TEXT)
end

return BalanceBoardWidget
