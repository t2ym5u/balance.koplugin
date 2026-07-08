local _dir = debug.getinfo(1, "S").source:sub(2):match("(.*[/\\])") or "./"
local function lrequire(name)
    local key = _dir .. name
    if not package.loaded[key] then
        package.loaded[key] = assert(loadfile(_dir .. name .. ".lua"))()
    end
    return package.loaded[key]
end

local ButtonTable     = require("ui/widget/buttontable")
local Device          = require("device")
local Font            = require("ui/font")
local FrameContainer  = require("ui/widget/container/framecontainer")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan  = require("ui/widget/horizontalspan")
local InputDialog     = require("ui/widget/inputdialog")
local Size            = require("ui/size")
local TextWidget      = require("ui/widget/textwidget")
local UIManager       = require("ui/uimanager")
local VerticalGroup   = require("ui/widget/verticalgroup")
local VerticalSpan    = require("ui/widget/verticalspan")
local _               = require("i18n")
local T               = require("ffi/util").template

local ScreenBase         = require("screen_base")
local MenuHelper         = require("menu_helper")
local BalanceBoard       = lrequire("board")
local BalanceBoardWidget = lrequire("board_widget")

local DeviceScreen = Device.screen

local GAME_RULES_EN = _([[
Balance Puzzle — Rules

One ball in the set is either heavier or lighter than all the others. Use a balance scale to find it in as few weighings as possible.

Each weighing:
• Assign balls to the left pan, the right pan, or leave them aside.
• Tap Weigh to see which side is heavier, or if they balance.
• Use the results to narrow down which ball is the odd one.

When you have identified the odd ball and whether it is heavier or lighter, tap Guess to submit your answer.

The puzzle is won when you correctly identify the odd ball within the allowed number of weighings.
]])

local GAME_RULES_FR = [[
Jeu de Balance — Règles

Une bille parmi l'ensemble est soit plus lourde soit plus légère que toutes les autres. Utilisez la balance pour l'identifier en un minimum de pesées.

Chaque pesée :
• Placez des billes sur le plateau gauche, le plateau droit ou laissez-les de côté.
• Appuyez sur Peser pour voir quel côté est plus lourd, ou si les deux côtés sont égaux.
• Utilisez les résultats pour déterminer quelle bille est la bille anormale.

Quand vous avez identifié la bille anormale et si elle est plus lourde ou plus légère, appuyez sur Deviner pour soumettre votre réponse.

Le puzzle est résolu quand vous identifiez correctement la bille anormale dans le nombre de pesées imparti.
]]

local BalanceScreen = ScreenBase:extend{}

function BalanceScreen:init()
    local state  = self.plugin:loadState()
    local preset = self.plugin:getSetting("preset", "easy")
    self.board   = BalanceBoard:new{ preset = preset }
    if not self.board:load(state) then
        -- new game already ready
    end
    ScreenBase.init(self)
end

function BalanceScreen:serializeState()
    return self.board:serialize()
end

-- ---------------------------------------------------------------------------
-- Layout
-- ---------------------------------------------------------------------------

