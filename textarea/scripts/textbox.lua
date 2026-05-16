--- Created by https://github.com/Mofurka/StarboundTextboxInterface
--- DateTime: 20.03.2026 11:04
--- Please credit if you use or modify this code, thanks!
--- Пожалуста, если вы используете или изменяете этот код, указывайте авторство, спасибо!
require("/scripts/vec2.lua")
require("/scripts/rect.lua")
require("/interface/StarboundTextboxInterface/scipts/utf8/utf8.lua")

-- ─────────────────────────── modules ────────────────────────────

---@type table<string, Textbox>
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

local WIDGET_SHORTS = {
    textCanvas = "_",
    carretCanvas = "__",
    fakeTextbox = "___",
    scrollArea = "____",
    lyt = "_", -- this comes with uuid, so it won't conflict between instances
    measureLabel = "_", -- this comes with uuid, so it won't conflict between instances
}

local CURSOR_AFFINITY = {
    forward = 1,
    backward = 0
}

local function dotWidget(name)
    return "." .. name
end

local DEBUG = false
local PAD = 2
local CARET_BLINK_INTERVAL = 0.5
local CARET_COLOR = { 0, 0, 0, 255 }
local SELECTION_COLOR = { 50, 100, 200, 80 }
local KEY_REPEAT_DELAY = 0.5
local KEY_REPEAT_INTERVAL = 0.05
local DOUBLE_CLICK_INTERVAL = 0.4
local DOUBLE_CLICK_MAX_DISTANCE = 4
local FAKE_TEXTBOX_COROUTINE_THRESHOLD = 60000
local FAKE_TEXTBOX_COROUTINE_CHUNK_SIZE = 30000

local REPEATABLE_KEYS = {
    Backspace = true,
    Del = true,
    Left = true,
    Right = true,
    Up = true,
    Down = true,
    Z = true,
    Y = true
}

local KEYS = {
    Backspace = "Backspace",
    Escape = "Esc",
    Delete = "Del",
    Return = "Return",
    Left = "Left",
    Right = "Right",
    Up = "Up",
    Down = "Down",
    Home = "Home",
    End = "End",
    Enter = "Enter",
    Tab = "Tab",
    LCtrl = "LCtrl",
    RCtrl = "RCtrl",
    LShift = "LShift",
    RShift = "RShift",
    A = "A",
    C = "C",
    V = "V",
    X = "X",
    Z = "Z",
    Y = "Y",
    U = "U",
}

local ACTION_TYPES = {
    insert = "insert",
    backspace = "backspace",
    delete = "delete",
    paste = "paste",
    selection = "selection",
    other = "other",
}

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
    parrentWidgetPath = nil,
    path = nil,
    textCanvas = nil,
    textCanvasPath = nil,
    carretCanvas = nil,
    carretCanvasPath = nil,
    fakeTextbox = nil,
    fakeTextboxPath = nil,
    scrollAreaPath = nil,
    measureLabelPath = nil,
    textColor = { 255, 255, 255, 255 },
    setupDone = false,
    uuid = nil,
    textDirty = true,
    fontSize = 8,
    lineHeight = 12,
    lineSpacing = 0,
    lineHeightRatio = 0,
    wrapWidth = 180,
    text = "",
    charLen = 0,
    cursorPos = 0,
    selAnchor = nil,
    lines = {},
    scrollY = 0,
    caretTimer = 0,
    tabSpaces = "  ",
    caretVisible = true,
    focused = false,
    caretColor = CARET_COLOR,
    selectionColor = SELECTION_COLOR,
    textOffsetY = 0,
    unfocusOnClickOutside = true,
    cache = {},

    -- undo/redo history
    undoHistory = {},
    redoHistory = {},
    _lastSavedState = nil,
    _lastActionType = nil,
    _lastActionTime = 0,
    _actionGroupTimeThreshold = 0.5,

    -- callbacks
    onChanged = nil,
    onEnterKey = nil,
    onEscapeKey = nil,

    hint = nil,
    hintColor = { 128, 128, 128, 180 },

    -- auto size
    minHeight = nil,
    maxHeight = nil,
    onSizeChange = nil,
    currentHeight = nil,

    -- my private shit pls dont touch it
    _mouseWasDown = false,
    _mouseLeftHeld = false,
    _doubleClickTimer = 0,
    _clickCount = 0,
    _mouseDragAnchor = nil,
    _lastClickMouse = nil,
    _shiftHeld = false,
    _ctrlHeld = false,
    _heldKey = nil,
    _heldTimer = 0,
    _ignoreInputFrame = false,
    _cursorAffinity = CURSOR_AFFINITY.forward,
    _lineHeightExplicit = nil,
    _fakeTextboxPasteCoroutine = nil,


    -- Global to local cords
    _screenOffset = { 0, 0 },
    _isChild = false,
    _firstParent = nil,
    _childrenRect = { 0, 0 },
    _paneFeature = {},

    caretDirty = true
}
Textbox.__index = Textbox

---@return Textbox
function Textbox.new()
    local self = setmetatable({}, Textbox)
    self.uuid = sb.makeUuid()
    return self
end

-- ─────────────────────────── Setup ───────────────────────────────────────────

---@class TextboxSetupOptions
---@field rect? RectI
---@field fontSize number?
---@field lineHeight number?
---@field lineSpacing number?
---@field hint string?
---@field textColor number[]? {r, g, b, a}
---@field hintColor number[]? {r, g, b, a}
---@field selectionColor number[]? {r, g, b, a}
---@field caretColor number[]? {r, g, b, a}
---@field onChanged fun(newText: string)?
---@field onEnterKey fun()?
---@field onEscapeKey fun()?
---@field tabInsertText string?
---@field maxHeight number?
---@field onSizeChange fun(newHeight: number[] {width, height})?
---@field screenOffset number[]? {x, y} - relative to the widget rect, for example {0, -10} would move the text 10 pixels up from the bottom of the widget
---@field unfocusOnClickOutside boolean? - whether the textbox should lose focus when the user clicks outside of it. Default is true.
---@field textFont string?

