--- Created by https://github.com/Mofurka/StarboundTextboxInterface
--- DateTime: 20.03.2026 11:04
--- Please credit if you use or modify this code, thanks!
--- Пожалуста, если вы используете или изменяете этот код, указывайте авторство, спасибо!
-- ─────────────────────────── utf8 ───────────────────────────────────

local function utf8_len(s)
    if not s or s == "" then
        return 0
    end
    return utf8.len(s) or 0
end

local function utf8_charAt(s, ci)
    if ci < 1 or not s or s == "" then
        return ""
    end
    local b = utf8.offset(s, ci)
    if not b then
        return ""
    end
    local nb = utf8.offset(s, ci + 1)
    return nb and s:sub(b, nb - 1) or s:sub(b)
end

local function utf8_sub(s, startChar, endChar)
    if not s or s == "" then
        return ""
    end
    endChar = endChar or utf8_len(s)
    local sb = utf8.offset(s, startChar)
    if not sb then
        return ""
    end
    local eb
    if endChar >= utf8_len(s) then
        eb = #s
    else
        eb = utf8.offset(s, endChar + 1)
        eb = eb and (eb - 1) or #s
    end
    return s:sub(sb, eb)
end

local function isWordChar(ch)
    return #ch > 1 or ch:match("[%w_]") ~= nil
end

-- ─────────────────────────── modules ────────────────────────────

local activeTextboxes = {}

local function hasMod(mods, name)
    if not mods then
        return false
    end
    for _, m in ipairs(mods) do
        if m == name then
            return true
        end
    end
    return false
end

local function clamp(v, lo, hi)
    return math.max(lo, math.min(hi, v))
end

-- ─────────────────────────── constants ───────────────────────────────────────

local DEBUG = false
local PAD = 3
local CARET_BLINK_INTERVAL = 0.5
local CARET_COLOR = { 0, 0, 0, 255 }
local SELECTION_COLOR = { 50, 100, 200, 80 }
local DEFAULT_FONT_SIZE = 8
local DEFAULT_LINE_HEIGHT = 12
local KEY_REPEAT_DELAY = 0.5
local KEY_REPEAT_INTERVAL = 0.05

local function debugMessage(msg, ...)
    if DEBUG then
        sb.logInfo("[tbx.lua] " .. msg, ...)
    end
end

-- ─────────────────────────── lifecycle ─────────────────────────────────

local oldInit, oldUpdate, oldUninit = init, update, uninit

function init()
    if oldInit then
        oldInit()
    end
    Textbox.init()
end

function update(dt)
    if oldUpdate then
        oldUpdate(dt)
    end
    Textbox.update(dt)
end

function uninit()
    if oldUninit then
        oldUninit()
    end
    Textbox.uninit()
end

-- ─────────────────────────── definition ────────────────────────────────

---@class Textbox
Textbox = {
    rect = nil,
    path = nil,
    textCanvas = nil,
    carretCanvas = nil,
    fakeTextbox = nil,
    measureLabelPath = nil,
    textColor = { 255, 255, 255, 255 },
    setupDone = false,
    uuid = nil,
    textDirty = true,
    fontSize = DEFAULT_FONT_SIZE,
    lineHeight = DEFAULT_LINE_HEIGHT,
    lineHeightRatio = DEFAULT_LINE_HEIGHT / DEFAULT_FONT_SIZE,
    wrapWidth = 180,
    text = "",
    charLen = 0,
    cursorPos = 0,
    selAnchor = nil,
    lines = {},
    scrollY = 0,
    caretTimer = 0,
    caretVisible = true,
    focused = false,
    caretColor = CARET_COLOR,
    selectionColor = SELECTION_COLOR,
    cache = {},

    -- callbacks
    onChanged = nil,
    onEnterKey = nil,
    onEscapeKey = nil,

    hint = nil,
    hintColor = { 128, 128, 128, 180 },

    -- my private shit pls dont touch it
    _mouseWasDown = false,
    _mouseLeftHeld = false,
    _shiftHeld = false,
    _ctrlHeld = false,
    _heldKey = nil,
    _heldTimer = 0,

    caretDirty = true
}
Textbox.__index = Textbox

function Textbox.new()
    local self = setmetatable({}, Textbox)
    self.uuid = sb.makeUuid()
    return self
end

-- ─────────────────────────── Setup ───────────────────────────────────────────

---@class TextboxSetupOptions
---@field rect RectI
---@field fontSize number
---@field lineHeight number
---@field hint string
---@field textColor number[] {r, g, b, a}
---@field hintColor number[] {r, g, b, a}
---@field selectionColor number[] {r, g, b, a}
---@field caretColor number[] {r, g, b, a}
---@field onChanged fun(newText: string)
---@field onEnterKey fun()
---@field onEscapeKey fun()


