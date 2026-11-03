require("/scripts/vec2.lua")

-- Так как оригинальный тайтл не может быть сдвинут вообще никак, как и сама картинка,
-- приходится создавать такие мелкие скрипты для удобства.

---@class BackgroundGuiConfig
---@field type       "background"
---@field fileHeader string
---@field fileBody   string
---@field fileFooter string

---@class BetterTitleIconConfig
---@field file     string
---@field position Vec2I?

---@class BetterTitleConfig
---@field title             string?
---@field subtitle          string?
---@field position          Vec2I?
---@field titlePosition     Vec2I?
---@field subtitlePosition  Vec2I?
---@field icon              BetterTitleIconConfig?
---@field padding           BetterTitlePadding?
---@field hideOriginalTitle boolean?

---@class BetterTitlePadding
---@field left       integer
---@field right      integer
---@field top        integer
---@field bottom     integer
---@field iconGap    integer
---@field lineGap    integer
---@field lineHeight integer

---@class BetterTitleTextPart
---@field value    string
---@field position Vec2I

---@class BetterTitleIcon
---@field file     string?
---@field position Vec2I
---@field _size    Vec2U

---@class BetterTitle
BetterTitle = {
    ---@type BetterTitleTextPart
    title = {
        value = "",
        position = { 0, 0 }
    },
    ---@type BetterTitleTextPart
    subtitle = {
        value = "",
        position = { 0, 0 }
    },
    ---@type BetterTitleIcon
    icon = {
        file = nil,
        position = { 0, 0 },
        _size = { 0, 0 }
    },
    ---@type Vec2I
    position = { 0, 0 },
    ---@type BetterTitlePadding
    padding = {
        left = 0,
        right = 0,
        top = 0,
        bottom = 0,
        iconGap = 0,
        lineGap = 2,
        lineHeight = 10
    },
    hideOriginalTitle = true
}

local LYT_TITLE_WIDGET_NAME = "f1cdace34ebd" -- i hope no one will do the same widget name
local TITLE_NAME_WIDGET = "name"
local TITLE_NAME_WIDGET_PATH = LYT_TITLE_WIDGET_NAME .. "." .. TITLE_NAME_WIDGET
local TITLE_SUBTITLE_WIDGET = "subtitle"
local TITLE_SUBTITLE_WIDGET_PATH = LYT_TITLE_WIDGET_NAME .. "." .. TITLE_SUBTITLE_WIDGET
local TITLE_ICON_WIDGET = "icon"
local TITLE_ICON_WIDGET_PATH = LYT_TITLE_WIDGET_NAME .. "." .. TITLE_ICON_WIDGET

local PADDING_KEYS = { "left", "right", "top", "bottom", "iconGap", "lineGap", "lineHeight" }

local CONFIG_KEY = "betterTitle"
local VANILLA_TITLE_KEY = "title"
local FALLBACK_HEADER_HEIGHT = 24
local widgetsCreated = false
---@type RectI?
local cachedHeaderRect = nil

local function _copy(value)
    if type(value) ~= "table" then
        return value
    end
    local result = {}
    for k, v in pairs(value) do
        result[k] = _copy(v)
    end
    return result
end

---@param value    any
---@param fallback Vec2I
---@return Vec2I
local function _toVec2(value, fallback)
    if type(value) == "table" and type(value[1]) == "number" and type(value[2]) == "number" then
        return { math.floor(value[1]), math.floor(value[2]) }
    end
    return { fallback[1], fallback[2] }
end

---@param value    any
---@param fallback string
---@return string
local function _toText(value, fallback)
    if type(value) == "string" then
        return value
    end
    if value ~= nil then
        return tostring(value)
    end
    return fallback
end

---@param file string?
---@return Vec2U?
local function _imageSize(file)
    if type(file) ~= "string" or file == "" then
        return nil
    end
    local ok, size = pcall(root.imageSize, file)
    if not ok or type(size) ~= "table" or type(size[1]) ~= "number" then
        sb.logWarn("[BetterTitle] Can't get image size '%s'", file)
        return nil
    end
    return { size[1], size[2] }
end

---@param widgetName string
---@return boolean
local function _widgetExists(widgetName)
    local ok, data = pcall(widget.getData, widgetName)
    return ok and data ~= nil
end

---@param path      string
---@param tableType string
---@return table? pair
local function _locateTable(path, tableType)
    local cfg = config.getParameter(path)
    if type(cfg) ~= "table" then
        return nil
    end
    for k, v in pairs(cfg) do
        if type(v) == "table" and v.type == tableType then
            return { k, v }
        end
    end
    return nil