---@public
---@param widgetName string can be nil
---@param options TextboxSetupOptions?
function Textbox:setup(widgetName, options)
    options = options or {}
    local inst = Textbox.new()
    inst.setupDone = true
    inst._lineHeightExplicit = options.lineHeight ~= nil
    inst.fontSize = options.fontSize or inst.fontSize
    inst.lineHeight = options.lineHeight or inst.lineHeight
    inst.lineSpacing = math.max(0, math.floor((options.lineSpacing or inst.lineSpacing) + 0.5))
    inst.lineHeightRatio = inst.lineHeight / inst.fontSize
    inst.onChanged = options.onChanged
    inst.onEnterKey = options.onEnterKey
    inst.onEscapeKey = options.onEscapeKey
    inst.maxHeight = options.maxHeight
    inst.onSizeChange = options.onSizeChange
    inst.tabSpaces = options.tabInsertText or inst.tabSpaces
    inst.verticalAlign = options.verticalAlign or "bottom"
    inst.textOffsetY = options.textOffsetY or 0
    inst.parrentWidgetPath = widgetName
    inst.caretColor = options.caretColor or CARET_COLOR
    inst._screenOffset = options.screenOffset or inst._screenOffset
    inst.unfocusOnClickOutside = options.unfocusOnClickOutside
    inst.textFont = options.textFont or "hobo"
    inst._paneFeature = Textbox.findPaneFeature()

    if widgetName:find("%.") then
        inst._isChild = true
    end

    local lytShort = WIDGET_SHORTS.lyt .. inst.uuid

    local rect = options.rect
    if not rect then
        local sz = widget.getSize(widgetName)
        rect = { 0, 0, sz[1], sz[2] }
    end
    inst._layoutOffset = { rect[1], rect[2] }

    local lytPath = widgetName .. "." .. lytShort
    inst.path = lytPath

    -- Store the UUID in the parent widget
    local parentWidgetData = widget.getData(widgetName) or {}
    if parentWidgetData.__tbx_uuid then
        widget.removeChild(widgetName, WIDGET_SHORTS.lyt .. parentWidgetData.__tbx_uuid)
    end
    parentWidgetData.__tbx_uuid = inst.uuid
    widget.setData(widgetName, parentWidgetData)

    local lytConfig = { type = "layout", rect = rect, layoutType = "basic" }
    widget.addChild(widgetName, lytConfig, lytShort)

    local canvasRect = { 0, 0, rect[3], rect[4] - 1 }
    inst.rect = { 0, 0, rect[3], rect[4] }


    -- Scroll arena
    local scrollConfig = root.assetJson("/interface/StarboundTextboxInterface/textarea/tbx_scroll_config.json")
    scrollConfig.rect = { rect[1], rect[2], rect[3] + 20, rect[4] }
    widget.addChild(lytPath, scrollConfig, WIDGET_SHORTS.scrollArea)
    inst.scrollAreaPath = lytPath .. dotWidget(WIDGET_SHORTS.scrollArea)

    -- Text canvas
    widget.addChild(lytPath, {
        type = "canvas", rect = canvasRect, zlevel = 2,
        captureMouseEvents = false, captureKeyboardEvents = false,
    }, WIDGET_SHORTS.textCanvas)
    inst.textCanvasPath = lytPath .. dotWidget(WIDGET_SHORTS.textCanvas)

    -- Carret canvas
    widget.addChild(lytPath, {
        type = "canvas", rect = canvasRect, zlevel = 3,
        captureMouseEvents = true, captureKeyboardEvents = false,
    }, WIDGET_SHORTS.carretCanvas)
    inst.carretCanvasPath = lytPath .. dotWidget(WIDGET_SHORTS.carretCanvas)

    -- Fake textbox for input capture
    widget.addChild(lytPath, {
        type = "textbox", position = { -1000, -1000 }, maxWidth = 200,
        textAlign = "left", callback = "null", enterKey = "null",
        escapeKey = "null", regex = "[\\s\\S]*"
    }, WIDGET_SHORTS.fakeTextbox)
    inst.fakeTextbox = lytPath .. dotWidget(WIDGET_SHORTS.fakeTextbox)

    -- Bind canvases
    inst.textCanvas = widget.bindCanvas(inst.textCanvasPath)
    inst.carretCanvas = widget.bindCanvas(inst.carretCanvasPath)

    inst:_setupMeasureLabel()

    if not inst._lineHeightExplicit then
        local metrics = inst:_measureFontMetrics()
        inst.lineHeight = inst:_resolveAutoLineHeight(metrics)
    else
        inst.lineHeight = math.floor(inst.lineHeight + 0.5)
    end

    local width = rect[3] - rect[1]
    local height = rect[4] - rect[2]
    local canvasSize = { width, height }

    inst.currentHeight = height
    inst.minHeight = height

    widget.setSize(inst.path, { width, height })
    widget.setSize(inst.textCanvasPath, canvasSize)
    widget.setSize(inst.carretCanvasPath, canvasSize)
    widget.setSize(inst.scrollAreaPath, { width + 20, height })

    inst.rect = { 0, 0, width, height }
    inst.wrapWidth = width - PAD * 2

    inst:_reflow()
    inst.scrollY = 0
    inst:_invalidateAll()
    inst:_saveInitialState()

    debugMessage("Textbox setup complete: %s", sb.print(inst))
    activeTextboxes[inst.uuid] = inst
    return inst
end

-- ─────────────────────────── MISERY (measure) ─────────────────────────────────
---@protected
function Textbox:_resolveAutoLineHeight(metrics)
    local size = self.fontSize
    local textH = metrics.textHeight

    local extraGap = math.max(1, math.floor(size * 0.12 + 0.5))
    return math.max(
            textH + extraGap,
            math.floor(size * 1.15 + 0.5)
    )
end
---@protected
function Textbox:_getVerticalInset(metrics)
    return math.max(0, math.floor((self.lineHeight - metrics.textHeight) / 2))
end
---@protected
function Textbox:_measureFontMetrics()
    if not self.cache[self.fontSize] then
        self.cache[self.fontSize] = {}
    end

    local cached = self.cache[self.fontSize].__fontMetrics
    if cached then
        return cached
    end

    widget.setText(self.measureLabelPath, "Ag")
    local sz = widget.getSize(self.measureLabelPath)

    local textW = sz and sz[1] or self.fontSize
    local textH = sz and sz[2] or self.fontSize
    textH = math.max(1, math.floor(textH + 0.5))

    local metrics = {
        textWidth = textW,
        textHeight = textH
    }

    self.cache[self.fontSize].__fontMetrics = metrics
    return metrics
end

---@protected
function Textbox:_setupMeasureLabel()
    local path = WIDGET_SHORTS.measureLabel .. self.uuid
    pane.addWidget({
        type = "label",
        wrapWidth = 1000,
        position = { -1000, -1000 },
        visible = false,
        hAnchor = "left",
        vAnchor = "top",
        color = "#00000000",
        fontSize = self.fontSize,
        value = "",
        font = self.textFont
    }, path)
    self.measureLabelPath = path
end