---@public
---@param widgetName string can be nil
---@param options TextboxSetupOptions?
function Textbox:setup(widgetName, options)
    options = options or {}
    local inst = Textbox.new()
    inst.setupDone = true
    inst.fontSize = options.fontSize or DEFAULT_FONT_SIZE
    inst.lineHeight = options.lineHeight or DEFAULT_LINE_HEIGHT
    inst.lineHeightRatio = inst.lineHeight / inst.fontSize
    inst.hint = options.hint
    inst.textColor = options.textColor or inst.textColor
    inst.hintColor = options.hintColor or inst.hintColor
    inst.selectionColor = options.selectionColor or inst.selectionColor
    inst.caretColor = options.caretColor or inst.caretColor
    inst.onChanged = options.onChanged
    inst.onEnterKey = options.onEnterKey
    inst.onEscapeKey = options.onEscapeKey

    local isChild = widgetName:find("%.")
    local lytShort = "__tbx_lyt_" .. inst.uuid

    local rect = options.rect
    if not rect then
        if isChild then
            local sz = widget.getSize(widgetName)
            rect = { 0, 0, sz[1], sz[2] }
        else
            rect = { 0, 0, 200, 200 }
        end
    end

    local lytPath = isChild and (widgetName .. "." .. lytShort) or lytShort
    inst.path = lytPath

        if isChild then
            widget.removeChild(widgetName, lytPath)
        else
            pane.removeWidget(lytPath)
        end


    local lytConfig = { type = "layout", rect = rect, layoutType = "basic" }
    if isChild then
        widget.addChild(widgetName, lytConfig, lytShort)
        debugMessage("Added textbox layout as child: %s -> %s", widgetName, lytShort)
    else
        pane.addWidget(lytConfig, lytShort)
        debugMessage("Added textbox layout: %s", lytShort)
    end

    local sz = widget.getSize(lytPath)
    local canvasRect = { 0, 0, sz[1] - 20, sz[2] - 1 }
    inst.rect = { 0, 0, sz[1], sz[2] }
    inst.wrapWidth = canvasRect[3] - PAD * 2

    local scrollConfig = root.assetJson("/scripts/utils/tbx_scroll_config.json")
    scrollConfig.rect = { rect[1], rect[2], rect[3] + 20, rect[4] }
    widget.addChild(lytPath, scrollConfig, "__tbx_sa_")

    widget.addChild(lytPath, {
        type = "canvas", rect = canvasRect, zlevel = 2,
        captureMouseEvents = false, captureKeyboardEvents = false,
    }, "__tbx_text_canvas")

    local carretName = "__tbx_carret_"
    widget.addChild(lytPath, {
        type = "canvas", rect = canvasRect, zlevel = 3,
        captureMouseEvents = true, captureKeyboardEvents = false,
    }, carretName)

    widget.addChild(lytPath, {
        type = "textbox", position = { -1000, -1000 }, maxWidth = 200,
        textAlign = "left", callback = "null", enterKey = "null",
    }, "__tbx_fake_textbox")
    inst.fakeTextbox = lytPath .. ".__tbx_fake_textbox"

    inst.textCanvas = widget.bindCanvas(lytPath .. ".__tbx_text_canvas")
    inst.carretCanvas = widget.bindCanvas(lytPath .. "." .. carretName)
    inst:_setupMeasureLabel()

    inst:_reflow()
    inst:_invalidateAll()

    debugMessage("Textbox setup complete: %s", sb.print(inst))
    activeTextboxes[inst.uuid] = inst
    debugMessage("Textbox setup complete: %s", inst.uuid)
    return inst

end

-- ─────────────────────────── MISERY (measure) ─────────────────────────────────

---@protected
function Textbox:_setupMeasureLabel()
    local path = "__tbx_measure_label_" .. self.uuid
    pane.addWidget({
        type = "label",
        wrapWidth = 500,
        position = { -1000, -1000 },
        hAnchor = "left",
        vAnchor = "top",
        color = "#00000000",
        fontSize = self.fontSize,
        value = "",
    }, path)
    self.measureLabelPath = path
end

---@protected
function Textbox:_destroyMeasureLabel()
    pane.removeWidget( self.measureLabelPath)
    self.cache = {}
end

---@protected
function Textbox:_measureLetter(letter)
    if not letter or letter == "" then
        return 0
    end

    if not self.cache[self.fontSize] then
        self.cache[self.fontSize] = {}
    end

    if letter == " " then
        return self:_measureSpaceAdvance()
    end

    local cached = self.cache[self.fontSize][letter]
    if cached then
        return cached
    end

    widget.setText(self.measureLabelPath, letter)
    local sz = widget.getSize(self.measureLabelPath)
    local w = (sz and sz[1] or 5)
    if w <= 0 then
        w = 5
    end

    self.cache[self.fontSize][letter] = w
    return w
end

---@protected
function Textbox:_lineTextWidth(text)
    if not text or text == "" then
        return 0
    end
    return self:_measureText(text)
end

---@protected
function Textbox:_measureText(text)
    if not text or text == "" then
        return 0
    end

    if not self.cache[self.fontSize] then
        self.cache[self.fontSize] = {}
    end

    local fc = self.cache[self.fontSize]
    fc.__textWidth = fc.__textWidth or {}

    local cached = fc.__textWidth[text]
    if cached ~= nil then
        return cached
    end

    widget.setText(self.measureLabelPath, text)
    local sz = widget.getSize(self.measureLabelPath)
    local w = (sz and sz[1] or 0)

    fc.__textWidth[text] = w
    return w