end

---@private
---@return RectI?
local function _getHeaderRect()
    if cachedHeaderRect ~= nil then
        return cachedHeaderRect
    end

    local interfaceSize = pane.getSize()
    if type(interfaceSize) ~= "table" then
        sb.logWarn(
            "[BetterTitle] pane.getSize() returned not a vector, can't calculate header"
        )
        return nil
    end

    local headerTable = _locateTable("gui", "background")
    local headerFile = headerTable and headerTable[2].fileHeader
    local headerSize = _imageSize(type(headerFile) == "string" and headerFile or nil)

    if headerSize == nil then
        sb.logWarn(
            "[BetterTitle] Can't find fileHeader in gui, using fallback header height (%s)",
            FALLBACK_HEADER_HEIGHT
        )
        headerSize = { interfaceSize[1], FALLBACK_HEADER_HEIGHT }
    end

    -- [100, 60] - [20, 20] = [80, 40] -- x,y of begining offset
    local begginingOffset = vec2.sub(interfaceSize, headerSize)
    local endOffset = interfaceSize
    cachedHeaderRect = { begginingOffset[1], begginingOffset[2], endOffset[1], endOffset[2] }
    return cachedHeaderRect
end

---@private
---@return RectI?
local function _layoutRect()
    local base = _getHeaderRect()
    if base == nil then
        return nil
    end

    local p = BetterTitle.position
    local pad = BetterTitle.padding

    local x1 = base[1] + pad.left + p[1]
    local y1 = base[2] + pad.bottom + p[2]
    local x2 = base[3] - pad.right + p[1]
    local y2 = base[4] - pad.top + p[2]

    if x2 < x1 then
        x2 = x1
    end
    if y2 < y1 then
        y2 = y1
    end

    return { x1, y1, x2, y2 }
end

---@private
---@return Vec2I iconPosition, Vec2I titlePosition, Vec2I subtitlePosition
local function _childPositions()
    local pad = BetterTitle.padding
    local icon = BetterTitle.icon
    local iconWidth = icon.file and icon._size[1] or 0
    local textX = iconWidth + (iconWidth > 0 and pad.iconGap or 0)
    local titleY = pad.lineHeight + pad.lineGap

    return { icon.position[1], icon.position[2] },
        { textX + BetterTitle.title.position[1], titleY + BetterTitle.title.position[2] },
        { textX + BetterTitle.subtitle.position[1], BetterTitle.subtitle.position[2] }
end

---@private
---@param iconPosition Vec2I
local function _syncIcon(iconPosition)
    local exists = _widgetExists(TITLE_ICON_WIDGET_PATH)

    if BetterTitle.icon.file == nil then
        if exists then
            widget.removeChild(LYT_TITLE_WIDGET_NAME, TITLE_ICON_WIDGET)
        end
        return
    end

    if exists then
        widget.setImage(TITLE_ICON_WIDGET_PATH, BetterTitle.icon.file)
        widget.setPosition(TITLE_ICON_WIDGET_PATH, iconPosition)
    else
        widget.addChild(LYT_TITLE_WIDGET_NAME, {
            type = "image",
            file = BetterTitle.icon.file,
            position = iconPosition,
            data = { exist = true }
        }, TITLE_ICON_WIDGET
        )
    end
end

---@private
local function _hideOriginalTitle()
    if not BetterTitle.hideOriginalTitle then
        return
    end
    if config.getParameter(VANILLA_TITLE_KEY) == nil then
        return
    end
    pcall(pane.setTitle, "", "")
    pcall(pane.setTitleIcon, "")
end

---@return BetterTitle
function BetterTitle.refresh()
    if not widgetsCreated or not _widgetExists(LYT_TITLE_WIDGET_NAME) then
        return BetterTitle
    end

    local rect = _layoutRect()
    if rect ~= nil then
        widget.setPosition(LYT_TITLE_WIDGET_NAME, { rect[1], rect[2] })
        widget.setSize(LYT_TITLE_WIDGET_NAME, { rect[3] - rect[1], rect[4] - rect[2] })
    end

    local iconPosition, titlePosition, subtitlePosition = _childPositions()

    _syncIcon(iconPosition)

    widget.setText(TITLE_NAME_WIDGET_PATH, BetterTitle.title.value)
    widget.setPosition(TITLE_NAME_WIDGET_PATH, titlePosition)

    widget.setText(TITLE_SUBTITLE_WIDGET_PATH, BetterTitle.subtitle.value)
    widget.setPosition(TITLE_SUBTITLE_WIDGET_PATH, subtitlePosition)

    return BetterTitle
