-- Combobox class.lua
require "/scripts/vec2.lua"

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

---@class Combobox
Combobox = {
    widgetName = "",
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

function Combobox:_new(widgetName, onSelect, values, defaultValue, closeOnSelect, onClose, onOpen)
    local obj = {}
    obj.widgetName = widgetName
    obj.onSelect = onSelect
    obj.values = values or {}
    obj.defaultValue = defaultValue or nil
    obj.closeOnSelect = closeOnSelect or false
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

    -- Backwards capability
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

    local cbUUID = sb.makeUuid()

    local backgroundImage = options.background or (filterEnabled and DEFAULT_SCHEMA.backgroundFilter or DEFAULT_SCHEMA.background)
    local backgroundSize = root.imageSize(backgroundImage)

    local lytPosition = vec2.add(widget.getPosition(widgetName), options.offset or {0, widget.getSize(widgetName)[2]})

    local layoutTemplate = {
        type = "layout",
        layoutType = "basic",
        size = backgroundSize,
        position = lytPosition,
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
    local parentFullWidgetName = parentWidgetName and (parentWidgetName .. ".") or ""

    local jsonPath = isChild and widgetName:gsub("%.", ".children.") or widgetName
    widgetConfig = sb.jsonQuery(config.getParameter("gui"), jsonPath)
    widgetName = childWidgetName

    -- Remove old widget
    if isChild then
        widget.removeChild(parentWidgetName, widgetName)
    else
        pane.removeWidget(widgetName)
    end

    -- Setup combobox config
    widgetConfig.callback = "comboboxClick"
    widgetConfig.data = widgetConfig.data or {}
    widgetConfig.data.comboboxData = {
        name = childWidgetName,
        parentWidgetName = parentWidgetName or "",
        values = values,
        defaultValue = options.defaultValue,
        uuid = cbUUID
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
                    parentWidgetName = parentWidgetName or "",
                    uuid = cbUUID
                }
            }
        }
    end

    -- Add new widgets
    local lytName = "lytCombobox" .. widgetName
    if isChild then
        widget.addChild(parentWidgetName, widgetConfig, widgetName)
        widget.addChild(parentWidgetName, layoutTemplate, lytName)
    else
        pane.addWidget(widgetConfig, widgetName)
        pane.addWidget(layoutTemplate, lytName)
    end

    -- Create and store combobox
    comboboxes[cbUUID] = self:_new(parentFullWidgetName .. lytName, onSelect, values, options.defaultValue, options.closeOnSelect, options.onClose, options.onOpen)

    widget.setData(parentFullWidgetName .. "lytCombobox" .. widgetName .. ".scrollAreaCombobox.listCombobox", {
        comboboxData = {
            name = widgetName,
            parentWidgetName = parentWidgetName,
            uuid = cbUUID
        }
    })

    comboboxes[cbUUID]:fillValues(nil, options.defaultValue)
    return comboboxes[cbUUID]
end

function Combobox:fillValues(searchText, defaultValue)
    widget.clearListItems(self.widgetName .. ".scrollAreaCombobox.listCombobox")

    for value, name in pairs(self.values) do
            if not searchText or name:lower():find(searchText:lower(), nil, true) then
            local li = widget.addListItem(self.widgetName .. ".scrollAreaCombobox.listCombobox")
            widget.setText(self.widgetName .. ".scrollAreaCombobox.listCombobox." .. li .. ".option", name)
            widget.setData(self.widgetName .. ".scrollAreaCombobox.listCombobox." .. li, value)

            if defaultValue and value == defaultValue then
                widget.setListSelected(self.widgetName .. ".scrollAreaCombobox.listCombobox", li)
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
    local isCurrentlyVisible = widget.active(self.widgetName)
    if isCurrentlyVisible then
        self:close()
    else
        self:open()
    end
end

function Combobox:close()
    widget.setVisible(self.widgetName, false)
    if self.onClose then
        self.onClose()
    end
end

function Combobox:open()
    widget.setVisible(self.widgetName, true)
    if self.onOpen then
        self.onOpen()
    end
end

function Combobox:setSelected(value)
    widget.setListSelected(self.widgetName .. ".scrollAreaCombobox.listCombobox", self.listMap[value] or "")
end

function getCombobox(uuid)
    if comboboxes[uuid] then
        return comboboxes[uuid]
    else
        sb.logError("Combobox with UUID '" .. uuid .. "' not found.")
        return Combobox:_new(callback)
    end
end

function comboboxClick(widgetName, widgetData)
    if widgetData.comboboxData then
        getCombobox(widgetData.comboboxData.uuid):toggle()
    end
end

function comboboxSelect(widgetName, widgetData)
    
    if widgetData.comboboxData then

        if widgetData.comboboxData.parentWidgetName then
            widgetName = widgetData.comboboxData.parentWidgetName .. "." .. "lytCombobox" .. widgetData.comboboxData.name
        else
            widgetName = "lytCombobox" .. widgetData.comboboxData.name
        end

        local li = widget.getListSelected(widgetName .. ".scrollAreaCombobox.listCombobox")
        if li then
            local cb = getCombobox(widgetData.comboboxData.uuid)
            if cb and cb.onSelect then
                cb.onSelect(widget.getData(widgetName .. ".scrollAreaCombobox.listCombobox." .. li), widget.getText(widgetName .. ".scrollAreaCombobox.listCombobox." .. li .. ".option"))
                if cb.closeOnSelect then
                    cb:close()
                end
            end
        end
    end
end

function comboboxFilter(widgetName, widgetData)
    if widgetData.comboboxData then
        if widgetData.comboboxData.parentWidgetName and widgetData.comboboxData.parentWidgetName ~= "" then
            widgetName = widgetData.comboboxData.parentWidgetName .. "." .. "lytCombobox" .. widgetData.comboboxData.name .. "." .. widgetName
        else
            widgetName = "lytCombobox" .. widgetData.comboboxData.name .. "." .. widgetName
        end

        local cb = getCombobox(widgetData.comboboxData.uuid)
        if cb then
            local searchText = widget.getText(widgetName)

            cb:fillValues(searchText)
        end
    end
end