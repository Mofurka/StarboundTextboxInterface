---@type MarkdownParser[]
local activeParsers = {}

---@param parser MarkdownParser
local function addParser(parser)
    activeParsers[parser.uuid] = parser
end

---@param uuid string
---@return MarkdownParser?
local function removeParser(uuid)
    local parser = activeParsers[uuid]
    if parser then
        activeParsers[uuid] = nil
    end
    return parser
end

---@param uuid string
---@return MarkdownParser?
local function getParserByUuid(uuid)
    return activeParsers[uuid]
end

local oldInit = init
local oldUpdate = update
local oldUninit = uninit

function init()
    if oldInit then
        oldInit()
    end
    sb.logInfo("[md.lua] Active MarkdownParsers: %s", #activeParsers)
    MarkdownParser.init()
end

function update(dt)

    if oldUpdate then
        oldUpdate(dt)
    end
    MarkdownParser.update(dt)
end

function uninit()
    if oldUninit then
        oldUninit()
    end
    MarkdownParser.uninit()
end

require("/scripts/utils/utf8.lua")
require("/scripts/vec2.lua")
---@class MarkdownParser
---@field scrollConfig MarkdownParserScrollConfig
MarkdownParser = {
    renders = {}, -- id -> { tokens, contentH, offsetY }
    blocks = {}, -- ordered list of block IDs on this instance
    scroll = 0,
    totalH = 0,
    nextId = 1,
    measureWidget = "_md_sz",
    measureCache = {},
    setupDone = false,
    textCanvas = nil, -- canvas used for rendering text
    mouseCanvas = nil, -- canvas used for mouse event capture (captureMouseEvents)
    thumbCanvas = nil, -- canvas used for drawing scrollbar thumb when scroll buttons are held

    _thumbDragging = false,
    _thumbDragOffset = 0,
    _holdInitiated = false,

    scrollConfig = {
        scrollEnabled = false
    },

    uuid = nil,
    _mouseLeftHeld = false,
    blockSeparator = nil,

    lytPath = nil,
    scrollAreaPath = nil,
    textCanvasPath = nil,
    mouseCanvasPath = nil,
    thumbCanvasPath = nil,
    parentWidgetPath = nil,

    _screenOffset = { 0, 0 },
    _paneFeature = {},
}
MarkdownParser.__index = MarkdownParser

-- ─────────────────────────── Constants ───────────────────────────────────────


local FONT_SIZE = {
    h1 = 16, h2 = 14, h3 = 12, h4 = 10, h5 = 9, h6 = 8,
    p = 8, li = 8, code_block = 8, table_cell = 7,
}

local LINE_HEIGHT = {
    h1 = 20, h2 = 18, h3 = 16, h4 = 14, h5 = 12, h6 = 11,
    p = 12, li = 12, code_block = 11,
    hr = 4, blank = 7, table_row = 14,
}

local PARAGRAPH_GAP = 3

local COLOR = {
    h1 = { 255, 255, 255, 255 },
    h2 = { 240, 240, 240, 255 },
    h3 = { 220, 220, 220, 255 },
    h4 = { 200, 200, 200, 255 },
    h5 = { 180, 180, 180, 255 },
    h6 = { 160, 160, 160, 255 },
    p = { 255, 255, 255, 255 },
    li = { 255, 255, 255, 255 },
    code_text = { 100, 210, 255, 255 },
    code_bg = { 15, 15, 40, 210 },
    hr = { 180, 180, 180, 140 },
    quote_bg = { 30, 22, 10, 200 },
    quote_text = { 220, 200, 155, 255 },
    quote_bar = { 185, 140, 45, 235 },
    table_border = { 150, 150, 150, 200 },
    table_header_bg = { 40, 40, 60, 220 },
    table_row_bg = { 20, 20, 30, 180 },
    table_text = { 255, 255, 255, 255 },
    table_header_text = { 255, 255, 255, 255 },
}

local INDENT_PX = 10
local PAD = 4
local BLOCK_GAP = 6
local QUOTE_PAD_LEFT = 8
local QUOTE_BAR_W = 3
local DEBUG = false

local WIDGET_SHORTS = {
    lyt = "__md_lyt_", -- + uuid
    scrollArea = "__md_sa_",
    textCanvas = "__md_cv_txt",
    mouseCanvas = "__md_cv_ms",
    thumbCanvas = "__md_cv_sb",
    measureLabel = "___md_sz_", -- + uuid
}

local function dotWidget(name)
    return "." .. name
end

local function logInfo(msg, ...)
    if DEBUG and msg and msg ~= "" then
        sb.logInfo("[md.lua] " .. msg, ...)
    end
end

---@param key string
---@param formatString string
---@param formatValues any
local function logMap(key, formatString, formatValues)
    sb.setLogMap("^yellow;[md.lua]^reset; " .. key, formatString, formatValues)
end

-- ─────────────────────────── Scrollbar constants ─────────────────────────────
local SCROLL_BTN_H = 11
local SCROLL_TRACK_COLOR = { 15, 15, 25, 200 }
local SCROLL_THUMB_COLOR = { 100, 100, 120, 220 }
local SCROLL_THUMB_HOVER_COLOR = { 150, 155, 175, 255 }
local SCROLL_BUTTON_SPEED = 160

-- ─────────────────────────── Constructor ─────────────────────────────────────

function MarkdownParser.new()
    local self = setmetatable({}, MarkdownParser)
    self.uuid = sb.makeUuid()
    return self
end

-- ─────────────────────────── Private helpers ─────────────────────────────────

local function applyInline(text)
    -- underscores first (before ** /* inject "hobo_b" etc. containing underscores) cuz the font contains underscore in it
    text = text:gsub("___(.-)___", "%1") -- italic underlined, not implemented yet TODO
    text = text:gsub("__(.-)__", "%1") -- underlined, not implemented yet TODO
    text = text:gsub("_(.-)_", "^font=hobo_i;%1^reset;") -- italic
    -- then stars
    text = text:gsub("%*%*%*(.-)%*%*%*", "^font=hobo_bi;%1^reset;") -- bold italic
    text = text:gsub("%*%*(.-)%*%*", "^font=hobo_b;%1^reset;") -- bold
    text = text:gsub("%*(.-)%*", "^font=hobo_i;%1^reset;") -- italic
    text = text:gsub("`(.-)`", "^cyan;%1^reset;") -- inline code
    text = text:gsub("%[(.-)%]%((.-)%)", "%1") -- links, not implemented yet TODO
    return text
end

local function lex(text)
    local tokens = {}
    local inCode = false
    local codeLang, codeLines = "", {}
    local quoteLines = {}
    local tableLines = {}
    local inTable = false

    local function flushCode()
        if #codeLines > 0 then
            tokens[#tokens + 1] = { type = "code_block", lines = codeLines, lang = codeLang }
            codeLines, codeLang = {}, ""
        end
    end

    local function flushQuote()
        while #quoteLines > 0 and quoteLines[#quoteLines]:match("^%s*$") do
            table.remove(quoteLines)
        end
        if #quoteLines > 0 then
            tokens[#tokens + 1] = { type = "blockquote", lines = quoteLines }
            quoteLines = {}
        end
    end

    local function flushTable()
        if #tableLines > 0 then
            -- Parse table structure
            local header = {}
            local alignments = {}
            local rows = {}

            -- First line is header
            if tableLines[1] then
                for cell in tableLines[1]:gmatch("|([^|]*)") do
                    if cell:match("%S") then
                        header[#header + 1] = cell:match("^%s*(.-)%s*$") or cell
                    end
                end
            end

            -- Second line is separator with alignment
            if tableLines[2] then
                for sep in tableLines[2]:gmatch("|([^|]*)") do
                    if sep:match("%S") then
                        local trimmed = sep:match("^%s*(.-)%s*$") or sep
                        local align = "left"
                        if trimmed:match("^:.-:$") then
                            align = "center"
                        elseif trimmed:match(":$") then
                            align = "right"
                        end
                        alignments[#alignments + 1] = align
                    end
                end
            end

            -- Remaining lines are data rows
            for i = 3, #tableLines do
                local row = {}
                for cell in tableLines[i]:gmatch("|([^|]*)") do
                    if cell:match("%S") or #row > 0 then
                        row[#row + 1] = cell:match("^%s*(.-)%s*$") or cell
                    end
                end
                if #row > 0 then
                    rows[#rows + 1] = row
                end
            end

            if #header > 0 and #rows > 0 then
                tokens[#tokens + 1] = {
                    type = "table",
                    header = header,
                    alignments = alignments,
                    rows = rows
                }
            end

            tableLines = {}
            inTable = false
        end
    end

    for line in (text .. "\n"):gmatch("([^\n]*)\n") do
        local fence = line:match("^%s*```(.*)$")
        if fence ~= nil then
            flushQuote()
            flushTable()
            if inCode then
                inCode = false;
                flushCode()
            else
                inCode = true;
                codeLang = fence
            end
        elseif inCode then
            codeLines[#codeLines + 1] = line
        else
            local isTableLine = line:match("^%s*|") and line:match("|%s*$")

            if isTableLine then
                flushQuote()
                inTable = true
                tableLines[#tableLines + 1] = line
            else
                flushTable()

                local quoteLine = line:match("^%s*>%s?(.*)$")
                if quoteLine then
                    quoteLines[#quoteLines + 1] = quoteLine
                else
                    flushQuote()
                    local level, heading = line:match("^(#+)%s+(.+)$")
                    if heading then
                        tokens[#tokens + 1] = { type = "h" .. math.min(#level, 6), text = heading }
                    elseif line:match("^%s*[-*+]%s+(.+)$") then
                        local indent = #(line:match("^(%s*)") or "")
                        local content = line:match("^%s*[-*+]%s+(.+)$")
                        tokens[#tokens + 1] = { type = "li", text = content, indent = math.floor(indent / 2) }
                    elseif line:match("^%s*%d+%.%s+(.+)$") then
                        local indent = #(line:match("^(%s*)") or "")
                        local num = line:match("^%s*(%d+)%.")
                        local content = line:match("^%s*%d+%.%s+(.+)$")
                        tokens[#tokens + 1] = { type = "li", text = num .. ". " .. content, indent = math.floor(indent / 2) }
                    elseif line:match("^%s*[-*_][%s%-*_]*$") and #line:gsub("[%s%-*_]", "") == 0 and #line >= 3 then
                        tokens[#tokens + 1] = { type = "hr" }
                    elseif line:match("^%s*$") then
                        tokens[#tokens + 1] = { type = "blank" }
                    else
                        tokens[#tokens + 1] = { type = "p", text = line }
                    end
                end
            end
        end
    end

    if inCode then
        flushCode()
    end
    flushQuote()
    flushTable()
    return tokens
end

local function stripDirectives(text)
    text = text or ""
    text = text:gsub("%^%w+=[^;]*;", "")
    text = text:gsub("%^%w+;", "")
    return text
end

local function estimateLines(text, maxChars)
    text = stripDirectives(text)
    if not text or text == "" or maxChars <= 0 then
        return 1
    end
    local lines, col = 1, 0
    for word in text:gmatch("%S+") do
        if col + #word + 1 > maxChars then
            lines = lines + 1
            col = #word
        else
            col = col + (col > 0 and 1 or 0) + #word
        end
    end
    return lines
end

local function debugMessage(msg, ...)
    if DEBUG and msg and msg ~= "" then
        sb.logInfo("[md.lua] " .. msg, ...)
    end
end



-- ─────────────────────────── Setup / factory ─────────────────────────────────
---@class MarkdownParserOptions
---@field rect RectI?  Optional {x1,y1,x2,y2} rect for the canvases. By default they will be sized to fill the parent widget.
---@field screenOffset number[]?  {x, y} nudge (in unscaled UI pixels) applied when converting the global mouse into local coordinates. Default {0, 0}.


---@param widgetName string   full widget path to use as parent for the canvases
---@param options    table?
---@return MarkdownParser
function MarkdownParser:setup(widgetName, options)
    options = options or {}

    local instance = MarkdownParser.new()
    instance.setupDone = true

    local isChild = widgetName:find("%.") ~= nil

    local lytShort = WIDGET_SHORTS.lyt .. instance.uuid
    local scrollShort = WIDGET_SHORTS.scrollArea
    local textShort = WIDGET_SHORTS.textCanvas
    local mouseShort = WIDGET_SHORTS.mouseCanvas

    local rect

    if options.rect then
        rect = options.rect
    elseif not isChild then
        local sz = widget.getSize(widgetName)
        rect = { 0, 0, sz[1], sz[2] }
    else
        rect = { 0, 0, 200, 200 }
        logInfo("Warning: No rect provided for MarkdownParser setup and parent is a child widget. Defaulting to {0,0,200,200}. This may cause rendering issues if the parent widget is smaller than this size. Consider providing a rect option or using a non-child parent widget.")
    end

    local lytPath = isChild and (widgetName .. "." .. lytShort) or lytShort
    pcall(function()
        if isChild then
            widget.removeChild(widgetName, lytPath)
            logInfo("Removed existing child widget at %s.%s", widgetName, lytShort)
        else
            pane.removeWidget(lytPath)
            logInfo("Removed existing widget at %s", lytPath)
        end
    end)

    local lytConfig = {
        type = "layout",
        rect = rect,
        layoutType = "basic"
    }

    if isChild then
        widget.addChild(widgetName, lytConfig, lytShort)
    else
        pane.addWidget(lytConfig, lytShort)
    end

    local sz = widget.getSize(lytPath)
    local canvasRect = {
        0,
        0,
        sz[1] - 20, -- adjust for scrollbar width. Ill use this space for buttons
        sz[2] - 1 -- adjust for scroll rect, so it will no slip through when fully scrolled down
    }
    instance.rect = { 0, 0, sz[1], sz[2] } -- the full area including scroll buttons, used for mouse event capture and scroll calculations

    instance.parentWidgetPath = widgetName
    instance._isChild = isChild
    instance._screenOffset = options.screenOffset or { 0, 0 }
    instance._paneFeature = MarkdownParser.findPaneFeature()

    local scrollConfig = root.assetJson("/interface/StarboundTextboxInterface/markdown/md_parser_scroll_config.json")
    scrollConfig.rect = instance.rect
    scrollConfig.zLevel = 5

    widget.addChild(lytPath, scrollConfig, scrollShort)

    local textCanvasCfg = {
        type = "canvas",
        rect = canvasRect,
        captureMouseEvents = false,
        captureKeyboardEvents = false,
        mouseTransparent = true
    }

    local mouseCanvasCfg = {
        type = "canvas",
        rect = instance.rect,
        zlevel = 10,
        captureMouseEvents = true,
        captureKeyboardEvents = false,
    }

    widget.addChild(lytPath, textCanvasCfg, textShort)
    widget.addChild(lytPath, mouseCanvasCfg, mouseShort)

    local textPath = lytPath .. dotWidget(textShort)
    local mousePath = lytPath .. dotWidget(mouseShort)

    instance.lytPath = lytPath
    instance.scrollAreaPath = lytPath .. dotWidget(scrollShort)
    instance.textCanvasPath = textPath
    instance.mouseCanvasPath = mousePath
    instance.textCanvas = widget.bindCanvas(textPath)
    instance.mouseCanvas = widget.bindCanvas(mousePath)
    instance.measureWidget = WIDGET_SHORTS.measureLabel .. instance.uuid
    instance.measureCache = {}

    debugMessage("MarkdownParser setup complete. %s", sb.print(instance))
    addParser(instance)
    return instance
end

---@class MarkdownParserScrollConfig
---@field scrollEnabled boolean?  whether to enable scrolling. Default is false.
---@field scrollWidth number?  width in pixels of the scrollbar strip on the right. Default is 8.
---@field upButtonImage string?  path to image for the up scroll button. Default is "/interface/scrollarea/varrow-forward.png".
---@field upButtonHoverImage string?  path to image for the up scroll button when hovered. Default is "/interface/scrollarea/varrow-forwardhover.png".
---@field downButtonImage string?  path to image for the down scroll button. Default is "/interface/scrollarea/varrow-backward.png".
---@field downButtonHoverImage string?  path to image for the down scroll button when hovered. Default is "/interface/scrollarea/varrow-backwardhover.png".
---@field scrollThumbColor Color?  color of the scrollbar thumb. Default is {100, 100, 120, 220}.
---@field scrollThumbHoverColor Color?  color of the scrollbar thumb when hovered or dragged. Default is {150, 155, 175, 255}.
---@field scrollTrackColor Color?  color of the scrollbar track. Default is {15, 15, 25, 200}.
---@field scrollButtonSpeed number?  speed in pixels per second when scroll buttons are held. Default is 160.


---@param scrollConfig MarkdownParserScrollConfig?
function MarkdownParser:setupScroll(scrollConfig)
    scrollConfig = scrollConfig or {}
    self.scrollConfig = {
        scrollEnabled = true,
        scrollWidth = scrollConfig.scrollWidth or 8,
        upButtonImage = scrollConfig.upButtonImage or "/interface/scrollarea/varrow-forward.png",
        upButtonHoverImage = scrollConfig.upButtonHoverImage or "/interface/scrollarea/varrow-forwardhover.png",
        downButtonImage = scrollConfig.downButtonImage or "/interface/scrollarea/varrow-backward.png",
        downButtonHoverImage = scrollConfig.downButtonHoverImage or "/interface/scrollarea/varrow-backwardhover.png",
        scrollThumbColor = scrollConfig.scrollThumbColor or SCROLL_THUMB_COLOR,
        scrollThumbHoverColor = scrollConfig.scrollThumbHoverColor or SCROLL_THUMB_HOVER_COLOR,
        scrollTrackColor = scrollConfig.scrollTrackColor or SCROLL_TRACK_COLOR,
        scrollButtonSpeed = scrollConfig.scrollButtonSpeed or SCROLL_BUTTON_SPEED
    }

    local thumbShort = WIDGET_SHORTS.thumbCanvas

    local thumbCanvasCfg = {
        type = "canvas",
        rect = { self.rect[3] - self.scrollConfig.scrollWidth, 0, self.rect[3], self.rect[4] },
        captureMouseEvents = false,
        captureKeyboardEvents = false,
        mouseTransparent = true
    }

    widget.addChild(self.lytPath, thumbCanvasCfg, thumbShort)
    local thumbPath = self.lytPath .. dotWidget(thumbShort)
    self.thumbCanvasPath = thumbPath
    self.thumbCanvas = widget.bindCanvas(thumbPath)
    self:_drawScrollbar()
end


---@return WidgetPaneFeature?
function MarkdownParser.findPaneFeature()
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

---@protected
function MarkdownParser:_splitWidgetPath(path)
    local parts = {}
    for part in string.gmatch(path or "", "[^%.]+") do
        parts[#parts + 1] = part
    end
    return parts
end

---@protected
--- Pane-relative (unscaled) position of the layout widget, summing widget.getPosition
--- along every prefix of lytPath. Works uniformly for a top-level pane widget and a
--- deeply nested child, so no special-casing of the parenting model is needed.
---@return number[]
function MarkdownParser:_getLayoutPaneOffset()
    local parts = self:_splitWidgetPath(self.lytPath)
    local offset = { 0, 0 }
    local currentPath = nil
    for _, part in ipairs(parts) do
        currentPath = currentPath and (currentPath .. "." .. part) or part
        offset = vec2.add(offset, widget.getPosition(currentPath) or { 0, 0 })
    end
    return offset
end

---@protected
function MarkdownParser:_getPaneAnchorOffset()
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
        offset = { (screenSize[1] - paneSize[1]) * 0.5, 0 }
    elseif anchor == "centerTop" then
        offset = { (screenSize[1] - paneSize[1]) * 0.5, screenSize[2] - paneSize[2] }
    elseif anchor == "centerLeft" then
        offset = { 0, (screenSize[2] - paneSize[2]) * 0.5 }
    elseif anchor == "centerRight" then
        offset = { screenSize[1] - paneSize[1], (screenSize[2] - paneSize[2]) * 0.5 }
    elseif anchor == "center" then
        offset = { (screenSize[1] - paneSize[1]) * 0.5, (screenSize[2] - paneSize[2]) * 0.5 }
    end

    local featureOffset = feature.offset or { 0, 0 }
    return vec2.add(offset, vec2.mul(featureOffset, scale))
end

---@protected
--- Screen-space rect {x1,y1,x2,y2} of the layout (bottom-left origin, screen pixels).
function MarkdownParser:_getWidgetScreenRect()
    local panePos = pane.getPosition()
    local anchorOffset = self:_getPaneAnchorOffset()

    local uiPos = vec2.add(panePos, self:_getLayoutPaneOffset())
    uiPos = vec2.add(uiPos, self._screenOffset)

    local scale = interface.scale() or 1

    local screenPos = vec2.add(anchorOffset, vec2.mul(uiPos, scale))
    local size = vec2.mul({ self.rect[3], self.rect[4] }, scale)

    return {
        screenPos[1],
        screenPos[2],
        screenPos[1] + size[1],
        screenPos[2] + size[2]
    }
end

---@protected
--- Convert a global screen mouse position into layout-local (unscaled) pixels,
--- the same coordinate space canvas:mousePosition() used to report.
---@param mouseScreen number[]
---@param clampToRect boolean?
---@return number[] localMouse, number[] widgetRect
function MarkdownParser:_screenToLocalMouse(mouseScreen, clampToRect)
    local widgetRect = self:_getWidgetScreenRect()
    local scale = interface.scale()

    local localMouse = {
        (mouseScreen[1] - widgetRect[1]) / scale,
        (mouseScreen[2] - widgetRect[2]) / scale
    }

    if clampToRect then
        localMouse[1] = math.max(0, math.min(localMouse[1], self.rect[3]))
        localMouse[2] = math.max(0, math.min(localMouse[2], self.rect[4]))
    end

    if DEBUG then
        logMap("_screenToLocalMouse" .. tostring(self.uuid), "%s", sb.printJson({
            mouseScreen = mouseScreen,
            widgetRect = widgetRect,
            localMouse = localMouse,
            scale = scale
        }))
    end

    return localMouse, widgetRect
end

---@protected
--- Global mouse expressed in the thumb strip's local coordinates (origin at the
--- strip's bottom-left), matching what thumbCanvas:mousePosition() used to give.
---@return number[]
function MarkdownParser:_thumbLocalMouse()
    local lm = self:_screenToLocalMouse(input.mousePosition(), false)
    local originX = self.rect[3] - (self.scrollConfig.scrollWidth or 8)
    return { lm[1] - originX, lm[2] }
end

-- ─────────────────────────── Scrollbar drawing ───────────────────────────────

--- Redraw the scrollbar strip (thumb canvas): track bg, thumb rect, arrow images.
---@protected
function MarkdownParser:_drawScrollbar()
    local canvas = self.thumbCanvas
    if not canvas then
        return
    end
    canvas:clear()

    local sz = canvas:size()
    local cw, ch = sz[1], sz[2]
    local btnH = SCROLL_BTN_H

    -- track background
    canvas:drawRect({ 0, btnH, cw, ch - btnH }, self.scrollConfig.scrollTrackColor)

    -- mouse position for hover / interaction detection (global -> strip-local)
    local mp = self:_thumbLocalMouse()
    local mx, my = mp[1], mp[2]
    local onCvs = mx >= 0 and mx <= cw and my >= 0 and my <= ch

    -- ── arrow buttons ────────────────────────────────────────────────────────
    local upHover = onCvs and my >= ch - btnH
    local downHover = onCvs and my <= btnH

    canvas:drawImage(
            upHover and self.scrollConfig.upButtonHoverImage
                    or self.scrollConfig.upButtonImage,
            { cw * 0.5, ch - btnH * 0.5 }, 1, nil, true)

    canvas:drawImage(
            downHover and self.scrollConfig.downButtonHoverImage
                    or self.scrollConfig.downButtonImage,
            { cw * 0.5, btnH * 0.5 }, 1, nil, true)

    -- ── scrollbar thumb ───────────────────────────────────────────────────────
    local maxScroll = self:getMaxScroll()
    if maxScroll > 0 and self.textCanvas then
        local trackH = ch - 2 * btnH
        local viewH = self.textCanvas:size()[2]
        local thumbH = math.max(10, math.floor(trackH * viewH / math.max(1, self.totalH)))
        local thumbRange = trackH - thumbH
        local t = self.scroll / maxScroll
        -- thumbBot: bottom edge in canvas coords (Y=0 at bottom).
        -- t=0 → thumb at top of track; t=1 → thumb at bottom.
        local thumbBot = ch - btnH - thumbH - math.floor(thumbRange * t)
        local thumbTop = thumbBot + thumbH

        local thumbHover = onCvs and my >= thumbBot and my <= thumbTop
        local col = (thumbHover or self._thumbDragging) and self.scrollConfig.scrollThumbHoverColor
                or self.scrollConfig.scrollThumbColor
        canvas:drawRect({ 2, thumbBot, cw - 2, thumbTop }, col)
    end
end

-- ─────────────────────────── Scrollbar update (called every frame) ───────────

--- Called from update(); handles mouse-held scrolling and thumb dragging.
---@protected
function MarkdownParser:_updateScroll(dt, events)
    local canvas = self.thumbCanvas
    if not canvas then
        return
    end

    local sz = canvas:size()
    local cw, ch = sz[1], sz[2]
    local btnH = SCROLL_BTN_H

    local mp = self:_thumbLocalMouse()
    local mx, my = mp[1], mp[2]
    local onCvs = mx >= 0 and mx <= cw

    -- Track mouse button state from events.
    for _, ev in ipairs(events) do
        if ev.type == "MouseButtonDown" and ev.data and ev.data.mouseButton == "MouseLeft" then
            if widget.hasFocus(self.mouseCanvasPath) then
                self._mouseLeftHeld = true
            end
        elseif ev.type == "MouseButtonUp" and ev.data and ev.data.mouseButton == "MouseLeft" then
            self._mouseLeftHeld = false
        end
    end

    local maxScroll = self:getMaxScroll()
    local held = self._mouseLeftHeld

    if held then
        if self._thumbDragging then
            -- ── drag in progress ─────────────────────────────────────────────
            if maxScroll > 0 and self.textCanvas then
                local trackH = ch - 2 * btnH
                local viewH = self.textCanvas:size()[2]
                local thumbH = math.max(10, math.floor(trackH * viewH / math.max(1, self.totalH)))
                local thumbRange = trackH - thumbH
                if thumbRange > 0 then
                    -- Reconstruct t from current mouse position + stored drag offset.
                    local thumbBot = my - self._thumbDragOffset
                    -- t=0 when thumbBot = ch-btnH-thumbH; t=1 when thumbBot = btnH
                    local t = (ch - btnH - thumbH - thumbBot) / thumbRange
                    self:setScroll(math.max(0, math.min(maxScroll, t * maxScroll)))
                end
            end

        elseif not self._holdInitiated then
            -- ── first frame of this hold: decide what was clicked ────────────
            self._holdInitiated = true

            if onCvs and maxScroll > 0 and self.textCanvas then
                local trackH = ch - 2 * btnH
                local viewH = self.textCanvas:size()[2]
                local thumbH = math.max(10, math.floor(trackH * viewH / math.max(1, self.totalH)))
                local thumbRange = trackH - thumbH
                local t = self.scroll / maxScroll
                local thumbBot = ch - btnH - thumbH - math.floor(thumbRange * t)
                local thumbTop = thumbBot + thumbH

                if my >= thumbBot and my <= thumbTop then
                    self._thumbDragging = true
                    self._thumbDragOffset = my - thumbBot
                end
            end
        end

        -- ── continuous button scroll (works alongside drag check above) ──────
        if not self._thumbDragging and onCvs then
            if my >= ch - btnH then
                -- up button held → scroll toward top
                self:setScroll(math.max(0, self.scroll - self.scrollConfig.scrollButtonSpeed * dt))
            elseif my <= btnH then
                -- down button held → scroll toward bottom
                self:setScroll(math.min(maxScroll, self.scroll + self.scrollConfig.scrollButtonSpeed * dt))
            end
        end
    else
        self._thumbDragging = false
        self._holdInitiated = false
    end

    -- Always redraw scrollbar to keep hover highlights responsive.
    self:_drawScrollbar()
end

-- ─────────────────────────── Measurement ─────────────────────────────────────
---@protected
---@param text      string
---@param fontSize  number
---@param wrapWidth number  pixel wrap width passed to the label
---@return number?
function MarkdownParser:_textHeight(text, fontSize, wrapWidth)
    if not self.setupDone then
        return nil
    end
    text = text or ""
    local key = text .. "\0" .. fontSize .. "\0" .. wrapWidth
    local cached = self.measureCache[key]
    if cached then
        return cached
    end

    local name = self.measureWidget
    pcall(function()
        pane.removeWidget(name)
    end)
    local ok = pcall(function()
        pane.addWidget({
            type = "label",
            position = { -1000, -1000 },
            fontSize = fontSize,
            wrapWidth = wrapWidth,
            value = text,
        }, name)
    end)
    if not ok then
        return nil
    end

    local sz = widget.getSize(name)
    local h = sz and sz[2] or nil
    if h and h > 0 then
        self.measureCache[key] = h
        return h
    end
    return nil
end

---@protected
--- Measure height of text, falling back to line-height × estimateLines when unavailable
---@param text      string
---@param fontSize  number
---@param lineH     number   fallback single-line height in pixels
---@param wrapWidth number
---@return number
function MarkdownParser:_mH(text, fontSize, lineH, wrapWidth)
    local h = self:_textHeight(text, fontSize, wrapWidth)
    if h and h > 0 then
        return h
    end
    return lineH * estimateLines(text, math.max(1, math.floor(wrapWidth / 5)))
end

---@protected
---@param text     string
---@param fontSize number
---@return number
function MarkdownParser:_estimateTextWidth(text, fontSize)
    local cleanText = text:gsub("%^[^;]*;", "")
    local charCount = utf8.len(cleanText) or #cleanText
    return math.ceil(charCount * fontSize * 0.6) + 8 -- +8 for padding
end

-- ─────────────────────────── Height calculation ──────────────────────────────
---@protected
--- Calculate the total pixel height occupied by all tokens
--- cw is the FULL canvas pixel width (canvas:size()[1])
---@param tokens table
---@param cw     number  full canvas width
---@return number
function MarkdownParser:_calcContentHeight(tokens, cw)
    local wrapWidth = cw - PAD * 2
    local quoteWrap = math.max(1, wrapWidth - QUOTE_PAD_LEFT)

    local h = 0
    for _, tok in ipairs(tokens) do
        if tok.type == "blank" then
            h = h + LINE_HEIGHT.blank

        elseif tok.type == "hr" then
            h = h + LINE_HEIGHT.hr + 4

        elseif tok.type:sub(1, 1) == "h" then
            local ht = tok.type
            local lh = LINE_HEIGHT[ht] or 12
            local fs = FONT_SIZE[ht] or 8
            local rendered = applyInline(tok.text)
            h = h + self:_mH(rendered, fs, lh, wrapWidth) + 2

        elseif tok.type == "p" then
            local rendered = applyInline(tok.text)
            h = h + self:_mH(rendered, FONT_SIZE.p, LINE_HEIGHT.p, wrapWidth) + PARAGRAPH_GAP

        elseif tok.type == "li" then
            local indent = (tok.indent or 0) * INDENT_PX
            local liWrap = math.max(1, wrapWidth - indent)
            local bullet = tok.text:match("^%d") and "" or "• "
            local rendered = bullet .. applyInline(tok.text)
            h = h + self:_mH(rendered, FONT_SIZE.li, LINE_HEIGHT.li, liWrap)

        elseif tok.type == "code_block" then
            h = h + LINE_HEIGHT.code_block * #tok.lines + 2

        elseif tok.type == "blockquote" then
            local innerH = 0
            for _, ql in ipairs(tok.lines) do
                local rendered = applyInline(ql)
                innerH = innerH + self:_mH(rendered, FONT_SIZE.p, LINE_HEIGHT.p, quoteWrap)
            end
            h = h + innerH + 4

        elseif tok.type == "table" then
            local numRows = #tok.rows + 1
            h = h + numRows * LINE_HEIGHT.table_row + 4
        end
    end
    return h
end

---@protected
function MarkdownParser:_recalc()
    if #self.blocks == 0 then
        self.totalH = 0;
        return
    end
    local y = PAD
    for i, id in ipairs(self.blocks) do
        self.renders[id].offsetY = y
        y = y + self.renders[id].contentH
        if i < #self.blocks then
            y = y + BLOCK_GAP
        end
    end
    self.totalH = y + PAD
end

-- ─────────────────────────── Drawing ─────────────────────────────────────────

---@protected
---@param canvas CanvasWidget
---@param tokens table
---@param baseY  number  vertical offset of the top of the block relative to the top of the canvas. This is used to calculate the Y coordinate for each line and determine if it is
---@param cw     number  full canvas width (canvas:size()[1])
---@param ch     number  full canvas height (canvas:size()[2])
---@param scroll number  current scroll offset in pixels
function MarkdownParser:_drawBlock(canvas, tokens, baseY, cw, ch, scroll)
    local wrapWidth = cw - PAD * 2
    local quoteWrap = math.max(1, wrapWidth - QUOTE_PAD_LEFT)

    local function toY(cy)
        return ch - (baseY + cy) + scroll
    end
    local function visible(top, h)
        return top > 0 and (top - h) < ch
    end

    local contentY = 0

    for _, tok in ipairs(tokens) do

        if tok.type == "blank" then
            contentY = contentY + LINE_HEIGHT.blank

        elseif tok.type == "hr" then
            contentY = contentY + 2
            local ty = toY(contentY)
            if visible(ty + 1, 2) then
                canvas:drawLine({ PAD, ty }, { cw - PAD, ty }, COLOR.hr, 1)
            end
            contentY = contentY + LINE_HEIGHT.hr + 2

        elseif tok.type:sub(1, 1) == "h" then
            local ht = tok.type
            local lh = LINE_HEIGHT[ht] or 12
            local fs = FONT_SIZE[ht] or 8
            local color = COLOR[ht] or COLOR.p
            local rendered = applyInline(tok.text)
            local totalH = self:_mH(rendered, fs, lh, wrapWidth) + 2
            local ty = toY(contentY)

            if visible(ty, totalH) then
                canvas:drawText(rendered, {
                    position = { PAD, ty },
                    horizontalAnchor = "left",
                    verticalAnchor = "top",
                    wrapWidth = wrapWidth,
                }, fs, color)
            end
            contentY = contentY + totalH

        elseif tok.type == "p" then
            local rendered = applyInline(tok.text)
            local textH = self:_mH(rendered, FONT_SIZE.p, LINE_HEIGHT.p, wrapWidth)
            local totalH = textH + PARAGRAPH_GAP
            local ty = toY(contentY)

            if visible(ty, totalH) then
                canvas:drawText(rendered, {
                    position = { PAD, ty },
                    horizontalAnchor = "left",
                    verticalAnchor = "top",
                    wrapWidth = wrapWidth,
                }, FONT_SIZE.p, COLOR.p)
            end
            contentY = contentY + totalH

        elseif tok.type == "li" then
            local indent = (tok.indent or 0) * INDENT_PX
            local liWrap = math.max(1, wrapWidth - indent)
            local bullet = tok.text:match("^%d") and "" or "• "
            local processed = bullet .. applyInline(tok.text)
            local totalH = self:_mH(processed, FONT_SIZE.li, LINE_HEIGHT.li, liWrap)
            local ty = toY(contentY)

            if visible(ty, totalH) then
                canvas:drawText(processed, {
                    position = { PAD + indent, ty },
                    horizontalAnchor = "left",
                    verticalAnchor = "top",
                    wrapWidth = liWrap,
                }, FONT_SIZE.li, COLOR.li)
            end
            contentY = contentY + totalH

        elseif tok.type == "code_block" then
            local blockH = LINE_HEIGHT.code_block * #tok.lines + 2
            local blockTop = toY(contentY)
            local blockBot = blockTop - blockH

            if visible(blockTop, blockH) then
                canvas:drawRect({ 0, blockBot, cw, blockTop }, COLOR.code_bg)
            end

            contentY = contentY + 1
            for _, cl in ipairs(tok.lines) do
                local ty = toY(contentY)
                if visible(ty, LINE_HEIGHT.code_block) then
                    canvas:drawText(cl:gsub("%^", "\\^"), {
                        position = { PAD + 2, ty },
                        horizontalAnchor = "left",
                        verticalAnchor = "top",
                        wrapWidth = wrapWidth - 4,
                    }, FONT_SIZE.code_block, COLOR.code_text)
                end
                contentY = contentY + LINE_HEIGHT.code_block
            end
            contentY = contentY + 1

        elseif tok.type == "blockquote" then
            local lineHeights = {}
            local innerH = 0

            for _, ql in ipairs(tok.lines) do
                local rendered = applyInline(ql)
                local lineH = self:_mH(rendered, FONT_SIZE.p, LINE_HEIGHT.p, quoteWrap)
                lineHeights[#lineHeights + 1] = lineH
                innerH = innerH + lineH
            end

            local totalH = innerH + 4
            local blockTop = toY(contentY)
            local blockBot = blockTop - totalH

            if visible(blockTop, totalH) then
                canvas:drawRect({ 0, blockBot, cw, blockTop }, COLOR.quote_bg)
                canvas:drawRect({ 0, blockBot, QUOTE_BAR_W, blockTop }, COLOR.quote_bar)
            end

            contentY = contentY + 2
            for i, ql in ipairs(tok.lines) do
                local rendered = applyInline(ql)
                local lineH = lineHeights[i]
                local ty = toY(contentY)

                if visible(ty, lineH) then
                    canvas:drawText(rendered, {
                        position = { PAD + QUOTE_PAD_LEFT, ty },
                        horizontalAnchor = "left",
                        verticalAnchor = "top",
                        wrapWidth = quoteWrap,
                    }, FONT_SIZE.p, COLOR.quote_text)
                end
                contentY = contentY + lineH
            end
            contentY = contentY + 2

        elseif tok.type == "table" then
            local numCols = #tok.header
            local numRows = #tok.rows + 1 -- +1 for header
            local colWidths = {}
            local minColWidth = 40
            local maxColWidth = 200

            for colIdx = 1, numCols do
                local maxWidth = minColWidth

                local headerText = applyInline(tok.header[colIdx] or "")
                local headerWidth = self:_estimateTextWidth(headerText, FONT_SIZE.table_cell)
                maxWidth = math.max(maxWidth, headerWidth)

                for _, row in ipairs(tok.rows) do
                    local cellText = applyInline(row[colIdx] or "")
                    local cellWidth = self:_estimateTextWidth(cellText, FONT_SIZE.table_cell)
                    maxWidth = math.max(maxWidth, cellWidth)
                end

                colWidths[colIdx] = math.min(maxWidth, maxColWidth)
            end

            local tableWidth = 4 -- padding
            for _, w in ipairs(colWidths) do
                tableWidth = tableWidth + w
            end

            if tableWidth > wrapWidth then
                local scale = wrapWidth / tableWidth
                for i = 1, #colWidths do
                    colWidths[i] = math.floor(colWidths[i] * scale)
                end
                tableWidth = wrapWidth
            end

            local tableHeight = numRows * LINE_HEIGHT.table_row + 4

            local blockTop = toY(contentY)
            local blockBot = blockTop - tableHeight

            if visible(blockTop, tableHeight) then
                canvas:drawRect({ PAD, blockBot, PAD + tableWidth, blockTop }, COLOR.table_border)

                local cellY = contentY + 2

                local headerTop = toY(cellY)
                local headerBot = headerTop - LINE_HEIGHT.table_row
                canvas:drawRect({ PAD + 1, headerBot, PAD + tableWidth - 1, headerTop }, COLOR.table_header_bg)

                local currentX = 0
                for colIdx, headerText in ipairs(tok.header) do
                    local colWidth = colWidths[colIdx]
                    local cellX = PAD + currentX + 2
                    local alignment = tok.alignments[colIdx] or "left"
                    local renderedText = applyInline(headerText)

                    local anchor = "left"
                    local xPos = cellX
                    if alignment == "center" then
                        anchor = "mid"
                        xPos = cellX + colWidth / 2 - 2
                    elseif alignment == "right" then
                        anchor = "right"
                        xPos = cellX + colWidth - 4
                    end

                    canvas:drawText(renderedText, {
                        position = { xPos, toY(cellY) },
                        horizontalAnchor = anchor,
                        verticalAnchor = "top",
                        wrapWidth = colWidth - 4,
                    }, FONT_SIZE.table_cell, COLOR.table_header_text)

                    currentX = currentX + colWidth
                end

                cellY = cellY + LINE_HEIGHT.table_row

                local sepY = toY(cellY)
                canvas:drawLine({ PAD, sepY }, { PAD + tableWidth, sepY }, COLOR.table_border, 1)

                for rowIdx, row in ipairs(tok.rows) do
                    local rowTop = toY(cellY)
                    local rowBot = rowTop - LINE_HEIGHT.table_row

                    if rowIdx % 2 == 0 then
                        canvas:drawRect({ PAD + 1, rowBot, PAD + tableWidth - 1, rowTop }, COLOR.table_row_bg)
                    end

                    currentX = 0
                    for colIdx = 1, numCols do
                        local colWidth = colWidths[colIdx]
                        local cellText = row[colIdx] or ""
                        local cellX = PAD + currentX + 2
                        local alignment = tok.alignments[colIdx] or "left"
                        local renderedText = applyInline(cellText)

                        local anchor = "left"
                        local xPos = cellX
                        if alignment == "center" then
                            anchor = "mid"
                            xPos = cellX + colWidth / 2 - 2
                        elseif alignment == "right" then
                            anchor = "right"
                            xPos = cellX + colWidth - 4
                        end

                        canvas:drawText(renderedText, {
                            position = { xPos, toY(cellY) },
                            horizontalAnchor = anchor,
                            verticalAnchor = "top",
                            wrapWidth = colWidth - 4,
                        }, FONT_SIZE.table_cell, COLOR.table_text)

                        currentX = currentX + colWidth
                    end

                    cellY = cellY + LINE_HEIGHT.table_row

                    if rowIdx < #tok.rows then
                        local rowSepY = toY(cellY)
                        canvas:drawLine({ PAD, rowSepY }, { PAD + tableWidth, rowSepY }, COLOR.table_border, 0.5)
                    end
                end
            end

            contentY = contentY + tableHeight
        end
    end
    if self.blockSeparator and self.blockSeparator ~= "" then
        canvas:drawText(self.blockSeparator, {
            position = { PAD, toY(contentY) },
            horizontalAnchor = "left",
            verticalAnchor = "top",
            wrapWidth = wrapWidth,
        }, FONT_SIZE.p, COLOR.hr)
    end
end

---@protected
function MarkdownParser:_drawAll()
    local canvas = self.textCanvas
    if not canvas then
        return
    end
    canvas:clear()
    if self.scrollConfig.scrollEnabled then
        self:_drawScrollbar()
    end
    if #self.blocks == 0 then
        return
    end

    local sz = canvas:size()
    local cw, ch = sz[1], sz[2]

    for _, id in ipairs(self.blocks) do
        local r = self.renders[id]
        self:_drawBlock(canvas, r.tokens, r.offsetY, cw, ch, self.scroll)
    end
end

-- ─────────────────────────── Public API ──────────────────────────────────────

---@param text    string   markdown source text
---@param options table?   reserved for future use
---@return number  blockID  (positive integer; -1 on error)
function MarkdownParser:render(text, options)
    options = options or {}
    if type(text) == "table" then
        text = table.concat(text, "\n")
    end
    if type(text) ~= "string" then
        sb.logError("[md.lua] text must be a string, got %s", type(text))
        return -1
    end
    if not self.textCanvas then
        sb.logError("[md.lua] render() called on an instance that has no canvas — did you call setup()?")
        return -1
    end

    local sz = self.textCanvas:size()
    local cw = sz[1]
    local tokens = lex(text)

    local id = self.nextId
    self.nextId = self.nextId + 1

    self.renders[id] = {
        tokens = tokens,
        contentH = self:_calcContentHeight(tokens, cw),
        offsetY = 0, -- set by _recalc below
    }

    self.blocks[#self.blocks + 1] = id
    self:_recalc()
    self:_drawAll()
    return id
end

--- Set separator between blocks (default: 6 pixels)
---@param pixels number
function MarkdownParser:setBlockGap(pixels)
    BLOCK_GAP = math.max(0, pixels)
end

function MarkdownParser.setDebug(enabled)
    DEBUG = enabled
end

--- Set the shared scroll offset (pixels from top) and redraw
---@param scrollY number
function MarkdownParser:setScroll(scrollY)
    self.scroll = math.max(0, scrollY)
    self:_drawAll()
end

--- Use together with setScroll() to jump to a specific block:
---   myMd:setScroll(myMd:getScrollByBlock(id))
---@param id number
---@return number  offsetY of the block (pixels from the top of the content)
function MarkdownParser:getScrollByBlock(id)
    local r = self.renders[id]
    if not r then
        return 0
    end
    return r.offsetY
end

function MarkdownParser:setBlockSeparatorLine(line)
    self.blockSeparator = line or self.blockSeparator
end

---@return boolean
function MarkdownParser:mouseOverWindow()
    local lm = self:_screenToLocalMouse(input.mousePosition(), false)
    return lm[1] >= self.rect[1] and lm[1] <= self.rect[3]
            and lm[2] >= self.rect[2] and lm[2] <= self.rect[4]
end

--- Get the current scroll offset.
---@return number
function MarkdownParser:getScroll()
    return self.scroll
end

--- Get the combined pixel height of all blocks (including gaps and padding)
---@return number
function MarkdownParser:getTotalHeight()
    return self.totalH
end

--- Get the maximum scroll offset (totalHeight - canvasHeight, ≥ 0)
---@return number
function MarkdownParser:getMaxScroll()
    if not self.textCanvas then
        return 0
    end
    return math.max(0, self.totalH - self.textCanvas:size()[2])
end

--- Remove a specific block and redraw
---@param id number
function MarkdownParser:remove(id)
    if not self.renders[id] then
        return
    end
    for i, bid in ipairs(self.blocks) do
        if bid == id then
            table.remove(self.blocks, i);
            break
        end
    end
    self.renders[id] = nil
    self:_recalc()
    self:_drawAll()
end

--- Update a block's text in-place and redraw
---@param id      number
---@param text    string
---@param options table?
function MarkdownParser:update(id, text, options)
    local r = self.renders[id]
    if not r then
        return
    end
    options = options or {}
    if type(text) == "table" then
        text = table.concat(text, "\n")
    end
    if not self.textCanvas then
        return
    end
    local cw = self.textCanvas:size()[1]
    r.tokens = lex(text)
    r.contentH = self:_calcContentHeight(r.tokens, cw)
    self:_recalc()
    self:_drawAll()
end

--- Remove all blocks and clear the canvas
function MarkdownParser:clear()
    self.renders = {}
    self.blocks = {}
    self.scroll = 0
    self.totalH = 0
    if self.textCanvas then
        self.textCanvas:clear()
    end
    if self.scrollConfig.scrollEnabled and self.thumbCanvas then
        self.thumbCanvas:clear()
    end
end

function MarkdownParser:destroy()
    self:clear()
    local path = self.lytPath
    pane.removeWidget(path)
    removeParser(self.uuid)
    self = nil
end

--- Force a full redraw of all blocks
function MarkdownParser:redraw()
    self:_drawAll()
end

---@param query string
---@return table[]
function MarkdownParser:search(query)
    if type(query) ~= "string" or query == "" then
        return {}
    end
    local lq = utf8.lower(query)
    local results = {}

    for _, id in ipairs(self.blocks) do
        local r = self.renders[id]
        for _, tok in ipairs(r.tokens) do
            if tok.type == "code_block" then
                for _, rawLine in ipairs(tok.lines) do
                    if utf8.lower(rawLine):find(lq, 1, true) then
                        results[#results + 1] = { id = id, line = rawLine }
                    end
                end

            elseif tok.type == "blockquote" then
                for _, rawLine in ipairs(tok.lines) do
                    local plain = stripDirectives(applyInline(rawLine))
                    if utf8.lower(plain):find(lq, 1, true) then
                        results[#results + 1] = { id = id, line = rawLine }
                    end
                end

            elseif tok.text then
                local plain = stripDirectives(applyInline(tok.text))
                if utf8.lower(plain):find(lq, 1, true) then
                    results[#results + 1] = { id = id, line = tok.text }
                end
            end
        end
    end

    return results
end


-- ────────────────────────── Lifecycle ─────────────────────────────────────────


function MarkdownParser.init()
    if not pane then
        assert(false, "MarkdownParser: init - pane API is not available. Make sure to include this script in an interface script and that it is loaded before the main script.")
    end
end

function MarkdownParser.update(dt)
    local events = input.events() or {}
    for _, parser in pairs(activeParsers) do
        if parser.scrollConfig.scrollEnabled and parser.thumbCanvas then
            parser:_updateScroll(dt, events)
        end
    end
end

function MarkdownParser.uninit()
    for uuid, parser in pairs(activeParsers) do
        local p = removeParser(uuid)
        if p then
            debugMessage("Uninitializing parser %s", sb.print(p.uuid))
            p:clear()
            local path = p.lytPath
            p = nil
            pane.removeWidget(path)
        else
            debugMessage("Parser %s was already removed for somehow", sb.print(parser))
        end
    end
end

