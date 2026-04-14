-- Combobox class.lua
require "/scripts/vec2.lua"


local function widgetPath(...)
    return table.concat({ ... }, ".")
end

---@class ComboboxSchema
---@field listUnselected string - Path to the unselected list item image
---@field listSelected string - Path to the selected list item image
---@field textOffset Vec2F - Offset of the text within the list item
---@field spacing Vec2F - Spacing between the list items
local DEFAULT_SCHEMA = {
    background = "/interface/combobox/templates/background.png",
    backgroundFilter = "/interface/combobox/templates/backgroundFilter.png",
    listSelected = "/interface/combobox/templates/listselected.png",
    listUnselected = "/interface/combobox/templates/listunselected.png",
    textOffset = {5, 2},
    spacing = {0, 0}
}

---@class ComboboxFilterOptions
---@field position Vec2F - Position of the filter textbox widget relative to the layout
---@field textOffset Vec2F - Offset of the text within the textbox
---@field hint string - Placeholder hint text for the filter textbox
---@field color string - Color of the hint text (e.g., "gray", hex color code)
---@field height number - Height of the filter textbox widget
local DEFAULT_FILTER = {
    position = {0, 0},
    textOffset = {5, 2},
    hint = "...",
    color = "gray",
    height = 20
}

---@class ComboboxScrollAreaOptions
---@field buttons table - Table of scrollArea buttons redefinition
---@field thumbs table - Table of scrollArea thumbs redefinition
local DEFAULT_SCROLL_AREA = {
    thumbs = nil,
    buttons = nil
}

local WIDGET_NAME = {
    wrapper = "listWrapCombobox",
    layout = "lytCombobox",
    scrollArea = "scrollAreaCombobox",
    list = "listCombobox"
}

---@class Combobox
Combobox = {
    layout = "",
    values = {},
    listMap = {},
    defaultValue = nil,
    onSelect = function()
    end,
    onClose = function()
    end,
    onOpen = function()
    end,
    backgroundImage = nil -- must be provided
}

local comboboxes = {}

function Combobox:_new(widgetName, onSelect, values, defaultValue, onClose, onOpen)
    local obj = {}
    obj.widgetName = widgetName
    obj.onSelect = onSelect
    obj.values = values or {}
    obj.defaultValue = defaultValue or nil
    obj.listMap = {}
    obj.onClose = onClose or function()
    end
    obj.onOpen = onOpen or function()
    end

    setmetatable(obj, self)
    self.__index = self

    return obj
end

---@class ComboboxOptions
---@field background string - Path to the background image
---@field offset Vec2F - Offset from the button widget position
---@field filter ComboboxFilterOptions|boolean - Configuration for the optional filter textbox (omit to disable). If `true`, default values will be used
---@field scrollArea ComboboxScrollAreaOptions - Configuration for the scrollArea images
---@field listSchema ComboboxListItems - Custom schema for the list widget
---@field defaultValue string - Default selected value
---@field closeOnSelect boolean - Whether to close the combobox after selection
---@field onClose function - Callback function when the combobox is closed
---@field onOpen function - Callback function when the combobox is opened


