# Textbar

**this is in early alpha and is still buggy and slightly broken, but serves as a PoC**

A Textadept module that defines a customizable, programmable user-interface widget. Basically a statusbar than can reside in any horizontally split view.

Install this module by copying it into your ~/.textadept/modules/ directory or Textadept's modules/ directory.

To setup a new textbar, call the following code from the Lua command entry, or add a way to invoke something similar to your *~/.textadept/init.lua*:

```lua
-- Add a horizontal split to become the textbar
view:split()
-- Capture the view as a textbar
textbar = require("textbar")
textbar(view)
-- Add fields to the textbar and set their text
textbar.new_field = "Hello world!"
textbar.new_field.align = textbar.RIGHT
-- Delete a field
textbar.delete_field(new_field) -- this may still be broken right now lol
-- Replace the built-in statusbar by hooking into the ui metatable
textbar.replace_statusbar()
```

## Known bugs/limitations
- If used to replace the statusbar
  - the command entry stops working because it keeps losing focus
  - the find/replace dialog behaves oddly
 
## Todo
- Fix bugs
- Add support for styling fields (preliminary explorations are present but commented out)
- Add support for mixed alignment layouts
- Clean up public methods and fields

## Possible future features
- Clickable fields
- Text entry fields