end

---@protected
---Вот из-за этой дичи я очень долго мучался
function Textbox:_measureSpaceAdvance()
    if not self.cache[self.fontSize] then
        self.cache[self.fontSize] = {}
    end

    local cached = self.cache[self.fontSize].__spaceAdvance
    if cached then
        return cached
    end

    local w1 = self:_measureText("фф")
    local w2 = self:_measureText("ф ф")

    local adv = w2 - w1
    if adv <= 0 then
        adv = 5
    end

    self.cache[self.fontSize].__spaceAdvance = adv
    return adv
end
-- ─────────────────────────── Reflow ──────────────────────────────

---@protected
function Textbox:_getWrapWidth()
    if self.textCanvas then
        local sz = self.textCanvas:size()
        return math.max(0, sz[1] - PAD * 2)
    end

    return math.max(0, self.wrapWidth or 0)
end

---@protected
function Textbox:_reflow()
    local lines = {}
    self.lines = lines

    local text = self.text or ""
    local maxW = math.max(0, self:_getWrapWidth())

    if self.charLen == 0 then
        lines[1] = {
            startIdx = 1,
            endIdx = 0,
            charXs = {},
            width = 0,
            text = "",
        }
        return
    end

    local lineStartCI = 1
    local lineText = ""
    local charXs = {}
    local lineWidth = 0

    local bi = 1
    for ci = 1, self.charLen do
        local nextBi = utf8.offset(text, 2, bi) or (#text + 1)
        local ch = text:sub(bi, nextBi - 1)

        if ch == "\n" then
            charXs[#charXs + 1] = lineWidth
            lines[#lines + 1] = {
                startIdx = lineStartCI,
                endIdx = ci,
                charXs = charXs,
                width = lineWidth,
                text = lineText .. "\n",
            }

            lineStartCI = ci + 1
            lineText = ""
            charXs = {}
            lineWidth = 0
        else
            local nextText = lineText .. ch
            local nextWidth = self:_lineTextWidth(nextText)

            if nextWidth > maxW and lineText ~= "" then
                lines[#lines + 1] = {
                    startIdx = lineStartCI,
                    endIdx = ci - 1,
                    charXs = charXs,
                    width = lineWidth,
                    text = lineText,
                }

                lineStartCI = ci
                lineText = ch
                charXs = { 0 }
                lineWidth = self:_lineTextWidth(ch)
            else
                charXs[#charXs + 1] = lineWidth
                lineText = nextText
                lineWidth = nextWidth
            end
        end

        bi = nextBi
    end

    if lineStartCI <= self.charLen then
        lines[#lines + 1] = {
            startIdx = lineStartCI,
            endIdx = self.charLen,
            charXs = charXs,
            width = lineWidth,
            text = lineText,
        }
    else
        lines[#lines + 1] = {
            startIdx = lineStartCI,
            endIdx = lineStartCI - 1,
            charXs = {},
            width = 0,
            text = "",
        }
    end
end

-- ─────────────────────────── Cursor ─────────────────────────────────────

---@protected
function Textbox:_hitTestLine(line, x)
    if #line.charXs == 0 then
        return line.startIdx - 1
    end

    local bestPos = line.startIdx - 1
    local base = line.startIdx

    for ci = 1, #line.charXs do
        local x1 = line.charXs[ci]
        local x2 = (ci < #line.charXs) and line.charXs[ci + 1] or line.width
        local mid = x1 + (x2 - x1) * 0.5

        if x >= mid then
            bestPos = base + ci - 1
        else
            break
        end
    end

    if bestPos >= line.startIdx
            and bestPos <= line.endIdx
            and utf8_charAt(self.text, bestPos) == "\n" then
        bestPos = math.max(line.startIdx - 1, bestPos - 1)
    end

    return bestPos
end

---@protected
function Textbox:_cursorToLineX(pos)
    if #self.lines == 0 then
        return 1, 0
    end

    for li, line in ipairs(self.lines) do
        local endsNL = line.endIdx >= line.startIdx
                and utf8_charAt(self.text, line.endIdx) == "\n"
        local endPos = endsNL and (line.endIdx - 1) or line.endIdx

        if pos >= line.startIdx - 1 and pos <= endPos then
            local localIdx = pos - (line.startIdx - 1)

            if localIdx <= 0 then
                return li, 0
            end

            if localIdx < #line.charXs then
                return li, line.charXs[localIdx + 1]
            end

            return li, line.width
        end
    end

    return #self.lines, self.lines[#self.lines].width
end

---@protected
function Textbox:_xyToCursor(clickX, clickY)
    local sz = self.carretCanvas:size()
    local lineIdx = clamp(
            math.floor((sz[2] - PAD + self.scrollY - clickY) / self.lineHeight) + 1,
            1, #self.lines)
    local line = self.lines[lineIdx]
    return line and self:_hitTestLine(line, clickX - PAD) or 0
end

---@protected
function Textbox:_xToLinePos(lineIdx, targetX)
    local line = self.lines[lineIdx]
    return line and self:_hitTestLine(line, targetX) or self.cursorPos
end

-- ─────────────────────────── Selection ────────────────────────────────────────
---@protected
function Textbox:_getSelRange()
    if self.selAnchor == nil or self.selAnchor == self.cursorPos then
        return nil, nil
    end
    local a, b = self.selAnchor, self.cursorPos
    if a > b then
        return b, a
    end
    return a, b
end
---@protected
function Textbox:_getSelectedText()
    local from, to = self:_getSelRange()
    if not from then
        return ""
    end
    return utf8_sub(self.text, from + 1, to)
end

-- ─────────────────────────── Text editing ────────────────────────────────────
---@protected
function Textbox:_splice(from, to)
    local before = from > 0 and utf8_sub(self.text, 1, from) or ""
    self.text = before .. (utf8_sub(self.text, to + 1) or "")
end
---@protected
function Textbox:_deleteSelection()
    local from, to = self:_getSelRange()
    if not from then
        return false
    end
    self:_splice(from, to)
    self.cursorPos = from
    self.selAnchor = nil
    return true
end
---@protected
function Textbox:_insertText(str)
    if not str or str == "" then
        return
    end
    self:_deleteSelection()
    local before = self.cursorPos > 0 and utf8_sub(self.text, 1, self.cursorPos) or ""
    self.text = before .. str .. (utf8_sub(self.text, self.cursorPos + 1) or "")
    self.cursorPos = self.cursorPos + utf8_len(str)
    self.selAnchor = nil
    self:_onTextChanged()
end
---@protected
function Textbox:_deleteBack()
    if self:_deleteSelection() then
        self:_onTextChanged();
        return
    end
    if self.cursorPos <= 0 then
        return
    end
    self:_splice(self.cursorPos - 1, self.cursorPos)
    self.cursorPos = self.cursorPos - 1
    self:_onTextChanged()
end
---@protected
function Textbox:_deleteForward()
    if self:_deleteSelection() then
        self:_onTextChanged();
        return
    end
    if self.cursorPos >= self.charLen then
        return
    end
    self:_splice(self.cursorPos, self.cursorPos + 1)
    self:_onTextChanged()
end

-- ─────────────────────────── Word ─────────────────────────────────
---@protected
function Textbox:_wordBoundaryLeft(pos)
    local text = self.text
    while pos > 0 and not isWordChar(utf8_charAt(text, pos)) do
        pos = pos - 1
    end
    while pos > 0 and isWordChar(utf8_charAt(text, pos)) do
        pos = pos - 1
    end
    return pos
end
---@protected
function Textbox:_wordBoundaryRight(pos)
    local text, len = self.text, self.charLen
    while pos < len and not isWordChar(utf8_charAt(text, pos + 1)) do
        pos = pos + 1
    end
    while pos < len and isWordChar(utf8_charAt(text, pos + 1)) do
        pos = pos + 1
    end
    return pos
end
---@protected
function Textbox:_deleteWordBack()
    if self:_deleteSelection() then
        self:_onTextChanged();
        return
    end
    if self.cursorPos <= 0 then
        return
    end
    local newPos = self:_wordBoundaryLeft(self.cursorPos)
    if newPos < self.cursorPos then
        self:_splice(newPos, self.cursorPos)
        self.cursorPos = newPos
        self:_onTextChanged()
    end
end
---@protected
function Textbox:_deleteWordForward()
    if self:_deleteSelection() then
        self:_onTextChanged();
        return
    end
    if self.cursorPos >= self.charLen then
        return
    end
    local newPos = self:_wordBoundaryRight(self.cursorPos)
    if newPos > self.cursorPos then
        self:_splice(self.cursorPos, newPos)
        self:_onTextChanged()
    end
end
---@protected
function Textbox:_onTextChanged()
    self.charLen = utf8_len(self.text)
    self.cursorPos = clamp(self.cursorPos, 0, self.charLen)

    if self.selAnchor ~= nil then
        self.selAnchor = clamp(self.selAnchor, 0, self.charLen)
    end

    self:_invalidateAll()
    self:_reflow()
    self:_ensureCursorVisible()
    self:_resetBlink()

    if self.onChanged then
        self.onChanged(self.text)
    end
end
---@protected
function Textbox:_resetBlink()
    self.caretTimer = 0
    self.caretVisible = true
    self:_invalidateCaret()
end

-- ─────────────────────────── navi ───────────────────────────────
---@protected
function Textbox:_finishMove(shift)
    if not shift then
        self.selAnchor = nil
    end
    self:_resetBlink()
    self:_ensureCursorVisible()
    self:_invalidateCaret()
end
---@protected
function Textbox:_moveCursorLeft(shift)
    local from = self:_getSelRange()
    if not shift and from then
        self.cursorPos = from
        self:_finishMove(false);
        return
    end
    if shift and self.selAnchor == nil then
        self.selAnchor = self.cursorPos
    end
    if self.cursorPos > 0 then
        self.cursorPos = self.cursorPos - 1
    end
    self:_finishMove(shift)
end
---@protected
function Textbox:_moveCursorRight(shift)
    local _, to = self:_getSelRange()
    if not shift and to then
        self.cursorPos = to
        self:_finishMove(false);
        return
    end
    if shift and self.selAnchor == nil then
        self.selAnchor = self.cursorPos
    end
    if self.cursorPos < self.charLen then
        self.cursorPos = self.cursorPos + 1
    end
    self:_finishMove(shift)
end
---@protected
function Textbox:_moveCursorUp(shift)
    if shift and self.selAnchor == nil then
        self.selAnchor = self.cursorPos
    end
    local li, x = self:_cursorToLineX(self.cursorPos)
    self.cursorPos = li <= 1 and 0 or self:_xToLinePos(li - 1, x)
    self:_finishMove(shift)
end
---@protected
function Textbox:_moveCursorDown(shift)
    if shift and self.selAnchor == nil then
        self.selAnchor = self.cursorPos
    end
    local li, x = self:_cursorToLineX(self.cursorPos)
    self.cursorPos = li >= #self.lines and self.charLen or self:_xToLinePos(li + 1, x)
    self:_finishMove(shift)
end
---@protected
function Textbox:_moveCursorHome(shift)
    if shift and self.selAnchor == nil then
        self.selAnchor = self.cursorPos
    end
    local li = self:_cursorToLineX(self.cursorPos)
    local line = self.lines[li]
    if line then
        self.cursorPos = line.startIdx - 1
    end
    self:_finishMove(shift)
end
---@protected
function Textbox:_moveCursorEnd(shift)
    if shift and self.selAnchor == nil then
        self.selAnchor = self.cursorPos
    end
    local li = self:_cursorToLineX(self.cursorPos)
    local line = self.lines[li]
    if line then
        local ep = line.endIdx
        if ep >= line.startIdx and utf8_charAt(self.text, ep) == "\n" then
            ep = math.max(line.startIdx - 1, ep - 1)
        end
        self.cursorPos = ep
    end
    self:_finishMove(shift)
end
---@protected
function Textbox:_moveCursorWordLeft(shift)
    if shift and self.selAnchor == nil then
        self.selAnchor = self.cursorPos
    end
    self.cursorPos = self:_wordBoundaryLeft(self.cursorPos)
    self:_finishMove(shift)
end
---@protected
function Textbox:_moveCursorWordRight(shift)
    if shift and self.selAnchor == nil then
        self.selAnchor = self.cursorPos
    end
    self.cursorPos = self:_wordBoundaryRight(self.cursorPos)
    self:_finishMove(shift)
end

-- ─────────────────────────── scoll ──────────────────────────────────────────
---@protected
function Textbox:_getContentHeight()
    return #self.lines * self.lineHeight
end
---@protected
function Textbox:_getViewHeight()
    return self.carretCanvas and self.carretCanvas:size()[2] or 100
end
---@protected
function Textbox:_getMaxScroll()
    return math.max(0, self:_getContentHeight() - self:_getViewHeight() + PAD * 2)
end

---@protected
function Textbox:_getVisibleLineRange()
    local total = #self.lines
    if total == 0 then
        return 1, 1
    end

    local viewH = self:_getViewHeight()
    local first = math.floor(self.scrollY / self.lineHeight) + 1
    local last = math.ceil((self.scrollY + viewH) / self.lineHeight) + 1

    first = clamp(first, 1, total)
    last = clamp(last, first, total)
    return first, last
end

---@protected
function Textbox:_invalidateText()
    self.textDirty = true
    self.caretDirty = true
end

---@protected
function Textbox:_invalidateCaret()
    self.caretDirty = true
end

---@protected
function Textbox:_invalidateAll()
    self.textDirty = true
    self.caretDirty = true
end

---@protected
function Textbox:_ensureCursorVisible()
    local li = self:_cursorToLineX(self.cursorPos)
    local viewH = self:_getViewHeight()
    local cursorTop = (li - 1) * self.lineHeight
    local cursorBot = cursorTop + self.lineHeight
    local visBot = self.scrollY + viewH - PAD * 2

    local old = self.scrollY
    if cursorTop < self.scrollY then
        self.scrollY = cursorTop
    elseif cursorBot > visBot then
        self.scrollY = cursorBot - (viewH - PAD * 2)
    end
    self.scrollY = clamp(self.scrollY, 0, self:_getMaxScroll())
    if self.scrollY ~= old then
        self:_invalidateAll()
    else
        self:_invalidateCaret()
    end
end

-- ─────────────────────────── helpers ────────────────────────────────

function Textbox.showClipboardUnavailable()
    local message = (
            "Due to safety restrictions, OpenStarbound does not allow access to the system clipboard.\n" ..
            "In your Starbound folder -> storage -> starbound.config, set alwaysAllowClipboard to true and restart the game.\n" ..
            "\"safe\": {\n" ..
            "    \"alwaysAllowClipboard\": true\n" ..
            "}"
    )
    Textbox.showWarningPopup("Clipboard Access Unavailable", "Please change your settings to allow clipboard access", message)
end


function Textbox.showWarningPopup(title, subtitle, message)
    local config = {
        title = title,
        subtitle = subtitle,
        message = message,
    }
    player.interact("showPopup", config)
end

-- ─────────────────────────── prosessing ────────────────────────────────
---@protected
function Textbox:_processInput(dt)
    self.caretTimer = self.caretTimer + dt
    if self.caretTimer >= CARET_BLINK_INTERVAL then
        self.caretTimer = self.caretTimer - CARET_BLINK_INTERVAL
        self.caretVisible = not self.caretVisible
        self:_invalidateCaret()
    end

    local events = input.events() or {}

    for _, ev in ipairs(events) do
        local data = ev.data
        if ev.type == "KeyDown" and data then
            local key = data.key
            if key == "LShift" or key == "RShift" then
                self._shiftHeld = true
            end
            if key == "LCtrl" or key == "RCtrl" then
                self._ctrlHeld = true
            end
            if key == "Backspace" or key == "Delete" then
                self._heldKey = key;
                self._heldTimer = 0
            end
        elseif ev.type == "KeyUp" and data then
            local key = data.key
            if key == "LShift" or key == "RShift" then
                self._shiftHeld = false
            end
            if key == "LCtrl" or key == "RCtrl" then
                self._ctrlHeld = false
            end
            if key == self._heldKey then
                self._heldKey = nil
            end
        end
    end

    self:_processMouseEvents(events)
    if not self.focused then
        return
    end

    if self._heldKey then
        self._heldTimer = self._heldTimer + dt
        if self._heldTimer >= KEY_REPEAT_DELAY then
            local elapsed = self._heldTimer - KEY_REPEAT_DELAY
            if math.floor(elapsed / KEY_REPEAT_INTERVAL) > 0 then
                self:_doDelete(self._heldKey)
                self._heldTimer = KEY_REPEAT_DELAY + (elapsed % KEY_REPEAT_INTERVAL)
            end
        end
    end

    self:_pollFakeTextbox()
    self:_processKeys(events)
end
---@protected
function Textbox:_doDelete(key)
    if key == "Backspace" then
        if self._ctrlHeld then
            self:_deleteWordBack()
        else
            self:_deleteBack()
        end
    else
        if self._ctrlHeld then
            self:_deleteWordForward()
        else
            self:_deleteForward()
        end
    end
end
---@protected
function Textbox:_processMouseEvents(events)
    if not self.carretCanvas then
        return
    end

    for _, ev in ipairs(events) do
        if ev.type == "MouseWheel" and ev.data and self.focused then
            local mp = self.carretCanvas:mousePosition()
            local sz = self.carretCanvas:size()
            if mp[1] >= 0 and mp[1] <= sz[1] and mp[2] >= 0 and mp[2] <= sz[2] then
                self.scrollY = clamp(
                        self.scrollY - ev.data.mouseWheel * self.lineHeight * 3,
                        0, self:_getMaxScroll())
                self.textDirty = true
            end

        elseif ev.type == "MouseButtonDown" and ev.data
                and ev.data.mouseButton == "MouseLeft" then
            self._mouseLeftHeld = true
            local mp = self.carretCanvas:mousePosition()
            local sz = self.carretCanvas:size()
            if mp[1] >= 0 and mp[1] <= sz[1] and mp[2] >= 0 and mp[2] <= sz[2] then
                self:focus()
                local pos = self:_xyToCursor(mp[1], mp[2])
                if self._shiftHeld then
                    if self.selAnchor == nil then
                        self.selAnchor = self.cursorPos
                    end
                else
                    self.selAnchor = pos
                end
                self.cursorPos = pos
                self:_resetBlink()
                self._mouseWasDown = true
            else
                self:blur()
                self._mouseWasDown = false
            end

        elseif ev.type == "MouseButtonUp" and ev.data
                and ev.data.mouseButton == "MouseLeft" then
            self._mouseLeftHeld = false
            self._mouseWasDown = false
        end
    end

    if self._mouseLeftHeld and self._mouseWasDown and self.focused then
        local mp = self.carretCanvas:mousePosition()
        local sz = self.carretCanvas:size()

        if mp[1] >= 0 and mp[1] <= sz[1] and mp[2] >= 0 and mp[2] <= sz[2] then
            local pos = self:_xyToCursor(mp[1], mp[2])
            if pos ~= self.cursorPos then
                self.cursorPos = pos
                self:_resetBlink()
                self:_ensureCursorVisible()
            end
        end
    end
end

---@protected
function Textbox:_pollFakeTextbox()
    if not self.fakeTextbox then
        return
    end
    local txt = widget.getText(self.fakeTextbox)
    if txt and txt ~= "" then
        if not txt:find("\n") then
            self:_insertText(txt)
        end
        widget.setText(self.fakeTextbox, "")
    end
end

---@protected
function Textbox:_processKeys(events)
    for _, ev in ipairs(events) do
        if ev.type == "KeyDown" and ev.data then
            local key = ev.data.key
            local mods = ev.data.mods or {}
            local shift = hasMod(mods, "LShift") or hasMod(mods, "RShift")
            local ctrl = hasMod(mods, "LCtrl") or hasMod(mods, "RCtrl")

            if key == "Backspace" then
                if ctrl then
                    self:_deleteWordBack()
                else
                    self:_deleteBack()
                end
            elseif key == "Del" then
                if ctrl then
                    self:_deleteWordForward()
                else
                    self:_deleteForward()
                end
            elseif key == "Return" then
                if shift then
                    self:_insertText("\n")
                elseif self.onEnterKey then
                    self.onEnterKey()
                end
            elseif key == "Escape" then
                if self.onEscapeKey then
                    self.onEscapeKey()
                end
            elseif key == "Tab" then
                self:_insertText(self.tabSpaces or "  ")
            elseif key == "Left" then
                if ctrl then
                    self:_moveCursorWordLeft(shift)
                else
                    self:_moveCursorLeft(shift)
                end
            elseif key == "Right" then
                if ctrl then
                    self:_moveCursorWordRight(shift)
                else
                    self:_moveCursorRight(shift)
                end
            elseif key == "Up" then
                self:_moveCursorUp(shift)
            elseif key == "Down" then
                self:_moveCursorDown(shift)
            elseif key == "Home" then
                self:_moveCursorHome(shift)
            elseif key == "End" then
                self:_moveCursorEnd(shift)
            elseif ctrl and key == "A" then
                self.selAnchor = 0;
                self.cursorPos = self.charLen;
                self:_resetBlink()
            elseif ctrl and key == "C" then
                local sel = self:_getSelectedText()
                if sel ~= "" then
                    clipboard.setText(sel)
                end
            elseif ctrl and key == "X" then
                local sel = self:_getSelectedText()
                if sel ~= "" then
                    clipboard.setText(sel)
                    self:_deleteSelection();
                    self:_onTextChanged()
                end
            elseif ctrl and key == "V" then
                if not clipboard.available() then
                    Textbox.showClipboardUnavailable()
                    return
                end
                if clipboard.hasText() then
                    local t = clipboard.getText()
                    if t:find("\n") then
                        t = t:gsub("\r", "")
                        if t and t ~= "" then
                            self:_insertText(t)
                        end
                    end
                end
            end
        end
    end
end


-- ─────────────────────────── drawin ─────────────────────────────────────────
---@protected
function Textbox:_drawText()
    local canvas = self.textCanvas
    if not canvas then
        return
    end
    canvas:clear()

    local canvasH = canvas:size()[2]
    local baseY = canvasH - PAD + self.scrollY
    local lh = self.lineHeight
    local fs, color = self.fontSize, self.textColor

    local drawParams = {
        position = { PAD, 0 },
        horizontalAnchor = "left",
        verticalAnchor = "top",
    }

    if self.charLen == 0 and self.hint and self.hint ~= "" and not self.focused then
        drawParams.position[2] = baseY
        canvas:drawText(self.hint, drawParams, fs, self.hintColor)
    else
        local fromLi, toLi = self:_getVisibleLineRange()
        for li = fromLi, toLi do
            local line = self.lines[li]
            if line then
                local top = baseY - (li - 1) * lh
                local lineText = line.text or ""
                if lineText ~= "" and lineText ~= "\n" then
                    if lineText:sub(-1) == "\n" then
                        lineText = lineText:sub(1, -2)
                    end
                    drawParams.position[2] = top
                    canvas:drawText(lineText, drawParams, fs, color)
                end
            end
        end
    end

    self.textDirty = false
end

---@protected
function Textbox:_drawCaret()
    local canvas = self.carretCanvas
    if not canvas then
        return
    end
    canvas:clear()
    if not self.focused then
        self.caretDirty = false
        return
    end

    local canvasH = canvas:size()[2]
    local baseY = canvasH - PAD + self.scrollY
    local lh = self.lineHeight
    local firstVisible, lastVisible = self:_getVisibleLineRange()

    local selFrom, selTo = self:_getSelRange()
    if selFrom then
        local fromLi, fromX = self:_cursorToLineX(selFrom)
        local toLi, toX = self:_cursorToLineX(selTo)
        local drawFrom = math.max(firstVisible, fromLi)
        local drawTo = math.min(lastVisible, toLi)

        for li = drawFrom, drawTo do
            local line = self.lines[li]
            if line then
                local top = baseY - (li - 1) * lh
                local bot = top - lh
                local x1 = li == fromLi and (PAD + fromX) or PAD
                local x2 = li == toLi and (PAD + toX) or (PAD + line.width)
                if x2 > x1 then
                    canvas:drawRect({ x1, bot + 2, x2, top + 2 }, self.selectionColor)
                end
            end
        end
    end

    if self.caretVisible then
        local li, cx = self:_cursorToLineX(self.cursorPos)
        if li >= firstVisible and li <= lastVisible then
            local top = baseY - (li - 1) * lh
            local bot = top - lh
            local x = PAD + cx
            canvas:drawLine({ x, bot + 5 }, { x, top }, self.caretColor, 1)
        end
    end

    self.caretDirty = false
end

---@protected
function Textbox:_draw()
    if self.textDirty then
        self:_drawText()
    end
    if self.caretDirty then
        self:_drawCaret()
    end
end

-- ─────────────────────────── Public API ──────────────────────────────────────

---@public
---@return string
function Textbox:getText()
    return self.text
end

---@public
---@overload fun(text: string)
---@overload fun(text: string[])
function Textbox:setText(text)
    if type(text) == "table" then
        text = table.concat(text, "\n")
    end
    self.text = text or ""
    self.charLen = utf8_len(self.text)
    self.cursorPos = self.charLen
    self.selAnchor = nil
    self.scrollY = 0
    self:_invalidateAll()
    self:_reflow()
    self:_ensureCursorVisible()
    self:_resetBlink()
end

---@public
---@return boolean
function Textbox:focus()
    self.focused = true
    widget.focus(self.fakeTextbox)
    widget.setText(self.fakeTextbox, "")
    self:_resetBlink()
    self:_invalidateAll()
end

---@public
---@return boolean
function Textbox:blur()
    self.focused = false
    widget.blur(self.fakeTextbox)
    self.selAnchor = nil
    self:_invalidateAll()
end

---@public
---@return boolean
function Textbox:hasFocus()
    return self.focused
end

---@public
function Textbox:clear()
    self.text = ""
    self.charLen = 0
    self.cursorPos = 0
    self.selAnchor = nil
    self.scrollY = 0
    self:_invalidateAll()
    self:_reflow()
    if self.textCanvas then
        self.textCanvas:clear()
    end
    if self.carretCanvas then
        self.carretCanvas:clear()
    end
end

---@public
---@param fn fun(newText: string)
function Textbox:setOnChanged(fn)
    self.onChanged = fn
end

---@public
---@param fn fun()
function Textbox:setOnEnterKey(fn)
    self.onEnterKey = fn
end

---@public
---@param fn fun()
function Textbox:setOnEscapeKey(fn)
    self.onEscapeKey = fn
end

---@public
---@param enabled boolean
function Textbox.setDebug(enabled)
    DEBUG = enabled
end

---@public
---@return string
function Textbox:destroy()
    self:_cleanup()
    local uuid = self.uuid
    activeTextboxes[uuid] = nil
    return uuid
end

---@protected
function Textbox:_cleanup()
    self:clear()
    self:_destroyMeasureLabel()
    pane.removeWidget(self.path)
end

-- ─────────────────────────── Getters/Setters ─────────────────────────────────

---@public
---@return number
function Textbox:getCursorPos()
    return self.cursorPos
end

---@public
---@param pos number
function Textbox:setCursorPos(pos)
    self.cursorPos = clamp(pos, 0, self.charLen)
    self.selAnchor = nil
    self:_ensureCursorVisible()
    self:_resetBlink()
    self:_invalidateCaret()
end

---@public
---@param text string
function Textbox:setTabInsertText(text)
    self.tabSpaces = text
end

---@public
---@return number
function Textbox:getLineCount()
    return #self.lines
end

---@public
---@return number
function Textbox:getScroll()
    return self.scrollY
end

---@public
---@param scrollY number
function Textbox:setScroll(scrollY)
    local old = self.scrollY
    self.scrollY = clamp(scrollY, 0, self:_getMaxScroll())
    if self.scrollY ~= old then
        self:_invalidateAll()
    end
end

---@public
---@param color number[] {r, g, b, a}
function Textbox:setCaretColor(color)
    self.caretColor = color
    self:_invalidateCaret()
end

---@public
---@param color number[] {r, g, b, a}
function Textbox:setSelectionColor(color)
    self.selectionColor = color
    self:_invalidateCaret()
end

---@public
---@param color number[] {r, g, b, a}
function Textbox:setTextColor(color)
    self.textColor = color
    self:_invalidateText()
end

---@public
---@param color number[] {r, g, b, a}
function Textbox:setHintColor(color)
    self.hintColor = color
    self:_invalidateCaret()
end

---@public
---@param size number
function Textbox:setFontSize(size)
    if self.fontSize == size then
        return
    end
    self.fontSize = size
    self.lineHeight = size * self.lineHeightRatio
    self:_destroyMeasureLabel()
    self:_setupMeasureLabel()
    self:_invalidateAll()
    self:_reflow()
    self:_ensureCursorVisible()
end

---@public
---@return number
function Textbox:getFontSize()
    return self.fontSize
end

---@public
---@param hint string
function Textbox:setHint(hint)
    self.hint = hint
    self:_invalidateText()
end

---@public
---@return string
function Textbox:getHint()
    return self.hint
end

---@public
---@param color number[] {r, g, b, a}
function Textbox:setHintColor(color)
    self.hintColor = color
    self:_invalidateText()
end

-- ─────────────────────────── lifecyle ────────────────────────────────

function Textbox.init()
    assert(pane, "Textbox: pane API not available. Include this script in an interface.")
end

function Textbox.update(dt)
    for _, tbx in pairs(activeTextboxes) do
        if tbx.setupDone then
            tbx:_processInput(dt);
            tbx:_draw()
        end
    end
end

function Textbox.uninit()
    for _, tbx in pairs(activeTextboxes) do
        tbx:_cleanup()
    end
    activeTextboxes = {}
end

