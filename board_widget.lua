local Blitbuffer     = require("ffi/blitbuffer")
local Device         = require("device")
local Font           = require("ui/font")
local GestureRange   = require("ui/gesturerange")
local Geom           = require("ui/geometry")
local InputContainer = require("ui/widget/container/inputcontainer")
local RenderText     = require("ui/rendertext")
local UIManager      = require("ui/uimanager")
local _              = require("i18n")

local Screen = Device.screen

local C_BG        = Blitbuffer.COLOR_WHITE
local C_INK       = Blitbuffer.COLOR_BLACK
local C_FRAME     = Blitbuffer.COLOR_GRAY_5
local C_PLATE     = Blitbuffer.COLOR_GRAY_D
local C_STRING    = Blitbuffer.COLOR_GRAY_7
local C_GHOST     = Blitbuffer.COLOR_GRAY_B
local C_MUTED     = Blitbuffer.COLOR_GRAY_7
local C_RULE      = Blitbuffer.COLOR_GRAY_D

-- ---------------------------------------------------------------------------
-- BalanceBoardWidget — the whole play area, drawn in one widget:
--
--   * the scale itself, whose beam tilts to show the last weighing (only while
--     the pans still hold exactly what was weighed; any change levels it, so a
--     tilted beam never describes a set-up that hasn't been weighed);
--   * the tray: every ball in a fixed slot, so positions never shift between
--     taps. A ball that is on a pan leaves a faint outline behind;
--   * the weighing log, one row per allowed weighing, the unused ones blank.
--
-- Tapping any ball (in the tray or on a pan) calls on_ball_tap(ball).
-- ---------------------------------------------------------------------------

local BalanceBoardWidget = InputContainer:extend{
    board       = nil,
    max_width   = 200,
    max_height  = 150,
    on_ball_tap = nil,
}

-- Font:getFace() scales its size by DPI; we size everything in real pixels.
local function face(px)
    local ratio = Screen:scaleBySize(1000) / 1000
    return Font:getFace("cfont", math.max(6, math.floor(px / ratio + 0.5)))
end

function BalanceBoardWidget:init()
    local w, h = self.max_width, self.max_height
    self.w, self.h = w, h
    self.dimen      = Geom:new{ x = 0, y = 0, w = w, h = h }
    self.paint_rect = Geom:new{ x = 0, y = 0, w = w, h = h }
    self.hits       = {}

    local n   = self.board.num_balls
    local pad = Screen:scaleBySize(8)
    self.pad  = pad

    -- Log rows: one per allowed weighing.
    local row_h       = math.max(Screen:scaleBySize(24), math.floor(h * 0.055))
    self.row_h        = row_h
    self.log_face     = face(math.floor(row_h * 0.62))
    self.caption_face = face(math.floor(row_h * 0.50))
    self.caption_h    = math.floor(row_h * 0.9)
    local log_h       = self.caption_h + row_h * self.board.max_weighings

    -- Tray: one row when the balls fit at a comfortable size, two otherwise.
    local min_r     = Screen:scaleBySize(20)
    local tray_rows = (w / (n * 2.5) >= min_r) and 1 or 2
    local per_row   = math.ceil(n / tray_rows)
    local r = math.floor(math.min(w / (per_row * 2.5), h * 0.045))
    self.tray_rows, self.tray_per_row = tray_rows, per_row
    self.ball_r = r
    local tray_h = self.caption_h + tray_rows * (2 * r + pad) + pad

    self.scene_h = h - tray_h - log_h - pad
    self.tray_y  = self.scene_h + pad
    self.log_y   = self.tray_y + tray_h

    self.ges_events = {
        Tap = {
            GestureRange:new{
                ges   = "tap",
                range = function() return self.paint_rect end,
            },
        },
    }
end

function BalanceBoardWidget:refresh()
    UIManager:setDirty(self, function()
        return "ui", Geom:new{ x = self.paint_rect.x, y = self.paint_rect.y, w = self.w, h = self.h }
    end)
end

function BalanceBoardWidget:onTap(_, ges)
    if not (ges and ges.pos) then return false end
    local lx = ges.pos.x - self.paint_rect.x
    local ly = ges.pos.y - self.paint_rect.y
    for _, hit in ipairs(self.hits) do
        local dx, dy = lx - hit.x, ly - hit.y
        -- A little slack around the ball: fingers are wider than outlines.
        if dx * dx + dy * dy <= (hit.r * 1.25) ^ 2 then
            if self.on_ball_tap then self.on_ball_tap(hit.ball) end
            return true
        end
    end
    return true
end

-- ---------------------------------------------------------------------------
-- Drawing primitives
-- ---------------------------------------------------------------------------

-- Thick straight line, drawn as one vertical run per column (the beam is
-- never steep, so this is both exact enough and cheap).
local function paintSlope(bb, x0, y0, x1, y1, thick, color)
    local half = math.floor(thick / 2)
    for x = x0, x1 do
        local y = y0 + (y1 - y0) * (x - x0) / (x1 - x0)
        bb:paintRect(x, math.floor(y + 0.5) - half, 1, thick, color)
    end
end

-- Thin line between any two points (strings).
local function paintLine(bb, x0, y0, x1, y1, color)
    local steps = math.max(math.abs(x1 - x0), math.abs(y1 - y0), 1)
    for i = 0, steps do
        local t = i / steps
        bb:paintRect(math.floor(x0 + (x1 - x0) * t + 0.5), math.floor(y0 + (y1 - y0) * t + 0.5), 1, 1, color)
    end
end

-- Filled isosceles triangle, apex on top.
local function paintTriangle(bb, cx, top, half_w, height, color)
    for i = 0, height - 1 do
        local hw = math.floor(half_w * (i + 1) / height)
        bb:paintRect(cx - hw, top + i, 2 * hw + 1, 1, color)
    end
end

local function textWidth(fc, text)
    return RenderText:sizeUtf8Text(0, Screen:getWidth(), fc, text, true, false).x
end

-- Draw text with its visual middle on cy.
local function paintTextCentered(bb, cx, cy, fc, text, color, max_w)
    -- y_top/y_bottom are the ink's extent above/below the baseline.
    local m  = RenderText:sizeUtf8Text(0, max_w or Screen:getWidth(), fc, text, true, false)
    local tx = cx - math.floor(m.x / 2)
    local baseline = cy + math.floor((m.y_top - m.y_bottom) / 2 + 0.5)
    RenderText:renderUtf8Text(bb, tx, baseline, fc, text, true, false, color, max_w)
end

-- ---------------------------------------------------------------------------
-- Balls
-- ---------------------------------------------------------------------------

-- style: "normal" | "ghost" | "reveal" (the odd ball, once the game is over)
function BalanceBoardWidget:_paintBall(bb, ox, oy, cx, cy, r, ball, style)
    local ring = math.max(2, math.floor(r / 10))
    local fc   = face(math.floor(r * 0.95))
    if style == "ghost" then
        bb:paintCircle(ox + cx, oy + cy, r, C_GHOST, math.max(1, math.floor(ring / 2)))
        paintTextCentered(bb, ox + cx, oy + cy, fc, tostring(ball), C_GHOST)
    elseif style == "reveal" then
        bb:paintCircle(ox + cx, oy + cy, r, C_INK)
        paintTextCentered(bb, ox + cx, oy + cy, fc, tostring(ball), C_BG)
    else
        bb:paintCircle(ox + cx, oy + cy, r, C_BG)
        bb:paintCircle(ox + cx, oy + cy, r, C_INK, ring)
        paintTextCentered(bb, ox + cx, oy + cy, fc, tostring(ball), C_INK)
    end
    if style ~= "ghost" or not (self.board.won or self.board.lost) then
        self.hits[#self.hits + 1] = { x = cx, y = cy, r = r, ball = ball }
    end
end

function BalanceBoardWidget:_ballStyle(ball)
    local b = self.board
    if (b.won or b.lost) and ball == b.odd_ball then return "reveal" end
    return "normal"
end

-- Stack the pan's balls on the plate: a bottom row, then rows above it.
-- Returns the pile height so the hanger can clear it.
local function pileLayout(n, plate_w, r_max)
    if n == 0 then return {}, r_max, 0 end
    local per_row = math.min(n, 4)
    local r = math.min(r_max, math.floor(plate_w / (per_row * 2 + 1)))
    local rows = math.ceil(n / per_row)
    local pos, i = {}, 0
    for row = 1, rows do
        local in_row = math.min(per_row, n - i)
        local span = in_row * 2 * r
        for k = 1, in_row do
            i = i + 1
            pos[i] = {
                dx = -math.floor(span / 2) + (2 * k - 1) * r,
                dy = -(2 * row - 1) * r,
            }
        end
    end
    return pos, r, rows * 2 * r
end

-- ---------------------------------------------------------------------------
-- Scene: the scale
-- ---------------------------------------------------------------------------

function BalanceBoardWidget:_paintScene(bb, ox, oy)
    local w, h  = self.w, self.scene_h
    local board = self.board
    local cx    = math.floor(w / 2)
    local unit  = math.max(2, math.floor(math.min(w, h) / 90))

    local half_beam = math.floor(w * 0.31)
    local plate_w   = math.floor(w * 0.30)

    -- Pile heights decide how long the hangers must be.
    local pan_r = math.max(self.ball_r, math.floor(plate_w / 9))
    local lpos, lr, lpile = pileLayout(#board.left_pan,  plate_w, pan_r)
    local rpos, rr, rpile = pileLayout(#board.right_pan, plate_w, pan_r)
    local min_pile = math.max(lpile, rpile, 4 * pan_r)

    local pivot_y = math.floor(h * 0.16)
    local tilt_px = math.floor(h * 0.07)
    local hang    = math.max(min_pile + 3 * unit, math.floor(h * 0.42))
    -- Keep the whole drawing inside the scene, whatever the pile height.
    local plate_bottom_room = h - (pivot_y + tilt_px + hang + 3 * unit)
    if plate_bottom_room < 0 then
        pivot_y = math.max(3 * unit, pivot_y + plate_bottom_room)
    end

    local result = board:currentResult()
    local tilt = (result == "L" and 1) or (result == "R" and -1) or 0
    local ly = pivot_y + tilt * tilt_px
    local ry = pivot_y - tilt * tilt_px
    local lx, rx = cx - half_beam, cx + half_beam

    -- Stand: base, column, fulcrum.
    local base_w = math.floor(w * 0.22)
    local base_h = 2 * unit
    local base_y = h - base_h - unit
    bb:paintRoundedRect(ox + cx - math.floor(base_w / 2), oy + base_y, base_w, base_h, C_INK, unit)
    local col_w = 2 * unit
    bb:paintRect(ox + cx - unit, oy + pivot_y, col_w, base_y - pivot_y, C_FRAME)
    paintTriangle(bb, ox + cx, oy + pivot_y - unit, 4 * unit, 6 * unit, C_INK)

    -- Beam.
    paintSlope(bb, ox + lx, oy + ly, ox + rx, oy + ry, 2 * unit, C_INK)
    bb:paintCircle(ox + cx, oy + pivot_y, 2 * unit, C_BG)
    bb:paintCircle(ox + cx, oy + pivot_y, 2 * unit, C_INK, math.max(1, math.floor(unit / 2)))

    -- Pans: hook at the beam end, two strings down to the plate rim.
    local function pan(hx, hy, pos, r, label, balls)
        local plate_y = hy + hang
        local px0 = hx - math.floor(plate_w / 2)
        bb:paintCircle(ox + hx, oy + hy, unit + 1, C_INK)
        paintLine(bb, ox + hx, oy + hy, ox + px0, oy + plate_y, C_STRING)
        paintLine(bb, ox + hx, oy + hy, ox + px0 + plate_w, oy + plate_y, C_STRING)
        -- Plate: a shallow dish, wider at the top.
        local dish_h = 2 * unit
        for i = 0, dish_h - 1 do
            local inset = math.floor(i * 1.5)
            bb:paintRect(ox + px0 + inset, oy + plate_y + i, plate_w - 2 * inset, 1, C_PLATE)
        end
        bb:paintRect(ox + px0, oy + plate_y, plate_w, math.max(1, math.floor(unit / 2)), C_INK)
        for i, p in ipairs(pos) do
            local ball = balls[i]
            self:_paintBall(bb, ox, oy, hx + p.dx, plate_y + p.dy, r, ball, self:_ballStyle(ball))
        end
        -- Pan name under the dish.
        paintTextCentered(bb, ox + hx, oy + plate_y + dish_h + math.floor(self.caption_h / 2) + unit,
            self.caption_face, label, C_MUTED)
    end
    pan(lx, ly, lpos, lr, _("Left pan"),  board.left_pan)
    pan(rx, ry, rpos, rr, _("Right pan"), board.right_pan)
end

-- ---------------------------------------------------------------------------
-- Tray
-- ---------------------------------------------------------------------------

local function caption(self, bb, ox, oy, y, text)
    local x = ox + self.pad
    local m = RenderText:sizeUtf8Text(0, self.w, self.caption_face, text, true, false)
    local _, asc = self.caption_face.ftsize:getHeightAndAscender()
    RenderText:renderUtf8Text(bb, x, oy + y + math.floor(asc), self.caption_face, text, true, false, C_MUTED)
    local rule_x = x + m.x + self.pad
    bb:paintRect(rule_x, oy + y + math.floor(asc * 0.6), ox + self.w - self.pad - rule_x, 1, C_RULE)
end

function BalanceBoardWidget:_paintTray(bb, ox, oy)
    local board = self.board
    local r, per_row = self.ball_r, self.tray_per_row
    caption(self, bb, ox, oy, self.tray_y, _("Off the scale"))
    local top  = self.tray_y + self.caption_h + self.pad
    local slot = math.floor(self.w / per_row)
    for i = 1, board.num_balls do
        local row = math.floor((i - 1) / per_row)
        local col = (i - 1) % per_row
        local in_row = math.min(per_row, board.num_balls - row * per_row)
        local x0 = math.floor((self.w - in_row * slot) / 2)
        local cx = x0 + col * slot + math.floor(slot / 2)
        local cy = top + row * (2 * r + self.pad) + r
        local on_pan = board:getBallState(i) ~= 0
        self:_paintBall(bb, ox, oy, cx, cy, r, i, on_pan and "ghost" or self:_ballStyle(i))
    end
end

-- ---------------------------------------------------------------------------
-- Weighing log
-- ---------------------------------------------------------------------------

-- Small tilted-beam pictogram for one result; nil draws an unused slot.
local function paintResultIcon(bb, cx, cy, size, result)
    local half = math.floor(size / 2)
    local tilt = (result == "L" and 1) or (result == "R" and -1) or 0
    local d = math.floor(size * 0.18) * tilt
    if not result then
        bb:paintRect(cx - half, cy, size, 1, C_GHOST)
        return
    end
    local t = math.max(2, math.floor(size / 12))
    paintSlope(bb, cx - half, cy + d, cx + half, cy - d, t, C_INK)
    paintTriangle(bb, cx, cy + 1, math.floor(size / 7), math.floor(size / 4), C_INK)
    local pr = math.max(2, math.floor(size / 9))
    bb:paintCircle(cx - half, cy + d + pr, pr, C_INK)
    bb:paintCircle(cx + half, cy - d + pr, pr, C_INK)
end

function BalanceBoardWidget:_paintLog(bb, ox, oy)
    local board = self.board
    caption(self, bb, ox, oy, self.log_y, _("Weighings"))
    local fc     = self.log_face
    local _, asc = fc.ftsize:getHeightAndAscender()
    local icon   = math.floor(self.row_h * 1.4)
    local mid    = math.floor(self.w / 2)
    local gap    = self.pad * 2
    local idx_w  = textWidth(fc, "8.") + self.pad
    local side_w = mid - math.floor(icon / 2) - gap - idx_w - self.pad
    for i = 1, board.max_weighings do
        local top  = self.log_y + self.caption_h + (i - 1) * self.row_h
        local cy   = oy + top + math.floor(self.row_h / 2)
        local base = cy + math.floor(asc / 2) - math.floor(asc * 0.12)
        local h    = board.history[i]
        local color = h and C_INK or C_GHOST
        RenderText:renderUtf8Text(bb, ox + self.pad, base, fc, i .. ".", true, false, color)
        if h then
            local ls = table.concat(h.left, " ")
            local rs = table.concat(h.right, " ")
            if ls == "" then ls = "–" end
            if rs == "" then rs = "–" end
            local lw = math.min(textWidth(fc, ls), side_w)
            RenderText:renderUtf8Text(bb, ox + mid - math.floor(icon / 2) - gap - lw, base, fc, ls,
                true, false, C_INK, side_w)
            RenderText:renderUtf8Text(bb, ox + mid + math.floor(icon / 2) + gap, base, fc, rs,
                true, false, C_INK, side_w)
        end
        paintResultIcon(bb, ox + mid, cy, icon, h and h.result)
    end
end

-- ---------------------------------------------------------------------------

function BalanceBoardWidget:paintTo(bb, x, y)
    self.paint_rect = Geom:new{ x = x, y = y, w = self.w, h = self.h }
    self.hits = {}
    bb:paintRect(x, y, self.w, self.h, C_BG)
    -- Pan balls are hit-tested before tray outlines (both can't overlap, but
    -- keep the order explicit: visible balls first).
    self:_paintScene(bb, x, y)
    self:_paintTray(bb, x, y)
    self:_paintLog(bb, x, y)
end

return BalanceBoardWidget