--- Bind a combobox to a button widget
---@param widgetName string - The name of the button widget to bind the combobox to
---@param values table - A table of values to populate the combobox with (key-value pairs)
---@param onSelect function - A function to call when an item is selected (receives value and name)
---@param options ComboboxOptions - Optional settings for the combobox
---@return Combobox
function Combobox:bind(widgetName, values, onSelect, options)
    options = options or {}

    if not widget.getChecked(widgetName) == nil then
        sb.logError("Combobox:bind - Widget '" .. widgetName .. "' does not exist or is not a button.")
        return nil
    end

    local filterEnabled = not not options.filter

    -- Backward capability
    if type(options.filter) == "boolean" then
        options.filter = {}
    end

    options.filter = sb.jsonMerge(DEFAULT_FILTER, options.filter or {})
    options.listSchema = sb.jsonMerge(DEFAULT_SCHEMA, options.listSchema or {})
    options.scrollArea = sb.jsonMerge(DEFAULT_SCROLL_AREA, options.scrollArea or {})

    -- Reformat values to a table if it's an array
    for k, v in ipairs(values or {}) do
        values[k] = nil
        values[v or k] = v
    end

    local backgroundImage = options.background or (filterEnabled and DEFAULT_SCHEMA.backgroundFilter or DEFAULT_SCHEMA.background)
    local backgroundSize = root.imageSize(backgroundImage)

    local layoutTemplate = {
        type = "layout",
        layoutType = "basic",
        size = backgroundSize,
        position = {0, 0},
        visible = false,
        children = {
            ["backgroundCombobox"] = {
                type = "image",
                file = backgroundImage,
                zlevel = 0
            },
            ["scrollAreaCombobox"] = {
                type = "scrollArea",
                position = filterEnabled and {0, options.filter.height} or {0, 0},
                size = {backgroundSize[1], backgroundSize[2] - (filterEnabled and options.filter.height or 0)},
                zlevel = 2,
                buttons = options.scrollArea.buttons,
                thumbs = options.scrollArea.thumbs,
                children = {
                    ["listCombobox"] = {
                        type = "list",
                        zlevel = 3,
                        callback = "comboboxSelect",
                        schema = {
                            selectedBG = options.listSchema.listSelected,
                            unselectedBG = options.listSchema.listUnselected,
                            spacing = options.listSchema.spacing,
                            memberSize = root.imageSize(options.listSchema.listUnselected),
                            listTemplate = {
                                background = {
                                    type = "image",
                                    file = options.listSchema.listUnselected
                                },
                                option = {
                                    type = "label",
                                    position = options.listSchema.textOffset
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    local isChild = widgetName:find("%.")
    local childWidgetName = widgetName:match("([^%.]+)$")
    local parentWidgetName = isChild and widgetName:match("(.+)%..+") or nil
    local parentFullWidgetName = parentWidgetName or ""

    local jsonPath = isChild and widgetName:gsub("%.", ".children.") or widgetName
    widgetConfig = sb.jsonQuery(config.getParameter("gui"), jsonPath)

    local wrapperListPosition = vec2.add(widget.getPosition(widgetName), options.offset or {0, widget.getSize(widgetName)[2]})
    
    -- Remove old widget
    if isChild then
        widget.removeChild(parentWidgetName, childWidgetName)
    else
        pane.removeWidget(childWidgetName)
    end

    -- Setup combobox config
    widgetConfig.data = widgetConfig.data or {}
    widgetConfig.data.comboboxData = {
        name = childWidgetName,
        parentWidgetName = parentWidgetName,
        values = values,
        defaultValue = options.defaultValue
    }

    -- Add optional filter
    if filterEnabled then
        layoutTemplate.children["textComboboxFilter"] = {
            type = "textbox",
            position = options.filter.textOffset,
            hint = options.filter.hint,
            color = options.filter.color,
            callback = "comboboxFilter",
            zlevel = 4,
            data = {
                comboboxData = {
                    name = childWidgetName,
                    parentWidgetName = parentWidgetName
                }
            }
        }
    end

    local wrapperListTemplate = {
        type = "list",
        position = wrapperListPosition,
        callback = "null",
        schema = {
            spacing = {0, 0},
            memberSize = backgroundSize,
            listTemplate = {
                -- The entire combobox structure becomes a list item template
                [WIDGET_NAME.layout] = layoutTemplate
            }
        }
    }

    local wrapperName = WIDGET_NAME.wrapper .. childWidgetName

    -- Add new widgets
    if isChild then
        widget.addChild(parentWidgetName, widgetConfig, childWidgetName)
        widget.addChild(parentWidgetName, wrapperListTemplate, wrapperName)
    else
        pane.addWidget(widgetConfig, widgetName)
        pane.addWidget(wrapperListTemplate, wrapperName)
    end

    -- Create and store combobox
    local wrapperFullPath = widgetPath(parentFullWidgetName, wrapperName)

    local cb = self:_new(wrapperFullPath, onSelect, values, options.defaultValue, options.onClose, options.onOpen)

    -- Create list item and register the callbacks
    widget.registerMemberCallback(wrapperFullPath, "comboboxSelect", function()
        
        local innerListPath = widgetPath(wrapperFullPath, cb.li, WIDGET_NAME.layout, WIDGET_NAME.scrollArea, WIDGET_NAME.list)
        local li = widget.getListSelected(innerListPath)
        if li then
            if onSelect then
                cb:onSelect(
                    widget.getData(widgetPath(innerListPath, li)), 
                    widget.getText(widgetPath(innerListPath, li, "option"))
                )
            end
            if options.closeOnSelect then
                cb:close()
            end
        end
    end)

    widget.registerMemberCallback(wrapperFullPath, "comboboxFilter", function(widgetName, widgetData)
        local searchText = widget.getText(widgetPath(wrapperFullPath, cb.li, WIDGET_NAME.layout, widgetName))
        cb:fillValues(searchText)
    end)

    cb.li = widget.addListItem(wrapperFullPath)

    widget.setData(widgetPath(wrapperFullPath, cb.li, WIDGET_NAME.layout, WIDGET_NAME.scrollArea, WIDGET_NAME.list), {
        comboboxData = {
            name = widgetName,
            parentWidgetName = parentWidgetName
        }
    })

    cb:fillValues(nil, options.defaultValue)
    return cb
end


function Combobox:fillValues(searchText, defaultValue)
    local listPath = widgetPath(self.widgetName, self.li, WIDGET_NAME.layout, WIDGET_NAME.scrollArea, WIDGET_NAME.list)
    widget.clearListItems(listPath)

    for value, name in pairs(self.values) do
        if not searchText or name:lower():find(searchText:lower(), nil, true) then

            local li = widget.addListItem(listPath)
            widget.setText(widgetPath(listPath, li, "option"), name)
            widget.setData(widgetPath(listPath, li), value)

            if defaultValue and value == defaultValue then
                widget.setListSelected(widgetPath(listPath, li))
            end

            self.listMap[value] = li
        end
    end
end

function Combobox:updateValues(values, defaultValue)
    self.values = values or {}
    self:fillValues(nil, defaultValue)
end

function Combobox:toggle()
    local isCurrentlyVisible = widget.active(widgetPath(self.widgetName, self.li, WIDGET_NAME.layout))
    if isCurrentlyVisible then
        self:close()
    else
        self:open()
    end
end

function Combobox:close()
    widget.setVisible(widgetPath(self.widgetName, self.li, WIDGET_NAME.layout), false)
    if self.onClose then
        self.onClose()
    end
end

function Combobox:open()
    widget.setVisible(widgetPath(self.widgetName, self.li, WIDGET_NAME.layout), true)
    if self.onOpen then
        self.onOpen()
    end
end

function Combobox:setSelected(value)
    widget.setListSelected(widgetPath(self.widgetName, self.li, WIDGET_NAME.layout, WIDGET_NAME.scrollArea, WIDGET_NAME.list), self.listMap[value] or "")
end

function Combobox:destory()
    
end