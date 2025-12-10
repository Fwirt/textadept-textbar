-- Copyright (c) 2025 Fwirt

-- A Textadept module for creating custom programmable single-line display widgets

-- TODO:
-- +Fix find dialog handling, if possible
-- May need to modify platform code to allow reselection of find dialog. Or just write ex module
-- and stop using it.
-- +Implement mixed alignment handling
-- Maybe a A LEFT aligned element between a RIGHT aligned element and a CENTER aligned element
-- should implement the next LEFT tabstop after the previous RIGHT tabstop? Or should it advance
-- the RIGHT tabstop to the left by the difference between the two, allowing for fixed-width
-- right-aligned fields??
-- +Implement field styling
-- Need to fix Scintilla get/set styled text first, not going to reimplement that in Lua.
-- +Optimize update() by rewriting it in C

-- globals --

local M = {}

local B, V -- backing buffer, captive view
local Vw -- cached view width

local fields = {}
local status_meta = {}

-- init the textbars table if it doesn't exist
_G._TEXTBARS = _G._TEXTBARS or {}

local NAME = "textbar"..#_G._TEXTBARS+1 -- default name of the textbar buffer

M.LEFT = "left"
M.RIGHT = "right"
M.CENTER = ""

M.STYLE_DEFAULT = _G.view.STYLE_DEFAULT

M.padding = 5

-- functions --

-- buffer:add_styled_text() does not work because luaL_checkscintilla() ignores
-- all struct types, even though cells is technically just a char*. If gen_iface.lua
-- is updated to assign cells to 7 instead of 9, and a wrapper is added to get_styled_text,
-- then that function could be made to work. buffer.lua just overwrites buffer.text_range
-- with a custom handler function so the same strategy could be used here.
--[[local function add_styled_text(text_table)
	local cur = B.current_pos
	for _, v in ipairs(text_table) do
		B:add_text(v.text)
		--B:start_styling(cur, 0)
		--B:set_styling(B.current_pos - cur, v.style)
		--cur = B.current_pos
	end
end]]

local function indexof(t, value)
	for i, v in ipairs(t, value) do
		if v == value then return i end
	end
	for i, v in pairs(t, value) do
		if v == value then return i end
	end
	return nil
end

