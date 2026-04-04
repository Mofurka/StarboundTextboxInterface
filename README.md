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

| Key                | Action             |
|--------------------|--------------------|
| ← →                | Move cursor        |
| Ctrl + ← →         | Move by word       |
| ↑ ↓                | Move between lines |
| Home / End         | Line start / end   |
| Ctrl Home / End    | Text start / end   |
| Backspace / Delete | Remove text        |
| Ctrl + Backspace   | Remove word        |
| Ctrl + A           | Select all         |
| Ctrl + C           | Copy               |
| Ctrl + X           | Cut                |
| Ctrl + V           | Paste              |
| Shift + Enter      | New line           |

---

## License

Free to use and modify. Attribution is appreciated.

## Contributors

* @KrashV (Degranon)

## Demonstation
[Video](https://youtu.be/hw2bQblKkdk)
