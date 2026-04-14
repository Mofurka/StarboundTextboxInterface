# Starbound Textbox Interface

A lightweight and flexible textbox implementation for Starbound UI, built on top of canvas rendering.

> Author: https://github.com/Mofurka  
> Please credit if you use or modify this code  

---

## ✨ Features

- UTF-8 text support
- Custom canvas-based rendering
- Cursor navigation and text selection
- Mouse and keyboard interaction
- Multiline editing
- Clipboard support (copy / paste / cut)
- Word-based navigation
- Scrolling
- Placeholder (hint) support
- Customizable appearance via public API
- Dynamic height functionality
- Redo/Undo operations

---

## 📦 Usage

### Setup

```lua
local textbox = Textbox:setup("widgetName", {
    -- All the provided parameters are optional
    rect = {0,0,200,200},
    fontSize = 8,
    lineSpacing = 0,
    hint = "Textbox hint",
    hintColor = {255, 255, 255},
    selectionColor = {255, 255, 255},
    caretColor = {255, 255, 255},
    tabInsertText = "    ",
    onChanged = function(text)
        sb.logInfo("Text changed: %s", text)
    end,
    onEnterKey = function()
        sb.logInfo("Enter key pressed")
    end,
    onEscapeKey = function()
        sb.logInfo("Escape key pressed")
    end,
    maxHeight = 120, -- Turns on the dynamic height functionality
    onSizeChange = function(newSize)
        sb.logInfo("Textbox changed size")
    end
})
```

### Setup Guide

You should put the `require("/scripts/utils/textbox.lua")` at the beggining or at the end of your file.

Dpending on the method there will be two different implementations:

#### If you put require at the beggining of the script:

You need to add textbox hooks like this:

```lua
require("/scripts/utils/textbox.lua")

function init()
    Textbox.init()
end

function update(dt)
    Textbox.update(dt)
end

function uninit()
    Textbox.uninit()
end
```

#### If you put require at the end of the script:

You don't need to call the hooks

```lua
function init()
end

function update(dt)
end

function uninit()
end

require("/scripts/utils/textbox.lua")
```

---

## Public API

#### `Textbox` Textbox:setup(`string|nil` widgetName, `table|nil` options)

Create and initialize a new textbox instance attached to a widget (or pane).

---

#### `string` textbox:getText()

Get current textbox text.

---

#### `string` textbox:getSelectedText()

Get selected text.

---

#### `string` textbox:replaceSelectedText()

Sets the text in the selected area.

---

#### `nil` textbox:setText(`string|string[]` text)

Set text for the current textbox. Arrays are joined with `"\n"`.

---

#### `boolean` textbox:focus()

Focus the textbox and activate keyboard input.

---

#### `boolean` textbox:blur()

Remove focus from the textbox and clear current selection.

---

#### `boolean` textbox:hasFocus()

Return whether textbox is currently focused.

---

#### `nil` textbox:clear()

Clear all text and reset cursor, selection, and scroll.

---

#### `nil` textbox:setOnChanged(`fun(newText: string)` fn)

Set callback fired each time textbox text changes.

---

#### `nil` textbox:setOnEnterKey(`fun()` fn)

Set callback fired on Enter key.

---

#### `nil` textbox:setOnEscapeKey(`fun()` fn)

Set callback fired on Escape key.

---

#### `nil` textbox:setOnSizeChange(`fun(newSize: number[])` fn)

Set callback fired on changing the textbox size. Dynamic height functionality only.

---

#### `nil` Textbox.setDebug(`boolean` enabled)

Enable or disable debug logging for the textbox module.

---

#### `string` textbox:destroy()

Destroy textbox widgets/canvases and remove instance from active list.

---

#### `number` textbox:getCursorPos()

Get current cursor position (UTF-8 character index).

---

#### `nil` textbox:setCursorPos(`number` pos)

Set cursor position (clamped to valid text bounds).

---

#### `nil` textbox:setTabInsertText(`string` text)

Set text inserted when `Tab` key is pressed.

---

#### `number` textbox:getLineCount()