function BalanceScreen:buildLayout()
    local sw           = DeviceScreen:getWidth()
    local sh = DeviceScreen:getHeight()
    local is_landscape = self:isLandscape()

    local btn_width = is_landscape
        and math.max(math.floor(sw * 0.38), 100)
        or  math.floor(sw * 0.9)

    local top_buttons = ButtonTable:new{
        shrink_unneeded_width = true,
        width   = btn_width,
        buttons = {{
            { text = _("New"),    callback = function() self:onNewGame() end },
            { id = "preset_btn", text = self:getPresetButtonText(),
              callback = function() self:openPresetMenu() end },
            self:makeRulesButtonConfig(GAME_RULES_EN, GAME_RULES_FR),
            self:makeCloseButtonConfig(),
        }},
    }
    self.preset_btn = top_buttons:getButtonById("preset_btn")

    -- Ball buttons (cycle through: none / L / R)
    local ball_btns = self:_buildBallButtons(btn_width)

    -- Action buttons
    local action_buttons = ButtonTable:new{
        shrink_unneeded_width = true,
        width   = btn_width,
        buttons = {{
            { text = _("Weigh"),      callback = function() self:onWeigh() end },
            { text = _("Clear Pans"), callback = function() self:onClearPans() end },
            { text = _("Guess"),      callback = function() self:onGuess() end },
        }},
    }

    -- History text
    local hist_sz   = math.max(8, math.floor(sh * 0.025))
    self.hist_face  = Font:getFace("smallinfofont", hist_sz)
    self.hist_text  = TextWidget:new{
        text = self:_buildHistoryText(),
        face = self.hist_face,
    }

    local margin      = Size.margin.default
    local padding     = Size.padding.large
    local frame_extra = (padding + margin) * 2

    local board_max_w = is_landscape and math.floor(sw * 0.50) or (sw - frame_extra)
    local board_max_h = math.floor(sh * 0.25)

    self.board_widget = BalanceBoardWidget:new{
        board      = self.board,
        max_width  = board_max_w,
        max_height = board_max_h,
    }

    local board_frame = FrameContainer:new{
        padding = padding,
        margin  = margin,
        self.board_widget,
    }

    if is_landscape then
        local right_panel = VerticalGroup:new{
            align = "center",
            top_buttons,
            VerticalSpan:new{ width = Size.span.vertical_default },
            ball_btns,
            VerticalSpan:new{ width = Size.span.vertical_default },
            action_buttons,
            VerticalSpan:new{ width = Size.span.vertical_default },
            self.hist_text,
            VerticalSpan:new{ width = Size.span.vertical_default },
            self.status_text,
        }
        self.layout = HorizontalGroup:new{
            align  = "center",
            board_frame,
            HorizontalSpan:new{ width = Size.span.horizontal_default },
            right_panel,
        }
    else
        self.layout = VerticalGroup:new{
            align = "center",
            VerticalSpan:new{ width = Size.span.vertical_large },
            top_buttons,
            VerticalSpan:new{ width = Size.span.vertical_default },
            board_frame,
            VerticalSpan:new{ width = Size.span.vertical_default },
            ball_btns,
            VerticalSpan:new{ width = Size.span.vertical_default },
            action_buttons,
            VerticalSpan:new{ width = Size.span.vertical_default },
            self.hist_text,
            VerticalSpan:new{ width = Size.span.vertical_default },
            self.status_text,
            VerticalSpan:new{ width = Size.span.vertical_large },
        }
    end
    self[1] = self.layout
    self:updateStatus()
end

