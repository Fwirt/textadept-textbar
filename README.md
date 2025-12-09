# Textbar

**this is in early alpha and is still fragile but serves as a PoC**

A Textadept module that defines a customizable, programmable user-interface widget. Basically a statusbar than can reside in any horizontally split view.

It requires the view.height, view.width, and events.RESIZE features from my ta feature branch which has not been merged yet.

Install this module by copying it into your ~/.textadept/modules/ directory or Textadept's modules/ directory.

To setup a new textbar, call the following code from the Lua command entry:

```lua
-- Add a horizontal split to become the textbar
view:split()
-- Capture the view as a textbar
bar = require("textbar")
bar(view)
-- Add fields to the textbar by assigning to them
-- By name
bar.hello = "Hello world!"
-- Or by index
bar[2] = "Foo"
bar.hello = "Just assign to a field to change its text"
-- Fields can be renamed
bar[2].alias = "goodbye"
-- And deleted
bar.goodbye = nil
-- By default fields float in the center, but they can be aligned
bar.hello.align = textbar.LEFT
-- Replace the built-in statusbar by hooking into the ui metatable
textbar.replace_statusbar()
```

Per Mitchell's instructions, textbars should not be initialized in init.lua becuase they require the creation of new views and buffers.

## Known bugs/limitations
- Updating the statusbar removes focus from the find/replace dialog
- Closing the backing buffer or view breaks everything
- No cleaup code written yet
 
## Todo
- Fix bugs
- Add support for styling fields (preliminary explorations are present but commented out)
- Add support for mixed alignment layouts
- Clean up interface more

## Possible future features
- Clickable fields
- Text entry fields