-- Fill the buffer with styled field text and update the tab stops.
M.update = function ()
	if not (B and V) then -- the view must be initialized first!
		error("setup_view must be called first")
		return
	end

	Vw = V.width
	local left, right = M.padding, Vw - M.padding
	local centers = {}
	local line_text = ""
	local field_text

	V:clear_tab_stops(1)
	V:clear_all()
	-- first we have to add the tab stops before printing any text
	for _, f in ipairs(fields) do
		field_text = f.text
		if #field_text > 0 then 
			if f.align == M.LEFT then
				V:add_tab_stop(1, left)
				left = left + (f.width + M.padding)
			elseif f.align == M.RIGHT then
				right = right - (f.width + M.padding)
				V:add_tab_stop(1, right)
			else
				table.insert(centers, f.width)
			end
			line_text = line_text .. '\t' .. field_text
		end
	end

	local spacing = Vw//(#centers+1)
	for i, v in ipairs(centers) do
		V:add_tab_stop(1, (spacing*i - v//2))
	end
	
	V:add_text(line_text)
	V:set_save_point()
end

-- Since we want complete control over styling, don't let the lexer
-- get in our way. There is no way to disable the lexer so this just
-- prevents it from ever getting called on this buffer.
local function preempt_lexer(end_pos, buffer)
	if buffer == B then return true end
end
events.connect(events.STYLE_NEEDED, preempt_lexer, 1)

-- Create a view at the bottom of the window that is one line tall
-- to hold the document and set local pointer variables
local function setup_buffer(name)
	-- we can only setup a buffer with a captive view
	if not V then return end
	-- if no name specified then assume we want a new buffer
	NAME = NAME or name
	for _, buffer in ipairs(_BUFFERS) do
		if buffer._type == NAME then
			B = buffer
		end
	end
	print("B is "..tostring(B))
	B = B or _G.buffer.new()
	V:goto_buffer(B)
	B._type = NAME
	status_meta.__name = NAME
	V.undo_collection = false
	V.scroll_width_tracking = false
	V.scroll_width = 1
	V.margins = 0
	V.margin_left = 0
	V.margin_right = 0
	V.h_scroll_bar = false
	V.v_scroll_bar = false
	V.caret_line_visible = false
	V.tab_width = 1
	V.minimum_tab_width = 1
	V.indentation_guides = V.IV_NONE
	B:clear_all()
	B:set_save_point()
	
	-- TODO: replace the view.goto_buffer, buffer.close, buffer.delete
	-- methods with empty functions to prevent them from breaking this
	-- module
end

local function maintain_size(resized)
	if resized == V then
		Vw = V.width
		M.update()
		V.height = V:text_height(1)
	end
end

local function setup_view(newview, name)
	if not newview then
		_G.view:split()
		newview = _G.view
	end
	V = newview
	M.STYLE_DEFAULT = V.STYLE_DEFAULT
	V.styles[M.STYLE_DEFAULT].font = nil
	V.styles[M.STYLE_DEFAULT].size = nil
	V:set_styles()
	V.extra_ascent = M.padding
	V.extra_descent = M.padding
	V.height = V:text_height(1)
	Vw = V.width
	events.connect(events.RESIZE, maintain_size)
	setup_buffer(name)
	-- TODO: add event handler for tab switch so we can't switch buffers
end
-- Hijack the ui metatable so that writes to the builtin statusbar
-- also update the replacement, for compatibility with existing
-- modules
M.replace_statusbar = function()
	-- setup the textbar the same as the statusbar, with fields on the left and right
	M.statusbar = ""
	M.statusbar.index = 1
	M.statusbar.align = M.LEFT
	M.buffer_statusbar = ""
	M.buffer_statusbar.align = M.RIGHT
	-- Try to match the ui default window background style. This will fail if the user
	-- has a custom GTK or Qt theme presently, since the theme colors are hardcoded.
	-- Need to add a method to platform.h to get the window background color for theme
	-- color matching.
	--V.styles[V.STYLE_DEFAULT].back = V.caret_line_back
	--V:set_styles()
	local ui_meta = getmetatable(_G.ui)
	local new_meta = {}
	for key, value in pairs(ui_meta) do
		new_meta[key] = value
	end
	new_meta.__newindex = function (t, key, value)
		if (key == "buffer_statusbar_text") then
--			M.buffer_statusbar.text = {{text=value,style=M.STYLE_DEFAULT}}
			M.buffer_statusbar.text = value
		elseif (key == "statusbar_text") then
--			M.statusbar.text = {{text=value,style=M.STYLE_DEFAULT}}
			M.statusbar.text = value
		else
			ui_meta.__newindex(t, key, value)
		end
	end
	setmetatable(_G.ui, new_meta)
	_G.ui.statusbar = false
end

-- TODO: Support mixed alignments where "center" fields are like
-- separators in between left and right aligned fields.
-- While I plan to support mixed alignments in the future, for now
-- this function will fix up the alignments of the fields to prevent
-- undesired behavior.
local function fix_alignment()
	local sets = {M.LEFT, M.CENTER, M.RIGHT}
	current_set = 1
	for i, v in ipairs(fields) do
		if indexof(sets, v.align) > current_set then
			current_set = indexof(sets, v.align)
		else
			v.align = sets[current_set]
		end
	end
end

local function add_field(key)
	if not (B and V) then -- the view must be initialized first!
		error("call textbar on a view first")
	end
--	local styled_text = {{text = '', style = M.STYLE_DEFAULT}}
	local text = ""
	local style = M.STYLE_DEFAULT
	local align = M.CENTER
	local width = 0
	local fixed_width = 0
	local index, name

	local get_plain = function ()
		local plain_text = ""
		for index, value in ipairs(styled_text) do
			plain_text = plain_text .. value.text
		end
		return plain_text
	end
	local set_text = function (new_text)
		text = tostring(new_text)
		width = V:text_width(style, text)
		if fixed_width > width then width = fixed_width end
		M.update()
--[[		if type(text) == "table" then
			styled_text = text
			M.update()
		else
			local text = tostring(new_text)
			-- if no update needed then avoid an expensive update (for functions that update the statusbar on redraw)
			if (#styled_text ~= 1 or styled_text[1].text ~= text or styled_text[1].style ~= M.STYLE_DEFAULT) then
				styled_text[1].text = string.gsub(text, "\t", " ")
				styled_text[1].style = M.STYLE_DEFAULT
				M.update()
			end
		end]]
	end

	local field_meta = {}
	field_meta.__index = function (t, key)
		if key == "text" then
--			return styled_text
			return text
		elseif key == "align" then
			return align
		elseif key == "width" then
			return width
		elseif key == "name" then
			return name
		elseif key == "index" then
			return index
		else
			return rawget(t, key)
		end
	end
	field_meta.__newindex = function (t, key, value)
		if key == "text" then
			set_text(value)
--[[			if type(value) == "string" or type(value) == "table" then
				set_text(value)
			else
				error("text must be string, table, or nil")
			end]]
		elseif key == "align" and align ~= value then
			align = value
			fix_alignment() -- do this until we have more complex handling
			M.update()
		elseif key == "width" and fixed_width ~= value then
			fixed_width = value
			M.update()
		elseif key == "name" and value ~= name then
			if name then fields[value], fields[name] = fields[name], nil
			else fields[value] = fields[index] end
			name = value
		-- swap field position but make sure it's necessary first
		elseif key == "index" and value ~= index and value ~= index+1 and value <= #fields+1 then
			table.insert(fields, value, fields[index])
			table.remove(fields, value > index and index or index+1)
			index = value
		else
			rawset(t, key, value)
		end
	end
	field_meta.__tostring = get_plain
	field_meta.__name = "field"

	local new_field = {}
	setmetatable(new_field, field_meta)

	-- insert the new field into the table. This was going to be
	-- a separate function but it was only called from this one
	-- function and having direct access to the closure variables
	-- is more efficient.
	local pos = type(key) ~= "number" and #fields + 1 or key
	table.insert(fields, pos, new_field)
	index = pos
	if pos ~= key then
		new_field.name = key
	end
	fix_alignment() -- do this until we have more complex handling

	M.update()
end

local function delete_field(key)
	local index, name
	if type(key) == "number" then
		index, name = key, fields[key].name
	else
		index, name = fields[key].index, key
	end
	fields[name] = nil
	table.remove(fields, index)
	
	M.update()
end

-- Remove all event handlers and tie up any loose ends.
local function cleanup()
	events.disconnect(events.STYLE_NEEDED, preempt_lexer)
	events.disconnect(events.RESIZE, maintain_size)
end

status_meta.__index = function (t, key)
	if key == "view" then
		return V
	elseif key == "name" then
		return NAME
	else
		return fields[key]
	end
end
status_meta.__len = function (t, key)
	return #fields
end
status_meta.__newindex = function (t, key, value)
	if key == "name" and B then
		NAME = value
		B._type = NAME
		status_meta.__name = NAME
		return
	end
	if not fields[key] and value then
		add_field(key)
	elseif fields[key] and not value then
		delete_field(key)
		return
	end
	fields[key].text = value
end
status_meta.__call = function(func, ...)
	return setup_view(...)
end
setmetatable(M, status_meta)

table.insert(_G._TEXTBARS, M)

return M