end

---@return BetterTitle
function BetterTitle.createWidgets()
    assert(pane ~= nil, "Pane is required. Make sure that the script in the interface context.")

    if _widgetExists(LYT_TITLE_WIDGET_NAME) then
        sb.logInfo("[BetterTitle] Widget already created, just refreshing it")
        widgetsCreated = true
        return BetterTitle.refresh()
    end

    local rect = _layoutRect()
    if rect == nil then
        sb.logWarn(
            "[BetterTitle] Can't calculate header rectangle, not creating widgets"
        )
        return BetterTitle
    end

    _hideOriginalTitle()

    pane.addWidget({
        type = "layout",
        layoutType = "basic",
        rect = rect,
        scissoring = true,
        data = {
            exist = true
        }
    }, LYT_TITLE_WIDGET_NAME)

    local iconPosition, titlePosition, subtitlePosition = _childPositions()

    if BetterTitle.icon.file then
        widget.addChild(LYT_TITLE_WIDGET_NAME, {
            type = "image",
            file = BetterTitle.icon.file,
            position = iconPosition,
            data = { exist = true }
        }, TITLE_ICON_WIDGET
        )
    end

    widget.addChild(LYT_TITLE_WIDGET_NAME, {
        type = "label",
        value = BetterTitle.title.value,
        position = titlePosition
    }, TITLE_NAME_WIDGET
    )

    widget.addChild(LYT_TITLE_WIDGET_NAME, {
        type = "label",
        value = BetterTitle.subtitle.value,
        position = subtitlePosition
    }, TITLE_SUBTITLE_WIDGET
    )

    widgetsCreated = true
    return BetterTitle
end

---@return BetterTitle
function BetterTitle.destroy()
    if _widgetExists(LYT_TITLE_WIDGET_NAME) then
        pane.removeWidget(LYT_TITLE_WIDGET_NAME)
    end
    widgetsCreated = false
    return BetterTitle
end

---@return boolean
function BetterTitle.isCreated()
    return widgetsCreated
end

---@return string
function BetterTitle.getTitle()
    return BetterTitle.title.value
end

---@param value string?
---@return BetterTitle
function BetterTitle.setTitle(value)
    BetterTitle.title.value = _toText(value, "")
    return BetterTitle.refresh()
end

---@return string
function BetterTitle.getSubtitle()
    return BetterTitle.subtitle.value
end

---@param value string?
---@return BetterTitle
function BetterTitle.setSubtitle(value)
    BetterTitle.subtitle.value = _toText(value, "")
    return BetterTitle.refresh()
end

---@return Vec2I
function BetterTitle.getTitlePosition()
    return _copy(BetterTitle.title.position)
end

---@param position Vec2I?
---@return BetterTitle
function BetterTitle.setTitlePosition(position)
    BetterTitle.title.position = _toVec2(position, BetterTitle.title.position)
    return BetterTitle.refresh()
end

---@return Vec2I
function BetterTitle.getSubtitlePosition()
    return _copy(BetterTitle.subtitle.position)
end

---@param position Vec2I?
---@return BetterTitle
function BetterTitle.setSubtitlePosition(position)
    BetterTitle.subtitle.position = _toVec2(position, BetterTitle.subtitle.position)
    return BetterTitle.refresh()
end

---@return string?
function BetterTitle.getIcon()
    return BetterTitle.icon.file
end

---@param file     string?
---@param position Vec2I?
---@return BetterTitle
function BetterTitle.setIcon(file, position)
    if file ~= nil and type(file) ~= "string" then
        sb.logWarn(
            "[BetterTitle] Path to icon must be a string, got: %s",
            type(file)
        )
        file = nil
    end

    local size = _imageSize(file)
    if file ~= nil and size == nil then
        file = nil
    end

    BetterTitle.icon.file = file
    BetterTitle.icon._size = size or { 0, 0 }
    BetterTitle.icon.position = _toVec2(position, BetterTitle.icon.position)

    return BetterTitle.refresh()
end

---@return Vec2I
function BetterTitle.getIconPosition()
    return _copy(BetterTitle.icon.position)
end

---@param position Vec2I?
---@return BetterTitle
function BetterTitle.setIconPosition(position)
    BetterTitle.icon.position = _toVec2(position, BetterTitle.icon.position)
    return BetterTitle.refresh()
end