Get current wrapped line count.

---

#### `number` textbox:getScroll()

Get current vertical scroll offset.

---

#### `nil` textbox:setScroll(`number` scrollY)

Set vertical scroll offset (clamped to valid range).

---

#### `nil` textbox:setCaretColor(`number[]` color)

Set caret color as `{r, g, b, a}`.

---

#### `nil` textbox:setSelectionColor(`number[]` color)

Set selection highlight color as `{r, g, b, a}`.

---

#### `nil` textbox:setTextColor(`number[]` color)

Set text color as `{r, g, b, a}`.

---

#### `nil` textbox:setHintColor(`number[]` color)

Set hint color as `{r, g, b, a}`.

---

#### `nil` textbox:setFontSize(`number` size)

Set font size and recalculate layout/line height.

---

#### `number` textbox:getFontSize()

Get current font size.

---

#### `nil` textbox:setLineSpacing(`number` spacing)

Set extra spacing between lines in pixels. Applied only when wrapped/content line count is geater than one.

---

#### `number` textbox:getLineSpacing()

Get current extra spacing between lines in pixels.

---

#### `nil` textbox:setHint(`string` hint)

Set placeholder (hint) text shown when empty and unfocused.

---

#### `string` textbox:getHint()

Get current placeholder (hint) text.

---

#### `nil` textbox:setMaxHeight(maxHeight)

Set max height of textbox. Enables the dynamic height functionality.

---

#### `number` textbox:getMaxHeight()

Get current max height of the textbox.

---

### Module lifecycle hooks

#### `nil` Textbox.init()

Initialize textbox module in pane context.

---

#### `nil` Textbox.update(`number` dt)

Update all active textboxes each frame (input + rendering).

---

#### `nil` Textbox.uninit()

Cleanup and destroy all active textboxes.

---

## Controls

| Key                         | Action             |
|-----------------------------|--------------------|
| ← →                         | Move cursor        |
| Ctrl + ← →                  | Move by word       |
| ↑ ↓                         | Move between lines |
| Home / End                  | Line start / end   |
| Ctrl Home / End             | Text start / end   |
| Backspace / Delete          | Remove text        |
| Ctrl + Backspace            | Remove word        |
| Ctrl + A                    | Select all         |
| Ctrl + C                    | Copy               |
| Ctrl + X                    | Cut                |
| Ctrl + V                    | Paste              |
| Ctrl + Z                    | Undo last action   |
| Ctrl + Y (Ctrl + Shift + Z) | Redo last action   |
| Shift + Enter               | New line           |

---

# Starbound Combobox Interface

A flexible dropdown combobox implementation for Starbound UI, allowing users to select from a list of options with optional filtering.

## ✨ Features

- Button-based dropdown activation
- Customizable list styling via schemas
- Optional search/filter functionality
- Scrollable list area
- Keyboard and mouse interaction
- Selection callbacks
- Dynamic value management
- Display name / internal value separation

---

## 📦 Usage

### Setup

First, add the require statement to your script:

```lua
require "/interface/combobox/scripts/combobox.lua"
```

Then bind the combobox to an existing button widget:

```lua
local combobox = Combobox:bind("buttonWidgetName", 
    {
        -- Value -> Display Name mapping
        ["value1"] = "Display Name 1",
        ["value2"] = "Display Name 2",
        ["value3"] = "Display Name 3"
    },
    function(value, name)
        sb.logInfo("Selected: %s (value: %s)", name, value)
    end,
    {
        -- All options are optional
        background = "/path/to/background.png",
        offset = {0, -100},
        defaultValue = "value1",
        closeOnSelect = true,
        filter = true,  -- Enable search filter
        -- filter = { ... }  -- Or provide custom filter options
        scrollArea = {},  -- Custom scroll area styling
        listSchema = {},  -- Custom list item styling
        onOpen = function()
            sb.logInfo("Combobox opened")
        end,
        onClose = function()
            sb.logInfo("Combobox closed")
        end
    }
)
```

### Values Format

Values can be provided as either a table with key-value pairs or a simple array:

```lua
-- Key-value format (value -> display name)
{
    ["internal_value"] = "Display Name",
    ["color_red"] = "Red",
    ["color_blue"] = "Blue"
}

-- Array format (display names become both key and value)
{"Option 1", "Option 2", "Option 3"}
```

---

## Public API

#### `Combobox` Combobox:bind(`string` widgetName, `table` values, `function` onSelect, `table|nil` options)

Bind a combobox to an existing button widget. Returns a combobox instance.

**Parameters:**
- `widgetName`: Name of the button widget to attach to
- `values`: Table of values (`{value = "display name", ...}`)
- `onSelect`: Callback function `function(value, displayName)` called on selection
- `options`: Configuration table (see below)

---

#### `table` ComboboxOptions

Configuration options for the combobox:

- `background` _(string)_ - Path to the background image. Defaults to filter-appropriate background.
- `offset` _(Vec2F)_ - Position offset `{x, y}` from the button widget.
- `defaultValue` _(string)_ - Value to select by default.
- `closeOnSelect` _(boolean)_ - Whether to close the dropdown after selection. Default: `false`
- `filter` _(table|boolean)_ - Enable filtering. Set to `true` for defaults or provide custom options.
- `scrollArea` _(table)_ - Customize scroll area styling (`thumbs` and `buttons` tables).
- `listSchema` _(table)_ - Customize list item appearance:
  - `background` - Path to background image
  - `backgroundFilter` - Alternative background path
  - `listSelected` - Path to selected item image
  - `listUnselected` - Path to unselected item image
  - `textOffset` - `{x, y}` offset for text within items
  - `spacing` - `{x, y}` spacing between items
- `onOpen` _(function)_ - Callback when dropdown opens.
- `onClose` _(function)_ - Callback when dropdown closes.

---

#### `table` ComboboxFilterOptions

Configuration for the optional search filter:

- `position` _(Vec2F)_ - Position of the filter textbox `{x, y}`. Default: `{0, 0}`
- `textOffset` _(Vec2F)_ - Text offset within the textbox `{x, y}`. Default: `{5, 2}`
- `hint` _(string)_ - Placeholder text. Default: `"..."`
- `color` _(string)_ - Hint text color. Default: `"gray"`
- `height` _(number)_ - Height of the filter textbox. Default: `20`

---

#### `nil` combobox:fillValues(`string|nil` searchText, `string|nil` defaultValue)

Populate the list with values. If `searchText` is provided, filters the list by display name (case-insensitive).

---

#### `nil` combobox:updateValues(`table` values, `string|nil` defaultValue)

Replace all values and optionally set a new default.

---

#### `nil` combobox:toggle()

Toggle the dropdown visibility (open if closed, close if open).

---

#### `nil` combobox:open()

Open the dropdown list.

---

#### `nil` combobox:close()

Close the dropdown list.

---

#### `nil` combobox:setSelected(`string` value)

Programmatically select an item by value.

---

## Complete Example

```lua
require "/interface/combobox/combobox.class.lua"

function init()
    local options = {
        ["opt_action"] = "Perform Action",
        ["opt_settings"] = "Open Settings",
        ["opt_about"] = "About"
    }
    
    local combobox = Combobox:bind("optionsButton", options, function(value, name)
        if value == "opt_action" then
            sb.logInfo("Action performed!")
        elseif value == "opt_settings" then
            sb.logInfo("Opening settings...")
        end
    end, {
        defaultValue = "opt_action",
        closeOnSelect = true,
        filter = true,
        offset = {0, -80},
        onOpen = function()
            sb.logInfo("Menu opened")
        end
    })
    
    -- Later, update the options
    combobox:updateValues({
        ["opt_export"] = "Export Data",
        ["opt_import"] = "Import Data"
    })
    
    -- Select an option programmatically
    combobox:setSelected("opt_export")
end
```

---

## License

Free to use and modify. Attribution is appreciated.

## Contributors

* @KrashV (Degranon)

## Demonstation
[Video](https://youtu.be/hw2bQblKkdk)