function BalanceScreen:_buildBallButtons(width)
    local board = self.board
    local rows  = {}
    local row   = {}
    local max_per_row = 8
    for i = 1, board.num_balls do
        row[#row + 1] = {
            id       = "ball_" .. i,
            text     = self:_ballLabel(i),
            callback = function()
                board:cycleBall(i)
                self:_refreshBallButtons()
                self.board_widget:refresh()
                self:updateStatus()
                self.plugin:saveState(self.board:serialize())
            end,
        }
        if #row >= max_per_row or i == board.num_balls then
            rows[#rows + 1] = row
            row = {}
        end
    end
    self.ball_button_table = ButtonTable:new{
        shrink_unneeded_width = true,
        width   = width,
        buttons = rows,
    }
    -- cache button refs
    self.ball_buttons = {}
    for i = 1, board.num_balls do
        self.ball_buttons[i] = self.ball_button_table:getButtonById("ball_" .. i)
    end
    return self.ball_button_table
end

function BalanceScreen:_ballLabel(i)
    local st = self.board:getBallState(i)
    if st == 1 then return "L:" .. i
    elseif st == 2 then return "R:" .. i
    else return tostring(i) end
end

function BalanceScreen:_refreshBallButtons()
    if not self.ball_buttons then return end
    for i, btn in ipairs(self.ball_buttons) do
        if btn then
            btn:setText(self:_ballLabel(i), btn.width)
        end
    end
end

function BalanceScreen:_buildHistoryText()
    local lines = {}
    for i, h in ipairs(self.board.history) do
        local ls = table.concat(h.left,  ",")
        local rs = table.concat(h.right, ",")
        local sym = h.result == "L" and "<" or (h.result == "R" and ">" or "=")
        lines[#lines + 1] = string.format("#%d: [%s] %s [%s]", i, ls, sym, rs)
    end
    return #lines > 0 and table.concat(lines, "  ") or _("No weighings yet")
end

-- ---------------------------------------------------------------------------
-- Actions
-- ---------------------------------------------------------------------------

function BalanceScreen:onWeigh()
    if self.board.won or self.board.lost then
        self:updateStatus()
        return
    end
    local result = self.board:weigh()
    if result == nil then
        if self.board:weighingsExhausted() then
            self:showMessage(_("No weighings remaining — make your guess!"))
        else
            self:showMessage(_("Place balls on the pans first."))
        end
        return
    end
    self.board_widget:refresh()
    if self.hist_text then
        self.hist_text:setText(self:_buildHistoryText())
    end
    self:updateStatus()
    self.plugin:saveState(self.board:serialize())
end

function BalanceScreen:onClearPans()
    self.board:clearPans()
    self:_refreshBallButtons()
    self.board_widget:refresh()
    self:updateStatus()
    self.plugin:saveState(self.board:serialize())
end

function BalanceScreen:onGuess()
    if self.board.won or self.board.lost then
        self:updateStatus()
        return
    end
    -- Build a guess menu: pick ball, then heavier/lighter
    local ball_items = {}
    for i = 1, self.board.num_balls do
        ball_items[#ball_items + 1] = { id = i, text = _("Ball ") .. i }
    end
    MenuHelper.openPickerMenu{
        title      = _("Which ball is the odd one?"),
        items      = ball_items,
        current_id = nil,
        parent     = self,
        on_select  = function(ball)
            -- Now ask heavier or lighter
            MenuHelper.openPickerMenu{
                title      = _("Heavier or lighter?"),
                items      = {
                    { id = true,  text = _("Heavier") },
                    { id = false, text = _("Lighter") },
                },
                current_id = nil,
                parent     = self,
                on_select  = function(heavier)
                    local correct = self.board:makeGuess(ball, heavier)
                    self:updateStatus()
                    if correct then
                        self:showMessage(T(_("Correct! Ball %1 was %2."), ball,
                            heavier and _("heavier") or _("lighter")), 4)
                    else
                        self:showMessage(T(_("Wrong! Ball %1 was %2."), self.board.odd_ball,
                            self.board.odd_heavier and _("heavier") or _("lighter")), 4)
                    end
                    self.plugin:saveState(self.board:serialize())
                end,
            }
        end,
    }
end

function BalanceScreen:onNewGame()
    local preset = self.plugin:getSetting("preset", "easy")
    self.board   = BalanceBoard:new{ preset = preset }
    self.plugin:saveState(self.board:serialize())
    self:buildLayout()
    UIManager:setDirty(self, function() return "ui", self.dimen end)
end

function BalanceScreen:openPresetMenu()
    local items = {}
    for _, id in ipairs(BalanceBoard.PRESET_ORDER) do
        local cfg = BalanceBoard.PRESETS[id]
        items[#items + 1] = {
            id   = id,
            text = string.format("%s (%d balls, %d weighings)",
                id:sub(1,1):upper() .. id:sub(2), cfg.num_balls, cfg.max_weighings),
        }
    end
    MenuHelper.openSizeMenu{
        title     = _("Select difficulty"),
        sizes     = items,
        current   = self.plugin:getSetting("preset", "easy"),
        parent    = self,
        on_select = function(id)
            self.plugin:saveSetting("preset", id)
            if self.preset_btn then
                self.preset_btn:setText(self:getPresetButtonText(), self.preset_btn.width)
            end
            self:onNewGame()
        end,
    }
end

-- ---------------------------------------------------------------------------
-- Status
-- ---------------------------------------------------------------------------

function BalanceScreen:updateStatus(msg)
    local status
    if msg then
        status = msg
    elseif self.board.won then
        status = T(_("Correct! Weighings: %1/%2"), self.board.weighings_used, self.board.max_weighings)
    elseif self.board.lost then
        status = T(_("Game over. Odd ball was #%1 (%2)."), self.board.odd_ball,
            self.board.odd_heavier and _("heavier") or _("lighter"))
    else
        status = T(_("Weighings: %1/%2"), self.board.weighings_used, self.board.max_weighings)
        local lc = #self.board.left_pan
        local rc = #self.board.right_pan
        if lc > 0 or rc > 0 then
            status = status .. T(_(" | L:%1 R:%2"), lc, rc)
        end
    end
    ScreenBase.updateStatus(self, status)
end

function BalanceScreen:getPresetButtonText()
    local preset = self.plugin:getSetting("preset", "easy")
    return preset:sub(1,1):upper() .. preset:sub(2)
end

return BalanceScreen