function Textbox:_getTextBaseY()
    local canvasH = self.carretCanvas:size()[2]
    local effectiveH = (#self.lines <= 1) and self.minHeight or canvasH
    return (effectiveH - PAD) + self.scrollY + (self.textOffsetY or 0)
end

---@protected
function Textbox:_getLineSpacing(lineCount)
    lineCount = lineCount or #self.lines
    return lineCount > 1 and self.lineSpacing or 0
end

---@protected
function Textbox:_getLineAdvance(lineCount)
    return self.lineHeight + self:_getLineSpacing(lineCount)
end

---@protected
function Textbox:_destroyMeasureLabel()
    pane.removeWidget(self.measureLabelPath)
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
    return math.max(0, self.rect[3] - PAD * 4)
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
    local lineChars = {}
    local charXs = {}
    local lineWidth = 0
    local lastBreakIndex = nil

    local function rebuildLineMetrics()
        charXs = {}
        for i = 1, #lineChars do
            charXs[i] = self:_lineTextWidth(table.concat(lineChars, "", 1, i - 1))
        end
        lineWidth = self:_lineTextWidth(table.concat(lineChars))
    end

    local function flushLine(endIdx, endsWithNewline)
        local textPart = table.concat(lineChars)
        lines[#lines + 1] = {
            startIdx = lineStartCI,
            endIdx = endIdx,
            charXs = charXs,
            width = lineWidth,
            text = endsWithNewline and (textPart .. "\n") or textPart,
            endsWithNewline = endsWithNewline,
            visibleEndIdx = endsWithNewline and (endIdx - 1) or endIdx
        }
    end

    local bi = 1
    for ci = 1, self.charLen do
        local nextBi = utf8.offset(text, 2, bi) or (#text + 1)
        local ch = text:sub(bi, nextBi - 1)

        if ch == "\n" then
            charXs[#charXs + 1] = lineWidth
            flushLine(ci, true)

            lineStartCI = ci + 1
            lineChars = {}
            charXs = {}
            lineWidth = 0
            lastBreakIndex = nil
        else
            lineChars[#lineChars + 1] = ch
            charXs[#charXs + 1] = lineWidth
            lineWidth = self:_lineTextWidth(table.concat(lineChars))

            if isHorizontalSpace(ch) then
                lastBreakIndex = #lineChars
            end

            if lineWidth > maxW and #lineChars > 1 then
                if lastBreakIndex and lastBreakIndex < #lineChars then
                    local wrapCount = lastBreakIndex
                    local wrapText = table.concat(lineChars, "", 1, wrapCount)
                    local wrapCharXs = {}
                    for i = 1, wrapCount do
                        wrapCharXs[i] = charXs[i]
                    end

                    lines[#lines + 1] = {
                        startIdx = lineStartCI,
                        endIdx = lineStartCI + wrapCount - 1,
                        charXs = wrapCharXs,
                        width = self:_lineTextWidth(wrapText),
                        text = wrapText,
                    }

                    local restChars = {}
                    for i = wrapCount + 1, #lineChars do
                        restChars[#restChars + 1] = lineChars[i]
                    end

                    lineStartCI = lineStartCI + wrapCount
                    lineChars = restChars
                    lastBreakIndex = nil
                    rebuildLineMetrics()

                    for i = 1, #lineChars do
                        if isHorizontalSpace(lineChars[i]) then
                            lastBreakIndex = i
                        end
                    end
                else
                    local overflowChar = lineChars[#lineChars]

                    local prevChars = {}
                    local prevCharXs = {}
                    for i = 1, #lineChars - 1 do
                        prevChars[i] = lineChars[i]
                        prevCharXs[i] = charXs[i]
                    end

                    lines[#lines + 1] = {
                        startIdx = lineStartCI,
                        endIdx = ci - 1,
                        charXs = prevCharXs,
                        width = self:_lineTextWidth(table.concat(prevChars)),
                        text = table.concat(prevChars),
                    }

                    lineStartCI = ci
                    lineChars = { overflowChar }
                    charXs = { 0 }
                    lineWidth = self:_lineTextWidth(overflowChar)
                    lastBreakIndex = isHorizontalSpace(overflowChar) and 1 or nil
                end
            end
        end

        bi = nextBi
    end

    if lineStartCI <= self.charLen then
        flushLine(self.charLen, false)
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

    if line.endsWithNewline and bestPos == line.endIdx then
        bestPos = math.max(line.startIdx - 1, bestPos - 1)
    end

    return bestPos
end

---@protected
function Textbox:_cursorToLineX(pos, affinity)
    affinity = affinity or CURSOR_AFFINITY.forward
    if #self.lines == 0 then
        return 1, 0
    end

    for li, line in ipairs(self.lines) do
        local endPos = line.visibleEndIdx or line.endIdx

        if pos >= line.startIdx - 1 and pos <= endPos then
            if not line.endsWithNewline and pos == endPos and li < #self.lines
                    and affinity == CURSOR_AFFINITY.forward then
                return li + 1, 0
            end

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
    local lineAdvance = self:_getLineAdvance()
    local lineIdx = clamp(
            math.floor((sz[2] - PAD + self.scrollY - clickY) / lineAdvance) + 1,
            1, #self.lines)
    local line = self.lines[lineIdx]
    return line and self:_hitTestLine(line, clickX - PAD) or 0, lineIdx
end

---@protected
function Textbox:_xToLinePos(lineIdx, targetX)
    local line = self.lines[lineIdx]
    return line and self:_hitTestLine(line, targetX) or self.cursorPos
end

---@protected
function Textbox:_determineClickAffinity(pos, lineIdx)
    local line = self.lines[lineIdx]
    if line and pos == line.endIdx
            and line.endIdx >= line.startIdx
            and not line.endsWithNewline
            and lineIdx < #self.lines then
        return CURSOR_AFFINITY.backward
    end
    return CURSOR_AFFINITY.forward
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
function Textbox:_selectAllText()
    self.selAnchor = 0
    self.cursorPos = self.charLen
    self._cursorAffinity = CURSOR_AFFINITY.backward
    self:_resetBlink()
    self:_ensureCursorVisible()
    self:_invalidateCaret()
end

---@protected
function Textbox:_selectCurrentLine(lineIdx)
    if not lineIdx or lineIdx < 1 or lineIdx > #self.lines then
        return
    end
    
    local line = self.lines[lineIdx]
    self.selAnchor = line.startIdx - 1
    self.cursorPos = line.endIdx
    self._cursorAffinity = CURSOR_AFFINITY.backward
    self:_resetBlink()
    self:_ensureCursorVisible()
    self:_invalidateCaret()
end

---@protected
function Textbox:_selectTextUnitAtCursor(pos)
    if self.charLen == 0 then
        return false
    end

    local charIdx = nil
    local rightChar = pos < self.charLen and utf8.charAt(self.text, pos + 1) or nil
    if rightChar then
        charIdx = pos + 1
    else
        local leftChar = pos > 0 and utf8.charAt(self.text, pos) or nil
        if leftChar then
            charIdx = pos
        end
    end

    if not charIdx then
        return false
    end

    local text = self.text
    local ch = utf8.charAt(text, charIdx)
    local from = charIdx - 1
    local to = charIdx

    if isWordChar(ch) then
        from = self:_wordBoundaryLeft(charIdx)
        to = self:_wordBoundaryRight(charIdx - 1)
    elseif isHorizontalSpace(ch) then
        while from > 0 and isHorizontalSpace(utf8.charAt(text, from)) do
            from = from - 1
        end
        while to < self.charLen and isHorizontalSpace(utf8.charAt(text, to + 1)) do
            to = to + 1
        end
    end

    while to < self.charLen and isHorizontalSpace(utf8.charAt(text, to + 1)) do
        to = to + 1
    end

    self.selAnchor = from
    self.cursorPos = to
    self._cursorAffinity = CURSOR_AFFINITY.backward
    self:_resetBlink()
    self:_ensureCursorVisible()
    self:_invalidateCaret()
    return true
end

-- ─────────────────────────── Text editing ────────────────────────────────────
---@protected
function Textbox:_splice(from, to)
    local before = from > 0 and utf8.sub(self.text, 1, from) or ""
    self.text = before .. (utf8.sub(self.text, to + 1) or "")
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
function Textbox:_insertText(str, suppressOnChanged)
    if not str or str == "" then
        return
    end
    local hadSelection = self:_deleteSelection()
    if hadSelection then
        -- Break the action grouping chain when replacing a selection
        self._lastActionType = nil
        self._timeSinceLastAction = self._actionGroupTimeThreshold
    end
    local before = self.cursorPos > 0 and utf8.sub(self.text, 1, self.cursorPos) or ""
    self.text = before .. str .. (utf8.sub(self.text, self.cursorPos + 1) or "")
    self.cursorPos = self.cursorPos + utf8.len(str)
    self.selAnchor = nil
    self:_onTextChanged(ACTION_TYPES.insert, suppressOnChanged)
end

---@protected
function Textbox:_deleteBack()
    if self:_deleteSelection() then
        self:_onTextChanged(ACTION_TYPES.backspace);
        return
    end
    if self.cursorPos <= 0 then
        return
    end
    self:_splice(self.cursorPos - 1, self.cursorPos)
    self.cursorPos = self.cursorPos - 1
    self.selAnchor = nil
    self:_onTextChanged(ACTION_TYPES.backspace)
end
---@protected
function Textbox:_deleteForward()
    if self:_deleteSelection() then
        self:_onTextChanged(ACTION_TYPES.delete);
        return
    end
    if self.cursorPos >= self.charLen then
        return
    end
    self:_splice(self.cursorPos, self.cursorPos + 1)
    self.selAnchor = nil
    self:_onTextChanged(ACTION_TYPES.delete)
end

-- ─────────────────────────── Word ─────────────────────────────────
---@protected
function Textbox:_wordBoundaryLeft(pos)
    local text = self.text
    while pos > 0 and not isWordChar(utf8.charAt(text, pos)) do
        pos = pos - 1
    end
    while pos > 0 and isWordChar(utf8.charAt(text, pos)) do
        pos = pos - 1
    end
    return pos
end
---@protected
function Textbox:_wordBoundaryRight(pos)
    local text, len = self.text, self.charLen
    while pos < len and not isWordChar(utf8.charAt(text, pos + 1)) do
        pos = pos + 1
    end
    while pos < len and isWordChar(utf8.charAt(text, pos + 1)) do
        pos = pos + 1
    end
    return pos
end
---@protected
function Textbox:_deleteWordBack()
    if self:_deleteSelection() then
        self:_onTextChanged(ACTION_TYPES.backspace);
        return
    end
    if self.cursorPos <= 0 then
        return
    end

    local prevChar = utf8.charAt(self.text, self.cursorPos)
    local newPos

    if prevChar == "\n" then
        newPos = self.cursorPos - 1
        while newPos > 0 and utf8.charAt(self.text, newPos) == "\n" do
            newPos = newPos - 1
        end
    else
        newPos = self:_wordBoundaryLeft(self.cursorPos)
    end

    if newPos < self.cursorPos then
        self:_splice(newPos, self.cursorPos)
        self.cursorPos = newPos
        self.selAnchor = nil
        self:_onTextChanged(ACTION_TYPES.backspace)
    end
end
---@protected
function Textbox:_deleteWordForward()
    if self:_deleteSelection() then
        self:_onTextChanged(ACTION_TYPES.delete);
        return
    end
    if self.cursorPos >= self.charLen then
        return
    end
    local newPos = self:_wordBoundaryRight(self.cursorPos)
    if newPos > self.cursorPos then
        self:_splice(self.cursorPos, newPos)
        self.selAnchor = nil
        self:_onTextChanged(ACTION_TYPES.delete)
    end
end

-- ─────────────────────────── Undo/Redo ─────────────────────────────────────

---@protected
---@return table
function Textbox:_saveState()
    return {
        text = self.text,
        cursorPos = self.cursorPos,
        selAnchor = self.selAnchor,
        scrollY = self.scrollY,
    }
end

---@protected
function Textbox:_restoreState(state, suppressOnChanged)
    if not state then
        return
    end
    self.text = state.text
    self.cursorPos = state.cursorPos
    self.selAnchor = state.selAnchor
    self.scrollY = state.scrollY
    self.charLen = utf8.len(self.text)

    self:_invalidateAll()
    self:_reflow()
    self:_updateAutoHeight()
    self:_ensureCursorVisible()
    self:_resetBlink()

    if self.onChanged and not suppressOnChanged then
        self.onChanged(self.text)
    end
end

---@protected
function Textbox:_saveInitialState()
    self._lastSavedState = self:_saveState()
    self._lastActionType = nil
    self._lastActionTime = 0
end

---@protected
---@param actionType string
---@param currentTime number
function Textbox:_pushUndoState(actionType, currentTime)
    local currentState = self:_saveState()

    if not self._lastSavedState or
       currentState.text ~= self._lastSavedState.text then
        
        -- Check if we should group this action with the previous one
        local shouldGroup = false
        if self._lastActionType and actionType then
            -- Group continuous insertions or deletions
            if (self._lastActionType == ACTION_TYPES.insert and actionType == ACTION_TYPES.insert) or
               (self._lastActionType == ACTION_TYPES.backspace and actionType == ACTION_TYPES.backspace) or
               (self._lastActionType == ACTION_TYPES.delete and actionType == ACTION_TYPES.delete) then
                -- Only group if time threshold hasn't been exceeded
                if (currentTime - self._lastActionTime) < self._actionGroupTimeThreshold then
                    shouldGroup = true
                end
            end
        end

        -- Only push to history if we're not grouping
        if not shouldGroup then
            table.insert(self.undoHistory, self._lastSavedState or self:_saveState())
            self.redoHistory = {}
        end

        self._lastSavedState = currentState
        self._lastActionType = actionType
        self._lastActionTime = currentTime
    end
end

---@protected
function Textbox:_undo()
    if #self.undoHistory == 0 then
        return
    end

    table.insert(self.redoHistory, self._lastSavedState)
    self._lastSavedState = table.remove(self.undoHistory)
    self:_restoreState(self._lastSavedState, true)
    
    self._lastActionType = nil
    self._lastActionTime = 0
end

---@protected
function Textbox:_redo()
    if #self.redoHistory == 0 then
        return
    end

    table.insert(self.undoHistory, self._lastSavedState)
    self._lastSavedState = table.remove(self.redoHistory)
    self:_restoreState(self._lastSavedState, true)
    
    self._lastActionType = nil
    self._lastActionTime = 0
end

---@protected
function Textbox:_onTextChanged(actionType, suppressOnChanged)
    self.charLen = utf8.len(self.text)
    self.cursorPos = clamp(self.cursorPos, 0, self.charLen)
    self._cursorAffinity = CURSOR_AFFINITY.forward

    if self.selAnchor ~= nil then
        self.selAnchor = clamp(self.selAnchor, 0, self.charLen)
    end

    self:_invalidateAll()
    self:_reflow()
    self:_updateAutoHeight()
    self:_ensureCursorVisible()
    self:_resetBlink()

    if self.onChanged and not suppressOnChanged then
        self.onChanged(self.text)
    end

    if not suppressOnChanged then
        local currentTime = 0
        self:_pushUndoState(actionType or ACTION_TYPES.other, currentTime)
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
function Textbox:_ensureSelection(shift)
    if shift and self.selAnchor == nil then
        self.selAnchor = self.cursorPos
    end
end

---@protected
function Textbox:_finishMove(shift, affinity)
    if not shift then
        self.selAnchor = nil
    end
    self._cursorAffinity = affinity or CURSOR_AFFINITY.forward
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
    self:_ensureSelection(shift)
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
    self:_ensureSelection(shift)
    if self.cursorPos < self.charLen then
        self.cursorPos = self.cursorPos + 1
    end
    self:_finishMove(shift)
end
---@protected
function Textbox:_moveCursorUp(shift)
    self:_ensureSelection(shift)
    local li, x = self:_cursorToLineX(self.cursorPos, self._cursorAffinity)
    self.cursorPos = li <= 1 and 0 or self:_xToLinePos(li - 1, x)
    self:_finishMove(shift)
end
---@protected
function Textbox:_moveCursorDown(shift)
    self:_ensureSelection(shift)
    local li, x = self:_cursorToLineX(self.cursorPos, self._cursorAffinity)
    self.cursorPos = li >= #self.lines and self.charLen or self:_xToLinePos(li + 1, x)
    self:_finishMove(shift)
end
---@protected
function Textbox:_moveCursorHome(shift)
    self:_ensureSelection(shift)
    local li = self:_cursorToLineX(self.cursorPos, self._cursorAffinity)
    local line = self.lines[li]
    if line then
        self.cursorPos = line.startIdx - 1
    end
    self:_finishMove(shift)
end
---@protected
function Textbox:_moveCursorEnd(shift)
    self:_ensureSelection(shift)
    local li = self:_cursorToLineX(self.cursorPos, self._cursorAffinity)
    local line = self.lines[li]
    if line then
        local ep = line.endIdx
        if ep >= line.startIdx and utf8.charAt(self.text, ep) == "\n" then
            ep = math.max(line.startIdx - 1, ep - 1)
        end
        self.cursorPos = ep
    end
    self:_finishMove(shift, CURSOR_AFFINITY.backward)
end
---@protected
function Textbox:_moveCursorWordLeft(shift)
    self:_ensureSelection(shift)
    self.cursorPos = self:_wordBoundaryLeft(self.cursorPos)
    self:_finishMove(shift)
end
---@protected
function Textbox:_moveCursorWordRight(shift)
    self:_ensureSelection(shift)
    self.cursorPos = self:_wordBoundaryRight(self.cursorPos)
    self:_finishMove(shift)
end

-- ─────────────────────────── scroll ──────────────────────────────────────────

---@protected
function Textbox:_getContentHeight()
    local lineCount = #self.lines
    return lineCount * self.lineHeight + math.max(0, lineCount - 1) * self:_getLineSpacing(lineCount)
end
---@protected
function Textbox:_getViewHeight()
    local h = self.carretCanvas:size()[2]
    return math.max(1, h)
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
    local lineAdvance = self:_getLineAdvance(total)
    local first = math.floor(self.scrollY / lineAdvance) + 1
    local last = math.ceil((self.scrollY + viewH) / lineAdvance) + 1

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
    --local contentH = self:_getContentHeight()
    local viewH = self:_getViewHeight()

    --[[    if contentH + PAD * 2 <= viewH then
            if self.scrollY ~= 0 then
                self.scrollY = 0
                self:_invalidateAll()
            else
                self:_invalidateCaret()
            end
            return
        end]]
    local li = self:_cursorToLineX(self.cursorPos)
    local lineAdvance = self:_getLineAdvance()

    local cursorTop = (li - 1) * lineAdvance
    local cursorBot = cursorTop + self.lineHeight

    local innerViewH = math.max(1, viewH - PAD * 2)

    local margin = math.floor(lineAdvance * 0.5)

    local topLimit = self.scrollY + margin
    local bottomLimit = self.scrollY + innerViewH - margin

    local old = self.scrollY

    if cursorTop < topLimit then
        self.scrollY = cursorTop - margin
    elseif cursorBot > bottomLimit then
        self.scrollY = cursorBot - innerViewH + margin
    end

    self.scrollY = clamp(self.scrollY, 0, self:_getMaxScroll())

    if self.scrollY ~= old then
        self:_invalidateAll()
    else
        self:_invalidateCaret()
    end
end
-- ─────────────────────────── prosessing ────────────────────────────────
---@protected
function Textbox:_processInput(dt, events, mousePos)
    self.caretTimer = self.caretTimer + dt
    self._doubleClickTimer = math.max(0, (self._doubleClickTimer or 0) - dt)

    if self.caretTimer >= CARET_BLINK_INTERVAL then
        self.caretTimer = self.caretTimer - CARET_BLINK_INTERVAL
        self.caretVisible = not self.caretVisible
        self:_invalidateCaret()
    end

    if self._ignoreInputFrame then
        self._ignoreInputFrame = false
        return
    end

    for _, ev in ipairs(events) do
        local data = ev.data
        if ev.type == "KeyDown" and data then
            local key = data.key
            if key == KEYS.LShift or key == KEYS.RShift then
                self._shiftHeld = true
            end
            if key == KEYS.LCtrl or key == KEYS.RCtrl then
                self._ctrlHeld = true
            end
            if REPEATABLE_KEYS[key] then
                self._heldKey = key
                self._heldTimer = 0
            end
        elseif ev.type == "KeyUp" and data then
            local key = data.key
            if key == KEYS.LShift or key == KEYS.RShift then
                self._shiftHeld = false
            end
            if key == KEYS.LCtrl or key == KEYS.RCtrl then
                self._ctrlHeld = false
            end
            if key == self._heldKey then
                self._heldKey = nil
                self._heldTimer = 0
            end
        end
    end

    self:_processMouseEvents(events, mousePos)
    if not self.focused then
        return
    end

    if self._heldKey then
        self._heldTimer = self._heldTimer + dt
        if self._heldTimer >= KEY_REPEAT_DELAY then
            local elapsed = self._heldTimer - KEY_REPEAT_DELAY
            if math.floor(elapsed / KEY_REPEAT_INTERVAL) > 0 then
                local mods = {}
                if self._shiftHeld then
                    table.insert(mods, KEYS.LShift)
                    table.insert(mods, KEYS.RShift)
                end
                if self._ctrlHeld then
                    table.insert(mods, KEYS.LCtrl)
                    table.insert(mods, KEYS.RCtrl)
                end
                local fakeEvent = {
                    type = "KeyDown",
                    data = {
                        key = self._heldKey,
                        mods = mods
                    }
                }
                self:_processKeys({ fakeEvent })
                self._heldTimer = KEY_REPEAT_DELAY + (elapsed % KEY_REPEAT_INTERVAL)
            end
        end
    end

    self:_pollFakeTextbox()
    self:_processKeys(events)
end

function Textbox.findPaneFeature()
    local cfg = config.getParameter("", {}) or {}
    if type(cfg) ~= "table" then
        return nil
    end

    if cfg.type == "panefeature" then
        return cfg
    end

    for _, v in pairs(cfg) do
        if type(v) == "table" then
            if v.type == "panefeature" then
                return v
            end

            for _, vv in pairs(v) do
                if type(vv) == "table" and vv.type == "panefeature" then
                    return vv
                end
            end
        end
    end

    return nil
end

---@class WidgetPaneFeature
---@field type string -- Он всегда равен "panefeature"
---@field anchor string -- none, bottomLeft, bottomRight, topLeft, topRight, centerBottom, centerTop, centerLeft, centerRight, center
---@field offset number[] -- [x, y]
---@field positionLocked boolean, -- Просто нельзя двигать виджет, он всегда будет в одной позиции относительно якоря

---@protected
function Textbox:_splitWidgetPath(path)
    local parts = {}
    for part in string.gmatch(path or "", "[^%.]+") do
        parts[#parts + 1] = part
    end
    return parts
end

---@protected
function Textbox:_getChildChainOffset()
    if not self._isChild then
        return { 0, 0 }
    end

    if self._firstParent and self._childrenRect then
        return self._childrenRect
    end

    local parts = self:_splitWidgetPath(self.parrentWidgetPath)
    debugMessage("Widget path parts: %s", sb.printJson(parts))
    if #parts == 0 then
        self._firstParent = self.parrentWidgetPath
        self._childrenRect = { 0, 0 }
        return self._childrenRect
    end

    self._firstParent = parts[1]

    local offset = { 0, 0 }
    local currentPath = parts[1]


    for i = 2, #parts do
        currentPath = currentPath .. "." .. parts[i]
        local childPos = widget.getPosition(currentPath) or { 0, 0 }
        offset = vec2.add(offset, childPos)
        debugMessage("Child chain part %s (%s) pos: %s", tostring(i), currentPath, sb.printJson(childPos))
    end

    self._childrenRect = offset
    return offset
end

---@protected
function Textbox:_getPaneAnchorOffset()
    local feature = self._paneFeature
    if not feature then
        return { 0, 0 }
    end
    local anchor = feature.anchor or "none"

    local screenSize = camera.screenSize()
    local scale = interface.scale()
    local paneSize = vec2.mul(pane.getSize(), scale)

    local offset = { 0, 0 }

    if anchor == "bottomLeft" or anchor == "none" then
        offset = { 0, 0 }

    elseif anchor == "bottomRight" then
        offset = { screenSize[1] - paneSize[1], 0 }

    elseif anchor == "topLeft" then
        offset = { 0, screenSize[2] - paneSize[2] }

    elseif anchor == "topRight" then
        offset = { screenSize[1] - paneSize[1], screenSize[2] - paneSize[2] }

    elseif anchor == "centerBottom" then
        offset = {
            (screenSize[1] - paneSize[1]) * 0.5,
            0
        }

    elseif anchor == "centerTop" then
        offset = {
            (screenSize[1] - paneSize[1]) * 0.5,
            screenSize[2] - paneSize[2]
        }

    elseif anchor == "centerLeft" then
        offset = {
            0,
            (screenSize[2] - paneSize[2]) * 0.5
        }

    elseif anchor == "centerRight" then
        offset = {
            screenSize[1] - paneSize[1],
            (screenSize[2] - paneSize[2]) * 0.5
        }

    elseif anchor == "center" then
        offset = {
            (screenSize[1] - paneSize[1]) * 0.5,
            (screenSize[2] - paneSize[2]) * 0.5
        }
    end

    local featureOffset = feature.offset or { 0, 0 }
    return vec2.add(offset, vec2.mul(featureOffset, scale))
end

---@protected
function Textbox:_getParentWidgetLocalPosition()
    if self._isChild then
        local childChain = self:_getChildChainOffset()
        local firstParentPos = widget.getPosition(self._firstParent)
        return vec2.add(firstParentPos, childChain)
    end

    return widget.getPosition(self.parrentWidgetPath)
end

---@protected
function Textbox:_getWidgetScreenRect()
    local panePos = pane.getPosition()
    local anchorOffset = self:_getPaneAnchorOffset()

    local parentWidgetPos = self:_getParentWidgetLocalPosition()

    local uiPos = vec2.add(panePos, parentWidgetPos)
    uiPos = vec2.add(uiPos, self._layoutOffset)
    uiPos = vec2.add(uiPos, self._screenOffset)

    local scale = interface.scale() or 1

    local screenPos = vec2.add(anchorOffset, vec2.mul(uiPos, scale))
    local size = vec2.mul(self.carretCanvas:size(), scale)

    return {
        screenPos[1],
        screenPos[2],
        screenPos[1] + size[1],
        screenPos[2] + size[2]
    }
end

---@protected
function Textbox:_screenToLocalMouse(mouseScreen, clampToCanvas)
    if not self.carretCanvas then
        return nil
    end

    local widgetRect = self:_getWidgetScreenRect()
    local scale = interface.scale()

    local localMouse = {
        (mouseScreen[1] - widgetRect[1]) / scale,
        (mouseScreen[2] - widgetRect[2]) / scale
    }

    if clampToCanvas then
        local sz = self.carretCanvas:size()
        localMouse[1] = clamp(localMouse[1], 0, sz[1])
        localMouse[2] = clamp(localMouse[2], 0, sz[2])
    end
    return localMouse, widgetRect
end

---@protected
function Textbox:_getMouseHit(mouseScreen)
    if not self.carretCanvas then
        return false, nil, nil
    end

    local localMouse, widgetRect = self:_screenToLocalMouse(mouseScreen, false)
    if not rect.contains(widgetRect, mouseScreen) then
        return false, localMouse, widgetRect
    end

    return true, localMouse, widgetRect
end

---@protected
function Textbox:_processMouseEvents(events, mouseScreen)
    if not self.carretCanvas then
        return
    end

    for _, ev in ipairs(events) do
        if ev.type == "MouseWheel" and ev.data and self.focused then
            local hit = self:_getMouseHit(mouseScreen)
            if hit then
                local lineAdvance = self:_getLineAdvance()
                self.scrollY = clamp(
                        self.scrollY - ev.data.mouseWheel * lineAdvance * 3,
                        0, self:_getMaxScroll()
                )
                self:_invalidateCaret()
                self.textDirty = true
            end

        elseif ev.type == "MouseButtonDown" and ev.data
                and ev.data.mouseButton == "MouseLeft" then
            self._mouseLeftHeld = true

            local hit, localMouse = self:_getMouseHit(mouseScreen)
            if hit then
                self:focus()
                local pos, clickedLi = self:_xyToCursor(localMouse[1], localMouse[2])
                self._cursorAffinity = self:_determineClickAffinity(pos, clickedLi)
                local clickCount = ev.data.count or ev.data.clickCount or ev.data.clicks
                if not clickCount and input.mouseDown then
                    clickCount = input.mouseDown("MouseLeft")
                end

                local isSameClickSpot = false
                if self._doubleClickTimer > 0 and self._lastClickMouse then
                    local dx = localMouse[1] - self._lastClickMouse[1]
                    local dy = localMouse[2] - self._lastClickMouse[2]
                    isSameClickSpot = (dx * dx + dy * dy) <= (DOUBLE_CLICK_MAX_DISTANCE * DOUBLE_CLICK_MAX_DISTANCE)
                end

                if clickCount and clickCount >= 2 then
                    self._clickCount = clickCount
                elseif isSameClickSpot then
                    self._clickCount = (self._clickCount or 0) + 1
                else
                    self._clickCount = 1
                end

                if self._clickCount >= 4 then
                    self:_selectAllText()
                    self._doubleClickTimer = 0
                    self._clickCount = 0
                    self._mouseDragAnchor = nil
                    self._lastClickMouse = nil
                    self._mouseWasDown = false
                elseif self._clickCount >= 3 then
                    self:_selectCurrentLine(clickedLi)
                    self._doubleClickTimer = DOUBLE_CLICK_INTERVAL
                    self._mouseDragAnchor = nil
                    self._lastClickMouse = { localMouse[1], localMouse[2] }
                    self._mouseWasDown = false
                elseif self._clickCount >= 2 then
                    if not self:_selectTextUnitAtCursor(pos) then
                        self.selAnchor = nil
                        self.cursorPos = pos
                        self:_resetBlink()
                    end
                    self._doubleClickTimer = DOUBLE_CLICK_INTERVAL
                    self._mouseDragAnchor = nil
                    self._lastClickMouse = { localMouse[1], localMouse[2] }
                    self._mouseWasDown = false
                else
                    if self._shiftHeld then
                        if self.selAnchor == nil then
                            self.selAnchor = self.cursorPos
                        end
                    else
                        self.selAnchor = nil
                    end

                    self.cursorPos = pos
                    self:_resetBlink()
                    self._doubleClickTimer = DOUBLE_CLICK_INTERVAL
                    self._mouseDragAnchor = pos
                    self._lastClickMouse = { localMouse[1], localMouse[2] }
                    self._mouseWasDown = true
                end
            else
                if self.unfocusOnClickOutside then
                    self:blur()
                end
                self._mouseWasDown = false
                self._doubleClickTimer = 0
                self._clickCount = 0
                self._mouseDragAnchor = nil
                self._lastClickMouse = nil
            end

        elseif ev.type == "MouseButtonUp" and ev.data
                and ev.data.mouseButton == "MouseLeft" then
            self._mouseLeftHeld = false
            self._mouseWasDown = false
            self._mouseDragAnchor = nil
        end
    end

    -- DRAG
    -- Надо бы почаще комментарии оставлять
    if self._mouseLeftHeld and self._mouseWasDown and self.focused then
        local localMouse = self:_screenToLocalMouse(mouseScreen, true)
        if localMouse then
            local pos, dragLi = self:_xyToCursor(localMouse[1], localMouse[2])
            if pos ~= self.cursorPos then
                if self.selAnchor == nil then
                    self.selAnchor = self._mouseDragAnchor or self.cursorPos
                end
                self.cursorPos = pos
                self._cursorAffinity = self:_determineClickAffinity(pos, dragLi)
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

    self:_resumeFakeTextboxPasteCoroutine()
    if self._fakeTextboxPasteCoroutine then
        return
    end

    local txt = widget.getText(self.fakeTextbox)
    if txt and txt ~= "" then
        widget.setText(self.fakeTextbox, "")

        if utf8.len(txt) > FAKE_TEXTBOX_COROUTINE_THRESHOLD then
            self:_startFakeTextboxPasteCoroutine(txt)
            self:_resumeFakeTextboxPasteCoroutine()
        else
            self:_insertText(txt)
        end
    end
end

---@protected
function Textbox:_clearFakeTextboxPasteCoroutine(clearBufferedText)
    self._fakeTextboxPasteCoroutine = nil

    if clearBufferedText and self.fakeTextbox then
        widget.setText(self.fakeTextbox, "")
    end
end

---@protected
---@param txt string
function Textbox:_startFakeTextboxPasteCoroutine(txt)

    local totalChars = utf8.len(txt)
    if totalChars <= FAKE_TEXTBOX_COROUTINE_THRESHOLD then
        self:_insertText(txt)
        return
    end

    self._fakeTextboxPasteCoroutine = coroutine.create(function()
        local fromChar = 1

        while fromChar <= totalChars do
            local toChar = math.min(totalChars, fromChar + FAKE_TEXTBOX_COROUTINE_CHUNK_SIZE - 1)
            local chunk = utf8.sub(txt, fromChar, toChar)
            local isLastChunk = toChar >= totalChars

            if chunk ~= "" then
                self:_insertText(chunk, not isLastChunk)
            end

            fromChar = toChar + 1
            if fromChar <= totalChars then
                coroutine.yield(fromChar)
            end
        end
    end)
end

---@protected
function Textbox:_resumeFakeTextboxPasteCoroutine()
    local co = self._fakeTextboxPasteCoroutine
    if not co then
        return false
    end

    if coroutine.status(co) == "dead" then
        self:_clearFakeTextboxPasteCoroutine(false)
        return false
    end

    local ok, err = coroutine.resume(co)
    if not ok then
        sb.logError("[tbx.lua] Fake textbox coroutine failed: %s", tostring(err))
        self:_clearFakeTextboxPasteCoroutine(false)
        return false
    end

    if coroutine.status(co) == "dead" then
        self:_clearFakeTextboxPasteCoroutine(false)
        return false
    end

    return true
end



local KEY_DISPATCH = {
    ---@param self Textbox
    [KEYS.Backspace] = function(self, ctrl, shift)
        if ctrl then self:_deleteWordBack() else self:_deleteBack() end
    end,
    ---@param self Textbox
    [KEYS.Delete] = function(self, ctrl, shift)
        if ctrl then self:_deleteWordForward() else self:_deleteForward() end
    end,
    ---@param self Textbox
    [KEYS.Return] = function(self, ctrl, shift)
        if shift then
            self:_insertText("\n")
        elseif self.onEnterKey then
            self.onEnterKey()
        end
    end,
    ---@param self Textbox
    [KEYS.Escape] = function(self, ctrl, shift)
        if self.onEscapeKey then self:onEscapeKey() end
    end,
    ---@param self Textbox
    [KEYS.Tab] = function(self, ctrl, shift)
        self:_insertText(self.tabSpaces or "  ")
    end,
    ---@param self Textbox
    [KEYS.Left] = function(self, ctrl, shift)
        if ctrl then self:_moveCursorWordLeft(shift) else self:_moveCursorLeft(shift) end
    end,
    ---@param self Textbox
    [KEYS.Right] = function(self, ctrl, shift)
        if ctrl then self:_moveCursorWordRight(shift) else self:_moveCursorRight(shift) end
    end,
    ---@param self Textbox
    [KEYS.Up] = function(self, ctrl, shift)
        self:_moveCursorUp(shift)
    end,
    ---@param self Textbox
    [KEYS.Down] = function(self, ctrl, shift)
        self:_moveCursorDown(shift)
    end,
    ---@param self Textbox
    [KEYS.Home] = function(self, ctrl, shift)
        if ctrl then
            self:_ensureSelection(shift)
            self.cursorPos = 0
            self:_finishMove(shift)
        else
            self:_moveCursorHome(shift)
        end
    end,
    ---@param self Textbox
    [KEYS.End] = function(self, ctrl, shift)
        if ctrl then
            self:_ensureSelection(shift)
            self.cursorPos = self.charLen
            self:_finishMove(shift)
        else
            self:_moveCursorEnd(shift)
        end
    end,
    ---@param self Textbox
    [KEYS.A] = function(self, ctrl, shift)
        if not ctrl then return end
        self.selAnchor = 0
        self.cursorPos = self.charLen
        self:_resetBlink()
    end,
    ---@param self Textbox
    [KEYS.C] = function(self, ctrl, shift)
        if not ctrl then return end
        local sel = self:getSelectedText()
        if sel ~= "" then clipboard.setText(sel) end
    end,
    ---@param self Textbox
    [KEYS.X] = function(self, ctrl, shift)
        if not ctrl then return end
        local sel = self:getSelectedText()
        if sel ~= "" then
            clipboard.setText(sel)
            self:_deleteSelection()
            self:_onTextChanged(ACTION_TYPES.delete)
        end
    end,
    ---@param self Textbox
    [KEYS.Z] = function(self, ctrl, shift)
        if not ctrl then return end
        if shift then self:_redo() else self:_undo() end
    end,
    ---@param self Textbox
    [KEYS.Y] = function(self, ctrl, shift)
        if ctrl then self:_redo() end
    end,
}


---@protected
function Textbox:_processKeys(events)
    for _, ev in ipairs(events) do
        if ev.type == "KeyDown" and ev.data then
            local key    = ev.data.key
            local mods   = ev.data.mods or {}
            local shift  = hasMod(mods, KEYS.LShift) or hasMod(mods, KEYS.RShift)
            local ctrl   = hasMod(mods, KEYS.LCtrl)  or hasMod(mods, KEYS.RCtrl)

            local handler = KEY_DISPATCH[key]
            if handler then
                handler(self, ctrl, shift)
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

    local metrics = self:_measureFontMetrics()
    local baseY = self:_getTextBaseY()
    local lineAdvance = self:_getLineAdvance()
    local fs, color = self.fontSize, self.textColor
    local vInset = self:_getVerticalInset(metrics)
    local textFont = self.textFont

    local drawParams = {
        position = { PAD, 0 },
        horizontalAnchor = "left",
        verticalAnchor = "top",
    }

    if self.charLen == 0 and self.hint and self.hint ~= "" then
        drawParams.position[2] = baseY - vInset
        canvas:drawText(self.hint, drawParams, fs, self.hintColor, nil, textFont)
    else
        local fromLi, toLi = self:_getVisibleLineRange()
        for li = fromLi, toLi do
            local line = self.lines[li]
            if line then
                local top = baseY - (li - 1) * lineAdvance
                local lineText = line.text or ""
                if lineText ~= "" and lineText ~= "\n" then
                    if lineText:sub(-1) == "\n" then
                        lineText = lineText:sub(1, -2)
                    end
                    drawParams.position[2] = top - vInset
                    debugMessage("DRAW LINE %s Y: %s", sb.print(li), sb.print(top - vInset))
                    canvas:drawText(lineText, drawParams, fs, color, nil, textFont)

                end
            end
        end
    end

    self.textDirty = false
end

---@protected
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

    local metrics = self:_measureFontMetrics()
    local baseY = self:_getTextBaseY()
    local lineAdvance = self:_getLineAdvance()
    local textH = metrics.textHeight
    local vInset = self:_getVerticalInset(metrics)

    local firstVisible, lastVisible = self:_getVisibleLineRange()

    local selFrom, selTo = self:_getSelRange()
    if selFrom then
        local fromLi, fromX = self:_cursorToLineX(selFrom, CURSOR_AFFINITY.forward)
        local toLi, toX = self:_cursorToLineX(selTo, CURSOR_AFFINITY.backward)
        local drawFrom = math.max(firstVisible, fromLi)
        local drawTo = math.min(lastVisible, toLi)

        for li = drawFrom, drawTo do
            local line = self.lines[li]
            if line then
                local top = baseY - (li - 1) * lineAdvance
                local textTop = top - vInset
                local textBot = textTop - textH

                local x1 = li == fromLi and (PAD + fromX) or PAD
                local x2 = li == toLi and (PAD + toX) or (PAD + line.width)

                if x2 > x1 then
                    canvas:drawRect({ x1, textBot, x2, textTop }, self.selectionColor)
                end
            end
        end
    end

    if self.caretVisible then
        local li, cx = self:_cursorToLineX(self.cursorPos, self._cursorAffinity)
        if li >= firstVisible and li <= lastVisible then
            local top = baseY - (li - 1) * lineAdvance
            local textTop = top - vInset
            local textBot = textTop - textH
            local x = PAD + cx

            canvas:drawLine({ x, textBot }, { x, textTop }, self.caretColor, 1)
        end
    end

    self.caretDirty = false
end

function Textbox:_requiredHeightForLines(lineCount)
    return lineCount == 1 and self.minHeight or (lineCount * self.lineHeight + math.max(0, lineCount - 1) * self:_getLineSpacing(lineCount) + PAD * 2)
end

---@protected
function Textbox:_updateAutoHeight()
    if not self.maxHeight then
        return
    end

    local contentHeight = self:_requiredHeightForLines(#self.lines)
    local newHeight = clamp(contentHeight, self.minHeight, self.maxHeight)

    if newHeight ~= self.currentHeight then
        self.currentHeight = newHeight

        local newRect = { self.rect[1], self.rect[2], self.rect[3], newHeight }

        local width = newRect[3] - PAD
        local height = newRect[4]

        -- layout
        widget.setSize(self.path, { width, height })

        -- canvases
        local canvasSize = { width, height }
        widget.setSize(self.textCanvasPath, canvasSize)
        widget.setSize(self.carretCanvasPath, canvasSize)

        -- scroll area
        widget.setSize(self.scrollAreaPath, { width + 20, height })

        self.rect = newRect

        self:_invalidateAll()
        self:_reflow()
        self:_ensureCursorVisible()

        if self.onSizeChange then
            self.onSizeChange({ width, height })
        end
    end
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
    self:_clearFakeTextboxPasteCoroutine(true)
    self.text = text or ""
    self.charLen = utf8.len(self.text)
    self.cursorPos = self.charLen
    self.selAnchor = nil
    self._cursorAffinity = CURSOR_AFFINITY.forward
    self.scrollY = 0
    self:_invalidateAll()
    self:_reflow()
    self:_updateAutoHeight()
    self:_ensureCursorVisible()
    self:_resetBlink()
    self.undoHistory = {}
    self.redoHistory = {}
    self:_saveInitialState()
end

---@public
---@return string
function Textbox:getSelectedText()
    local from, to = self:_getSelRange()
    if not from then
        return ""
    end
    return utf8.sub(self.text, from + 1, to)
end

---@public
---@param newText string
function Textbox:replaceSelectedText(newText)
    self:_insertText(newText or "")
end

---@public
---@return boolean
function Textbox:focus()
    self.focused = true
    widget.focus(self.fakeTextbox)
    widget.setText(self.fakeTextbox, "")
    self._ignoreInputFrame = true
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
    self:_clearFakeTextboxPasteCoroutine(true)
    self.text = ""
    self.charLen = 0
    self.cursorPos = 0
    self.selAnchor = nil
    self.scrollY = 0
    self.undoHistory = {}
    self.redoHistory = {}
    self:_invalidateAll()
    self:_reflow()
    self.textCanvas:clear()
    self.carretCanvas:clear()
    self:_saveInitialState()
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
---@param fn fun(newSize: number[])
function Textbox:setOnSizeChange(fn)
    self.onSizeChange = fn
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
    self:_clearFakeTextboxPasteCoroutine(true)
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
    self._cursorAffinity = CURSOR_AFFINITY.forward
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
---@param ignore boolean
function Textbox:setIgnoreInputFrame(ignore)
    self._ignoreInputFrame = ignore
end

---@public
---@param size number
function Textbox:setFontSize(size)
    if self.fontSize == size then
        return
    end

    self.fontSize = size
    self:_destroyMeasureLabel()
    self:_setupMeasureLabel()

    local metrics = self:_measureFontMetrics()

    if not self._lineHeightExplicit then
        self.lineHeight = self:_resolveAutoLineHeight(metrics)
    else
        self.lineHeight = math.floor(self.lineHeight + 0.5)
    end

    self:_invalidateAll()
    self:_reflow()
    self:_updateAutoHeight()
    self:_ensureCursorVisible()
end

---@public
---@return number
function Textbox:getFontSize()
    return self.fontSize
end

---@public
---@param font string
function Textbox:setFont(font)
    if not font or font == "" then return end
    self.textFont = font

    self:_destroyMeasureLabel()
    self:_setupMeasureLabel()

    local metrics = self:_measureFontMetrics()

    if not self._lineHeightExplicit then
        self.lineHeight = self:_resolveAutoLineHeight(metrics)
    else
        self.lineHeight = math.floor(self.lineHeight + 0.5)
    end
    
    self:_invalidateAll()
    self:_reflow()
    self:_updateAutoHeight()
    self:_ensureCursorVisible()
end

---@public
---@return string
function Textbox:getFont()
    return self.textFont
end

---@public
---@param spacing number
function Textbox:setLineSpacing(spacing)
    local normalizedSpacing = math.max(0, math.floor((spacing or 0) + 0.5))
    if self.lineSpacing == normalizedSpacing then
        return
    end

    self.lineSpacing = normalizedSpacing
    self:_invalidateAll()
    self:_updateAutoHeight()
    self:_ensureCursorVisible()
end

---@public
---@return number
function Textbox:getLineSpacing()
    return self.lineSpacing
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
---@param number
function Textbox:setMaxHeight(maxHeight)
    self.maxHeight = maxHeight
    self:_updateAutoHeight()
end

---@public
---@return number
function Textbox:getMaxHeight()
    return self.maxHeight
end

---@public
---@param size number[] {width, height}
function Textbox:setSize(size)
    if not size then
        return
    end

    local width = math.max(1, math.floor((size[1] or self.rect[3]) + 0.5))
    local height = math.max(1, math.floor((size[2] or self.rect[4]) + 0.5))

    if self.rect[3] == width and self.rect[4] == height then
        return
    end

    self.currentHeight = height
    widget.setSize(self.path, { width, height })
    widget.setSize(self.textCanvasPath, { width, height })
    widget.setSize(self.carretCanvasPath, { width, height })
    widget.setSize(self.scrollAreaPath, { width + 20, height })

    self.rect = { 0, 0, width, height }
    self.wrapWidth = self:_getWrapWidth()

    self:_reflow()
    self:_updateAutoHeight()
    self:_invalidateAll()
    self:_ensureCursorVisible()
end

-- ─────────────────────────── lifecyle ────────────────────────────────

function Textbox.init()
    assert(pane, "Textbox: pane API not available. Include this script in an interface.")
end

function Textbox.update(dt)
    local events = input.events() or {}
    local mousePos = input.mousePosition()
    for _, tbx in pairs(activeTextboxes) do
        if tbx.setupDone then
            tbx:_processInput(dt, events, mousePos);
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
