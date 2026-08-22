--- Created by https://github.com/Mofurka/StarboundTextboxInterface
--- DateTime: 20.03.2026 11:04
--- Please credit if you use or modify this code, thanks!
--- Пожалуста, если вы используете или изменяете этот код, указывайте авторство, спасибо!
require("/scripts/vec2.lua")
require("/scripts/rect.lua")
require("/interface/StarboundTextboxInterface/scripts/utf8/utf8.lua")

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
    caretCanvas = "__",
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
local REFLOW_YIELD_INTERVAL = 2000
local INCREMENTAL_REFLOW_MIN = 4000
local INCREMENTAL_REFLOW_MAX_SPAN = 20000
local MAX_SYNC_REFLOW_CHARS = 30000
local EMPTY_LINE_HIGHLIGHT_WIDTH = 2

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

local function logInfo(msg, ...)
    sb.logInfo("[tbx.lua] " .. msg, ...)
end

---@param key string
---@param formatString string
---@param formatValues any
local function logMap(key, formatString, formatValues)
    sb.setLogMap("^yellow;[tbx.lua]^reset; " .. key, formatString, formatValues)
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
    parentWidgetPath = nil,
    path = nil,
    textCanvas = nil,
    textCanvasPath = nil,
    caretCanvas = nil,
    caretCanvasPath = nil,
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
    scrollLinesPerWheel = 1,
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
    _heldTimerIntervalsProcessed = 0,
    _ignoreInputFrame = false,
    _cursorAffinity = CURSOR_AFFINITY.forward,
    _lineHeightExplicit = nil,
    _fakeTextboxPasteCoroutine = nil,

    -- When true, _redlow yields periodicaly
    _reflowYieldEnabled = false,

    -- TODO(nightly): temporary shift +enter anti dupe \n.
    _fakeInsertedNewline = false,


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
---@field scrollLinesPerWheel number?
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
    inst.scrollLinesPerWheel = options.scrollLinesPerWheel or inst.scrollLinesPerWheel
    inst.verticalAlign = options.verticalAlign or "bottom"
    inst.textOffsetY = options.textOffsetY or 0
    inst.parentWidgetPath = widgetName
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
        captureMouseEvents = false, captureKeyboardEvents = false,
    }, WIDGET_SHORTS.caretCanvas)
    inst.caretCanvasPath = lytPath .. dotWidget(WIDGET_SHORTS.caretCanvas)

    -- Fake textbox for input capture
    widget.addChild(lytPath, {
        type = "textbox", position = { -1000, -1000 }, maxWidth = 200,
        textAlign = "left", callback = "null", enterKey = "null",
        escapeKey = "null", regex = "[\\s\\S]*"
    }, WIDGET_SHORTS.fakeTextbox)
    inst.fakeTextbox = lytPath .. dotWidget(WIDGET_SHORTS.fakeTextbox)

    -- Bind canvases
    inst.textCanvas = widget.bindCanvas(inst.textCanvasPath)
    inst.caretCanvas = widget.bindCanvas(inst.caretCanvasPath)

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
    widget.setSize(inst.caretCanvasPath, canvasSize)
    widget.setSize(inst.scrollAreaPath, { width + 20, height })

    inst.rect = { 0, 0, width, height }
    inst.wrapWidth = width - PAD * 2

    inst:_reflow()
    inst.scrollY = 0
    inst:_invalidateAll()
    inst:_saveInitialState()
    if DEBUG then
        logInfo("Textbox setup complete: %s", sb.print(inst))
    end
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
    local canvasH = self.caretCanvas:size()[2]
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
---@param fromChar number
---@param toChar number
---@return table lines
function Textbox:_wrapRange(fromChar, toChar)
    local lines = {}

    local text = self.text or ""
    local maxW = math.max(0, self:_getWrapWidth())

    local lineStartCI = fromChar
    local lineChars = {}
    local charXs = {}
    local lineWidth = 0
    local lastBreakIndex

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

    local bi = utf8.offset(text, fromChar) or (#text + 1)
    for ci = fromChar, toChar do
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

        if self._reflowYieldEnabled and ci % REFLOW_YIELD_INTERVAL == 0 then
            local co, ismain = coroutine.running()
            if co and not ismain then
                coroutine.yield()
            end
        end
    end

    if lineStartCI <= toChar then
        flushLine(toChar, false)
    elseif toChar >= self.charLen then
        lines[#lines + 1] = {
            startIdx = lineStartCI,
            endIdx = lineStartCI - 1,
            charXs = {},
            width = 0,
            text = "",
        }
    end

    return lines
end

---@protected
function Textbox:_reflow()
    self.lines = self:_wrapRange(1, self.charLen)
end

---@protected
---@param charIdx number
---@return number lineIndex
function Textbox:_lineIndexOfChar(charIdx)
    local lines = self.lines
    local n = #lines
    if n == 0 then
        return 1
    end
    if charIdx < 1 then
        return 1
    end
    local lo, hi, ans = 1, n, 1
    while lo <= hi do
        local mid = math.floor((lo + hi) / 2)
        if lines[mid].startIdx <= charIdx then
            ans = mid
            lo = mid + 1
        else
            hi = mid - 1
        end
    end
    return ans
end

---@protected
function Textbox:_paragraphStartLine(idx)
    while idx > 1 and not self.lines[idx - 1].endsWithNewline do
        idx = idx - 1
    end
    return idx
end

---@protected
function Textbox:_paragraphEndLine(idx)
    local n = #self.lines
    while idx < n and not self.lines[idx].endsWithNewline do
        idx = idx + 1
    end
    return idx
end

---@protected
---@param opts table? { onChanged = boolean, pushUndo = boolean, actionType = string }
function Textbox:_startReflowCoroutine(opts)
    opts = opts or {}
    self._fakeTextboxPasteCoroutine = coroutine.create(function()
        self._reflowYieldEnabled = true
        self:_reflow()
        self._reflowYieldEnabled = false
        coroutine.yield()

        self:_updateAutoHeight()
        self:_ensureCursorVisible()
        self:_resetBlink()
        self:_invalidateAll()

        if opts.onChanged and self.onChanged then
            self.onChanged(self.text)
        end
        if opts.pushUndo then
            self:_pushUndoState(opts.actionType or ACTION_TYPES.other, 0)
        end
    end)
end

---@protected
---@param editStart number? 0
---@param newInsertedLen number
---@param oldCharLen number
---@param actionType string
---@param suppressOnChanged boolean?
---@return boolean
function Textbox:_reflowAfterEdit(editStart, newInsertedLen, oldCharLen, actionType, suppressOnChanged)
    if editStart == nil or #self.lines == 0 or self.charLen <= INCREMENTAL_REFLOW_MIN then
        self:_reflow()
        return false
    end

    local delta = self.charLen - oldCharLen
    local oldRemovedLen = newInsertedLen - delta

    -- Locate the touched old paragraph range (old lines still describe the old text).
    local leftChar = math.max(1, math.min(editStart, oldCharLen))
    local oldFirst = self:_paragraphStartLine(self:_lineIndexOfChar(leftChar))

    local rightChar = editStart + oldRemovedLen + 1
    local rightLineIdx
    if rightChar > oldCharLen then
        rightLineIdx = #self.lines
    else
        rightLineIdx = self:_lineIndexOfChar(rightChar)
    end
    local oldLast = self:_paragraphEndLine(rightLineIdx)

    if oldFirst < 1 or oldLast > #self.lines or oldLast < oldFirst then
        self:_reflow()
        return false
    end

    local pStart = self.lines[oldFirst].startIdx
    local pEndOld = self.lines[oldLast].endIdx
    local pEnd = pEndOld + delta

    if pEnd >= self.charLen then
        pEnd = self.charLen
        oldLast = #self.lines
    end

    if pStart < 1 or pEnd < pStart or (pEnd - pStart) > INCREMENTAL_REFLOW_MAX_SPAN then
        self:_startReflowCoroutine({
            onChanged = not suppressOnChanged,
            pushUndo = not suppressOnChanged,
            actionType = actionType,
        })
        return true
    end

    local newParaLines = self:_wrapRange(pStart, pEnd)

    local newLines = {}
    for i = 1, oldFirst - 1 do
        newLines[#newLines + 1] = self.lines[i]
    end
    for i = 1, #newParaLines do
        newLines[#newLines + 1] = newParaLines[i]
    end
    for i = oldLast + 1, #self.lines do
        local ln = self.lines[i]
        ln.startIdx = ln.startIdx + delta
        ln.endIdx = ln.endIdx + delta
        if ln.visibleEndIdx then
            ln.visibleEndIdx = ln.visibleEndIdx + delta
        end
        newLines[#newLines + 1] = ln
    end
    self.lines = newLines
    return false
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
    local sz = self.caretCanvas:size()
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

    local charIdx
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
--- BEHOLD MY MAGNUM OPUS FOR LUA INSTRUCTIONS SAVE
--- Now we are using the builtin instead of our custom one
function Textbox:_splice(from, to)
    local text = self.text
    local fromByte = utf8.offset(text, from + 1) or (#text + 1)
    local toByte = utf8.offset(text, to + 1) or (#text + 1)
    self.text = text:sub(1, fromByte - 1) .. text:sub(toByte)
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
        self._lastActionType = nil
        self._timeSinceLastAction = self._actionGroupTimeThreshold
    end
    local editStart = self.cursorPos
    local insertedLen = utf8.len(str)
    local text = self.text
    local cutByte = utf8.offset(text, self.cursorPos + 1) or (#text + 1)
    self.text = text:sub(1, cutByte - 1) .. str .. text:sub(cutByte)
    self.cursorPos = self.cursorPos + insertedLen
    self.selAnchor = nil
    self:_onTextChanged(ACTION_TYPES.insert, suppressOnChanged, editStart, insertedLen)
end

---@protected
function Textbox:_deleteBack()
    if self:_deleteSelection() then
        self:_onTextChanged(ACTION_TYPES.backspace, nil, self.cursorPos, 0);
        return
    end
    if self.cursorPos <= 0 then
        return
    end
    self:_splice(self.cursorPos - 1, self.cursorPos)
    self.cursorPos = self.cursorPos - 1
    self.selAnchor = nil
    self:_onTextChanged(ACTION_TYPES.backspace, nil, self.cursorPos, 0)
end
---@protected
function Textbox:_deleteForward()
    if self:_deleteSelection() then
        self:_onTextChanged(ACTION_TYPES.delete, nil, self.cursorPos, 0);
        return
    end
    if self.cursorPos >= self.charLen then
        return
    end
    local editStart = self.cursorPos
    self:_splice(self.cursorPos, self.cursorPos + 1)
    self.selAnchor = nil
    self:_onTextChanged(ACTION_TYPES.delete, nil, editStart, 0)
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
        self:_onTextChanged(ACTION_TYPES.backspace, nil, self.cursorPos, 0);
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
        self:_onTextChanged(ACTION_TYPES.backspace, nil, newPos, 0)
    end
end
---@protected
function Textbox:_deleteWordForward()
    if self:_deleteSelection() then
        self:_onTextChanged(ACTION_TYPES.delete, nil, self.cursorPos, 0);
        return
    end
    if self.cursorPos >= self.charLen then
        return
    end
    local editStart = self.cursorPos
    local newPos = self:_wordBoundaryRight(self.cursorPos)
    if newPos > self.cursorPos then
        self:_splice(self.cursorPos, newPos)
        self.selAnchor = nil
        self:_onTextChanged(ACTION_TYPES.delete, nil, editStart, 0)
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
    if self.charLen > MAX_SYNC_REFLOW_CHARS then
        self:_startReflowCoroutine({ onChanged = not suppressOnChanged })
        return
    end

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
---@param actionType string
---@param suppressOnChanged boolean?
---@param editStart number? 0
---@param newInsertedLen number?
function Textbox:_onTextChanged(actionType, suppressOnChanged, editStart, newInsertedLen)
    local oldCharLen = self.charLen
    self.charLen = utf8.len(self.text)
    self.cursorPos = clamp(self.cursorPos, 0, self.charLen)
    self._cursorAffinity = CURSOR_AFFINITY.forward

    if self.selAnchor ~= nil then
        self.selAnchor = clamp(self.selAnchor, 0, self.charLen)
    end

    self:_invalidateAll()

    if self:_reflowAfterEdit(editStart, newInsertedLen or 0, oldCharLen, actionType, suppressOnChanged) then
        return
    end

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
    local h = self.caretCanvas:size()[2]
    return math.max(1, h)
end
---@protected
---@return number
function Textbox:_getFullyVisibleLineCount()
    local lineAdvance = self:_getLineAdvance()
    if lineAdvance <= 0 then
        return 1
    end
    local usable = self:_getViewHeight() - PAD - self.lineHeight
    if usable < 0 then
        return 1
    end
    return math.max(1, math.floor(usable / lineAdvance) + 1)
end

---@protected
function Textbox:_getMaxScroll()
    local hidden = #self.lines - self:_getFullyVisibleLineCount()
    if hidden <= 0 then
        return 0
    end
    return hidden * self:_getLineAdvance()
end

---@protected
function Textbox:_clampScroll(scrollY)
    local lineAdvance = self:_getLineAdvance()
    local maxScroll = self:_getMaxScroll()
    if lineAdvance <= 0 then
        return clamp(scrollY, 0, maxScroll)
    end
    return clamp(math.floor(scrollY / lineAdvance + 0.5) * lineAdvance, 0, maxScroll)
end

---@protected
function Textbox:_getVisibleLineRange()
    local total = #self.lines
    if total == 0 then
        return 1, 1
    end

    local lineAdvance = self:_getLineAdvance(total)
    if lineAdvance <= 0 then
        return 1, total
    end

    local first = math.floor(self.scrollY / lineAdvance) + 1
    local last = first + self:_getFullyVisibleLineCount() - 1

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
    local lineAdvance = self:_getLineAdvance()
    if lineAdvance <= 0 then
        self:_invalidateCaret()
        return
    end

    local li = self:_cursorToLineX(self.cursorPos)
    local visibleLines = self:_getFullyVisibleLineCount()

    local firstLine = math.floor(self.scrollY / lineAdvance) + 1
    if li < firstLine then
        firstLine = li
    elseif li > firstLine + visibleLines - 1 then
        firstLine = li - visibleLines + 1
    end

    local old = self.scrollY
    self.scrollY = clamp((firstLine - 1) * lineAdvance, 0, self:_getMaxScroll())

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
    -- TODO(nightly): reset the shif + enter antidupe flag each frame.
    self._fakeInsertedNewline = false

    if self.caretTimer >= CARET_BLINK_INTERVAL then
        self.caretTimer = self.caretTimer - CARET_BLINK_INTERVAL
        self.caretVisible = not self.caretVisible
        self:_invalidateCaret()
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
                self._heldTimerIntervalsProcessed = 0
            end
        end
    end

    if self._ignoreInputFrame then
        self._ignoreInputFrame = false
        return
    end

    if self._fakeTextboxPasteCoroutine then
        self:_resumeFakeTextboxPasteCoroutine()
        return
    end

    self:_processMouseEvents(events, mousePos)
    if not self.focused then
        return
    end

    if self._heldKey then
        self._heldTimer = self._heldTimer + dt
        if self._heldTimer >= KEY_REPEAT_DELAY then
            local elapsed = self._heldTimer - KEY_REPEAT_DELAY
            local intervalsElapsed = math.floor(elapsed / KEY_REPEAT_INTERVAL)
            if intervalsElapsed > self._heldTimerIntervalsProcessed then
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
                self._heldTimerIntervalsProcessed = intervalsElapsed
            end
        end
    end

    self:_pollFakeTextbox()
    if self._fakeTextboxPasteCoroutine then
        return
    end
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

    local parts = self:_splitWidgetPath(self.parentWidgetPath)
    if DEBUG then
        logInfo("Widget path parts: %s", sb.printJson(parts))
    end
    if #parts == 0 then
        self._firstParent = self.parentWidgetPath
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
        if DEBUG then
            logInfo("Child chain part %s (%s) pos: %s", tostring(i), currentPath, sb.printJson(childPos))
        end
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

    return widget.getPosition(self.parentWidgetPath)
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
    local size = vec2.mul(self.caretCanvas:size(), scale)

    return {
        screenPos[1],
        screenPos[2],
        screenPos[1] + size[1],
        screenPos[2] + size[2]
    }
end

---@protected
function Textbox:_screenToLocalMouse(mouseScreen, clampToCanvas)
    if not self.caretCanvas then
        return nil
    end

    local widgetRect = self:_getWidgetScreenRect()
    local scale = interface.scale()

    local localMouse = {
        (mouseScreen[1] - widgetRect[1]) / scale,
        (mouseScreen[2] - widgetRect[2]) / scale
    }

    if clampToCanvas then
        local sz = self.caretCanvas:size()
        localMouse[1] = clamp(localMouse[1], 0, sz[1])
        localMouse[2] = clamp(localMouse[2], 0, sz[2])
    end

    if DEBUG then
        logMap("Textbox:_screenToLocalMouse" .. self.uuid, "%s", sb.printJson({
            mouseScreen = mouseScreen,
            widgetRect = widgetRect,
            localMouse = localMouse,
            canvasMouse = self.caretCanvas and self.caretCanvas:mousePosition(),
            scale = scale
        }))
    end

    return localMouse, widgetRect
end

---@protected
function Textbox:_getMouseHit(mouseScreen)
    if not self.caretCanvas then
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
    if not self.caretCanvas then
        return
    end

    for _, ev in ipairs(events) do
        if ev.type == "MouseWheel" and ev.data and self.focused then
            local hit = self:_getMouseHit(mouseScreen)
            if hit then
                local lineAdvance = self:_getLineAdvance()
                local step = self.scrollLinesPerWheel or 3
                self.scrollY = self:_clampScroll(self.scrollY - ev.data.mouseWheel * lineAdvance * step)
                self:_invalidateCaret()
                self.textDirty = true
            end

        elseif ev.type == "MouseButtonDown" and ev.data
                and ev.data.mouseButton == "MouseLeft" then
            self._mouseLeftHeld = true

            local hit, localMouse = self:_getMouseHit(mouseScreen)

            if hit and not widget.hasFocus(self.caretCanvasPath) then
                hit = false
            end

            if hit then
                self:focus()
                local pos, clickedLi = self:_xyToCursor(localMouse[1], localMouse[2])
                self._cursorAffinity = self:_determineClickAffinity(pos, clickedLi)

                local isSameClickSpot = false
                if self._doubleClickTimer > 0 and self._lastClickMouse then
                    local dx = localMouse[1] - self._lastClickMouse[1]
                    local dy = localMouse[2] - self._lastClickMouse[2]
                    isSameClickSpot = (dx * dx + dy * dy) <= (DOUBLE_CLICK_MAX_DISTANCE * DOUBLE_CLICK_MAX_DISTANCE)
                end

                if isSameClickSpot then
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

        -- TODO(nightly): flag that the faketbx already caried a newline
        if txt:find("\n", 1, true) then
            self._fakeInsertedNewline = true
        end

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
    self._reflowYieldEnabled = false

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
        --  replace
        self:_deleteSelection()

        local cur = self.text
        local cutByte = utf8.offset(cur, self.cursorPos + 1) or (#cur + 1)
        self.text = cur:sub(1, cutByte - 1) .. txt .. cur:sub(cutByte)
        self.cursorPos = self.cursorPos + totalChars
        self.selAnchor = nil
        self.charLen = utf8.len(self.text)
        coroutine.yield()

        -- reflow
        self._reflowYieldEnabled = true
        self:_reflow()
        coroutine.yield()
        self:_updateAutoHeight()
        self._reflowYieldEnabled = false
        coroutine.yield()

        -- final
        self.cursorPos = clamp(self.cursorPos, 0, self.charLen)
        self._cursorAffinity = CURSOR_AFFINITY.forward
        self:_ensureCursorVisible()
        self:_resetBlink()
        self:_invalidateAll()

        if self.onChanged then
            self.onChanged(self.text)
        end
        self:_pushUndoState(ACTION_TYPES.paste, 0)
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
    [KEYS.Backspace] = function(self, ctrl, _)
        if ctrl then
            self:_deleteWordBack()
        else
            self:_deleteBack()
        end
    end,
    ---@param self Textbox
    [KEYS.Delete] = function(self, ctrl, _)
        if ctrl then
            self:_deleteWordForward()
        else
            self:_deleteForward()
        end
    end,
    ---@param self Textbox
    [KEYS.Return] = function(self, _, shift)
        if shift then
            -- TODO(osb-nightly): on nightly OSB the fakeTextbox already inserted
            if not self._fakeInsertedNewline then
                self:_insertText("\n")
            end
        elseif self.onEnterKey then
            self.onEnterKey()
        end
    end,
    ---@param self Textbox
    [KEYS.Escape] = function(self, _, _)
        if self.onEscapeKey then
            self:onEscapeKey()
        end
    end,
    ---@param self Textbox
    [KEYS.Tab] = function(self, _, _)
        self:_insertText(self.tabSpaces or "  ")
    end,
    ---@param self Textbox
    [KEYS.Left] = function(self, ctrl, shift)
        if ctrl then
            self:_moveCursorWordLeft(shift)
        else
            self:_moveCursorLeft(shift)
        end
    end,
    ---@param self Textbox
    [KEYS.Right] = function(self, ctrl, shift)
        if ctrl then
            self:_moveCursorWordRight(shift)
        else
            self:_moveCursorRight(shift)
        end
    end,
    ---@param self Textbox
    [KEYS.Up] = function(self, _, shift)
        self:_moveCursorUp(shift)
    end,
    ---@param self Textbox
    [KEYS.Down] = function(self, _, shift)
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
    [KEYS.A] = function(self, ctrl, _)
        if not ctrl then
            return
        end
        self.selAnchor = 0
        self.cursorPos = self.charLen
        self:_resetBlink()
    end,
    ---@param self Textbox
    [KEYS.C] = function(self, ctrl, _)
        if not ctrl then
            return
        end
        local sel = self:getSelectedText()
        if sel ~= "" then
            clipboard.setText(sel)
        end
    end,
    ---@param self Textbox
    [KEYS.X] = function(self, ctrl, _)
        if not ctrl then
            return
        end
        local sel = self:getSelectedText()
        if sel ~= "" then
            clipboard.setText(sel)
            self:_deleteSelection()
            self:_onTextChanged(ACTION_TYPES.delete, nil, self.cursorPos, 0)
        end
    end,
    ---@param self Textbox
    [KEYS.Z] = function(self, ctrl, shift)
        if not ctrl then
            return
        end
        if shift then
            self:_redo()
        else
            self:_undo()
        end
    end,
    ---@param self Textbox
    [KEYS.Y] = function(self, ctrl, _)
        if ctrl then
            self:_redo()
        end
    end,
}

---@protected
function Textbox:_processKeys(events)
    for _, ev in ipairs(events) do
        if ev.type == "KeyDown" and ev.data then
            local key = ev.data.key
            local mods = ev.data.mods or {}
            local shift = hasMod(mods, KEYS.LShift) or hasMod(mods, KEYS.RShift)
            local ctrl = hasMod(mods, KEYS.LCtrl) or hasMod(mods, KEYS.RCtrl)

            local handler = KEY_DISPATCH[key]
            if handler then
                handler(self, ctrl, shift)
                if self._fakeTextboxPasteCoroutine then
                    return
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

    if DEBUG then
        canvas:drawRect(
                { 0, 0, canvas:size()[1], canvas:size()[2] },
                { 255, 0, 0, 100 }
        )
    end

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
                    if DEBUG then
                        logInfo("DRAW LINE %s Y: %s", sb.print(li), sb.print(top - vInset))
                    end
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
    local canvas = self.caretCanvas
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

                -- Ensure empty lines also get highlighted by drawing at least a minimal width
                if x2 <= x1 then
                    x2 = x1 + EMPTY_LINE_HIGHLIGHT_WIDTH
                end

                canvas:drawRect({ x1, textBot, x2, textTop }, self.selectionColor)
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
function Textbox:_snapHeightToWholeLines(height)
    local lineAdvance = self:_getLineAdvance()
    if lineAdvance <= 0 then
        return height
    end

    local usable = height - PAD * 2 - self.lineHeight
    if usable < 0 then
        return height
    end

    local fitLines = math.floor(usable / lineAdvance) + 1
    return math.min(height, (fitLines - 1) * lineAdvance + self.lineHeight + PAD * 2)
end

---@protected
function Textbox:_updateAutoHeight()
    if not self.maxHeight then
        return
    end

    local contentHeight = self:_requiredHeightForLines(#self.lines)
    local newHeight = clamp(contentHeight, self.minHeight, self.maxHeight)

    if newHeight < contentHeight then
        newHeight = math.max(self.minHeight, self:_snapHeightToWholeLines(newHeight))
    end

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
        widget.setSize(self.caretCanvasPath, canvasSize)

        -- scroll area
        widget.setSize(self.scrollAreaPath, { width + 20, height })

        self.rect = newRect

        self:_invalidateAll()
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
    self.undoHistory = {}
    self.redoHistory = {}

    -- FOR LARGER TEXT 🙃
    if self.charLen > MAX_SYNC_REFLOW_CHARS then
        self:_startReflowCoroutine({})
        self:_saveInitialState()
        return
    end

    self:_reflow()
    self:_updateAutoHeight()
    self:_ensureCursorVisible()
    self:_resetBlink()
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
    self.caretCanvas:clear()
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
---@param lines number the name says by itself
function Textbox:setScrollLinesPerWheel(lines)
    self.scrollLinesPerWheel = math.max(1, math.floor((tonumber(lines) or 1) + 0.5))
end

---@public
---@return number
function Textbox:getScrollLinesPerWheel()
    return self.scrollLinesPerWheel or 3
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
    self.scrollY = self:_clampScroll(scrollY)
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
    if not font or font == "" then
        return
    end
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
---@param maxHeight
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
    widget.setSize(self.caretCanvasPath, { width, height })
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
            if not tbx._fakeTextboxPasteCoroutine then
                tbx:_draw()
            end
        end
    end
end

function Textbox.uninit()
    for _, tbx in pairs(activeTextboxes) do
        tbx:_cleanup()
    end
    activeTextboxes = {}
end