---@return Vec2U
function BetterTitle.getIconSize()
    return _copy(BetterTitle.icon._size)
end

---@return BetterTitlePadding
function BetterTitle.getPadding()
    return _copy(BetterTitle.padding)
end

---@param padding BetterTitlePadding | table
---@return BetterTitle
function BetterTitle.setPadding(padding)
    if type(padding) ~= "table" then
        sb.logWarn("[BetterTitle] setPadding expects a table, got: %s", type(padding))
        return BetterTitle
    end
    for _, key in ipairs(PADDING_KEYS) do
        local value = padding[key]
        if type(value) == "number" then
            BetterTitle.padding[key] = math.floor(value)
        elseif value ~= nil then
            sb.logWarn(
                "[BetterTitle] padding.%s must be a number, got: %s", key, type(value)
            )
        end
    end
    return BetterTitle.refresh()
end

---@return Vec2I
function BetterTitle.getPosition()
    return _copy(BetterTitle.position)
end

---@param position Vec2I?
---@return BetterTitle
function BetterTitle.setPosition(position)
    BetterTitle.position = _toVec2(position, BetterTitle.position)
    return BetterTitle.refresh()
end

---@param visible boolean
---@return BetterTitle
function BetterTitle.setVisible(visible)
    if widgetsCreated and _widgetExists(LYT_TITLE_WIDGET_NAME) then
        widget.setVisible(LYT_TITLE_WIDGET_NAME, visible and true or false)
    end
    return BetterTitle
end

---@param options table
---@return BetterTitle
function BetterTitle.configure(options)
    if type(options) ~= "table" then
        sb.logWarn("[BetterTitle] configure expects a table, got: %s", type(options))
        return BetterTitle
    end

    if type(options.title) == "table" then
        BetterTitle.title.value = _toText(options.title.value, BetterTitle.title.value)
        BetterTitle.title.position = _toVec2(options.title.position, BetterTitle.title.position)
    elseif options.title ~= nil then
        BetterTitle.title.value = _toText(options.title, BetterTitle.title.value)
    end

    if type(options.subtitle) == "table" then
        BetterTitle.subtitle.value = _toText(options.subtitle.value, BetterTitle.subtitle.value)
        BetterTitle.subtitle.position = _toVec2(options.subtitle.position, BetterTitle.subtitle.position)
    elseif options.subtitle ~= nil then
        BetterTitle.subtitle.value = _toText(options.subtitle, BetterTitle.subtitle.value)
    end

    if type(options.icon) == "table" then
        BetterTitle.setIcon(options.icon.file, options.icon.position)
    end

    if options.position ~= nil then
        BetterTitle.position = _toVec2(options.position, BetterTitle.position)
    end

    if type(options.padding) == "table" then
        BetterTitle.setPadding(options.padding)
    end

    if type(options.hideOriginalTitle) == "boolean" then
        BetterTitle.hideOriginalTitle = options.hideOriginalTitle
    end

    return BetterTitle.refresh()
end

---@private
---@return BetterTitle
function BetterTitle.loadFromConfig()
    ---@type BetterTitleConfig?
    local cfg = config.getParameter(CONFIG_KEY)
    if type(cfg) ~= "table" then
        sb.logInfo(
            "[BetterTitle] No '%s' section in pane config, sticking with default values",
            CONFIG_KEY
        )
        return BetterTitle
    end

    BetterTitle.title.value = _toText(cfg.title, BetterTitle.title.value)
    BetterTitle.title.position = _toVec2(cfg.titlePosition, BetterTitle.title.position)

    BetterTitle.subtitle.value = _toText(cfg.subtitle, BetterTitle.subtitle.value)
    BetterTitle.subtitle.position = _toVec2(cfg.subtitlePosition, BetterTitle.subtitle.position)

    BetterTitle.position = _toVec2(cfg.position, BetterTitle.position)

    if type(cfg.icon) == "table" then
        BetterTitle.setIcon(cfg.icon.file, cfg.icon.position)
    end

    if type(cfg.padding) == "table" then
        BetterTitle.setPadding(cfg.padding)
    end

    if type(cfg.hideOriginalTitle) == "boolean" then
        BetterTitle.hideOriginalTitle = cfg.hideOriginalTitle
    end

    return BetterTitle.refresh()
end

---@return BetterTitle
function BetterTitle.initialize()
    assert(pane ~= nil, "Pane is required. Make sure that the script in the interface context.")
    BetterTitle.loadFromConfig()
    return BetterTitle.createWidgets()
end
