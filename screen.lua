local _dir = debug.getinfo(1, "S").source:sub(2):match("(.*[/\\])") or "./"
local function lrequire(name)
    local key = _dir .. name
    if not package.loaded[key] then
        package.loaded[key] = assert(loadfile(_dir .. name .. ".lua"))()
    end
    return package.loaded[key]
end

local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan  = require("ui/widget/horizontalspan")
local Size            = require("ui/size")
local UIManager       = require("ui/uimanager")
local VerticalGroup   = require("ui/widget/verticalgroup")
local VerticalSpan    = require("ui/widget/verticalspan")
local _               = require("i18n")
local T               = require("ffi/util").template

local ScreenBase         = require("screen_base")
local MenuHelper         = require("menu_helper")
local BalanceBoard       = lrequire("board")
local BalanceBoardWidget = lrequire("board_widget")

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
    local is_landscape = self:isLandscape()

    local title_bar = self:buildTitleBar(_("Balance"), function()
        return {
            { text = _("New game"),               callback = function() self:onNewGame() end },
            { text = T(_("Difficulty: %1"), self:getPresetButtonText()),
              callback = function() self:openPresetMenu() end },
            self:makeRulesButtonConfig(GAME_RULES_EN, GAME_RULES_FR),
        }
    end)

    local footer_w = self:getControlsWidth()
    self.status_text:setMaxWidth(footer_w)

    local footer = VerticalGroup:new{
        align = "center",
        self.status_text,
        VerticalSpan:new{ width = Size.span.vertical_large },
        self:buildActionBar({
            { text = _("Weigh"),      callback = function() self:onWeigh() end },
            { text = _("Clear Pans"), callback = function() self:onClearPans() end },
            { text = _("Guess"),      callback = function() self:onGuess() end },
        }),
    }

    -- The board takes every pixel the title bar and footer leave over.
    local board_w, board_h = self:getBoardBudget(title_bar, footer)

    self.board_widget = BalanceBoardWidget:new{
        board       = self.board,
        max_width   = board_w,
        max_height  = board_h,
        on_ball_tap = function(ball) self:onBallTap(ball) end,
    }

    if is_landscape then
        local content = HorizontalGroup:new{
            align  = "center",
            self.board_widget,
            HorizontalSpan:new{ width = self:getGutter() },
            footer,
        }
        self:buildLandscapeLayout(title_bar, content)
    else
        self:buildPortraitLayout(title_bar, self.board_widget,
            VerticalGroup:new{ align = "center", footer, VerticalSpan:new{ width = self:getGutter() } })
    end
    self:updateStatus()
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
    self:updateStatus()
    self.plugin:saveState(self.board:serialize())
end

function BalanceScreen:onBallTap(ball)
    if self.board.won or self.board.lost then return end
    self.board:cycleBall(ball)
    self.board_widget:refresh()
    self:updateStatus()
    self.plugin:saveState(self.board:serialize())
end

function BalanceScreen:onClearPans()
    self.board:clearPans()
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
                    self:refreshActionBar()
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

function BalanceScreen:isRoundOver()
    return (self.board.won or self.board.lost) and true or false
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
    for _i, id in ipairs(BalanceBoard.PRESET_ORDER) do
        local cfg = BalanceBoard.PRESETS[id]
        items[#items + 1] = {
            id   = id,
            text = T(_("%1 (%2 balls, %3 weighings)"),
                MenuHelper.DIFFICULTY_LABELS[id] or id, cfg.num_balls, cfg.max_weighings),
        }
    end
    MenuHelper.openSizeMenu{
        title     = _("Difficulty"),
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
        local count = T(_("Weighings: %1/%2"), self.board.weighings_used, self.board.max_weighings)
        local result = self.board:currentResult()
        local lead
        if result == "L" then
            lead = _("Left pan is heavier")
        elseif result == "R" then
            lead = _("Right pan is heavier")
        elseif result == "=" then
            lead = _("The pans balance")
        elseif #self.board.history == 0 and #self.board.left_pan == 0 and #self.board.right_pan == 0 then
            lead = _("Tap a ball: left pan, right pan, back")
        end
        status = self:joinStatus(lead, count)
    end
    ScreenBase.updateStatus(self, status)
end

function BalanceScreen:getPresetButtonText()
    local preset = self.plugin:getSetting("preset", "easy")
    return MenuHelper.DIFFICULTY_LABELS[preset] or preset
end

return BalanceScreen
