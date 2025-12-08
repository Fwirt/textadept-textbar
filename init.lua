	-- Copyright (c) 2025 Fwirt

--- A Textadept module that replaces the built-in statusbar with a Scintilla view.

-- Known issues:
-- sometimes the tab stops just randomly stop working, seems finicky
--- re: above: breaks when typing in another view, something to do with
--- the view not being focused and redrawing incorrectly. Easiest to
--- reproduct by setting up hijack_statusbar
-- need to setup buffer as not a file so it doesn't try to save it on close
-- random segfaults??? Trying to track this down

local M = {}

local B, V -- backing buffer, captive view
local Vw -- cached view width

local fields = {}

M.LEFT = "left"
M.RIGHT = "right"
M.CENTER = "center"

M.STYLE_DEFAULT = _G.view.STYLE_DEFAULT

M.padding = 5

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

-- We have to switch views to update the tab stops, but switching
-- views triggers a whole bunch of built-in events designed for
-- users switches, which we should ignore.
local block_switch_events = nil
local function preempt_event()
	return block_switch_events
end
events.connect(events.VIEW_BEFORE_SWITCH, preempt_event, 1)
events.connect(events.VIEW_AFTER_SWITCH, preempt_event, 1)

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
	
	local view_before = _G.view
	block_switch_events = true
	ui.goto_view(V)
	
	B:clear_tab_stops(1)
	B:clear_all()
	-- first we have to add the tab stops before printing any text
	for _, f in ipairs(fields) do
		if f.align == M.LEFT then
			B:add_tab_stop(1, left)
			left = left + (f.width + M.padding)
		elseif f.align == M.RIGHT then
			right = right - (f.width + M.padding)
			B:add_tab_stop(1, right)
		else
			table.insert(centers, f.width)
		end
		line_text = line_text .. '\t' .. f.text
	end

	local spacing = Vw//(#centers+1)
	for i, v in ipairs(centers) do
		B:add_tab_stop(1, (spacing*i - v//2))
	end
	
	B:add_text(line_text)
	B:set_save_point()
	
	ui.goto_view(view_before)
	block_switch_events = nil
end

-- Create a view at the bottom of the window that is one line tall
-- to hold the document and set local pointer variables
local function setup_buffer(name)
	-- we can only setup a buffer with a captive view
	if not V then return end
	if not name then name = 'statusbar' end
	for _, buffer in ipairs(_BUFFERS) do
		if buffer._type == name then
			B = buffer
		end
	end
	B = B or _G.buffer.new()
	V:goto_buffer(B)
	B._type = 'statusbar'
	B.undo_collection = false
	B.scroll_width_tracking = false
	B.scroll_width = 1
	B.margins = 0
	B.margin_left = 0
	B.margin_right = 0
	B.h_scroll_bar = false
	B.v_scroll_bar = false
	B.tab_width = 1
	B.minimum_tab_width = 1
	B.indentation_guides = B.IV_NONE
	B:clear_all()
	local function resize_statusbar(resized)
		if resized == V and not ui.command_entry.active then
			Vw = V.width
			M.update()
			V.height = V:text_height(1)
		end
	end
	events.connect(events.RESIZE, resize_statusbar)

end

M.setup_view = function (newview)
	if newview then
	    V = view
	else
	    -- setup new split
	    -- if the top level split is horizontal then we need to rebuild the split table.
	end
	M.STYLE_DEFAULT = V.STYLE_DEFAULT
	V.styles[M.STYLE_DEFAULT].font = nil
	V.styles[M.STYLE_DEFAULT].size = nil
	V:set_styles()
	V.extra_ascent = M.padding
	V.extra_descent = M.padding
	V.height = V:text_height(1)
	Vw = V.width
	setup_buffer()
	-- TODO: add event handler for tab switch so we can't switch buffers
end
	
-- Hijack the ui metatable so that writes to the builtin statusbar
-- also update the replacement, for compatibility with existing
-- modules
M.replace_statusbar = function()
	M.statusbar = ""
	M.statusbar.align = M.LEFT
	M.buffer_statusbar = ""
	M.buffer_statusbar.align = M.RIGHT
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
	setmetatable(ui, new_meta)
end

local function indexof(t, value)
	for i, v in ipairs(t, value) do
		if v == value then return i end
	end
	for i, v in pairs(t, value) do
		if v == value then return i end
	end
	return nil
end

-- TODO: Support mixed alignments where "center" fields are like
-- separators in between left and right aligned fields.
-- While I plan to support mixed alignments in the future, for now
-- this function will fix up the alignments of the fields to prevent
-- undesired behavior.
local function fix_alignment()
	sets = {M.LEFT, "", M.CENTER, M.RIGHT}
	current_set = 1
	for i, v in ipairs(fields) do
		if indexof(sets, v.align) > current_set then
			current_set = indexof(sets, v.align)
		else
			v.align = sets[current_set]
		end
	end
end

local function new_field()
	if not (B and V) then -- the view must be initialized first!
		error("setup_view must be called first")
	end
--	local styled_text = {{text = '', style = M.STYLE_DEFAULT}}
	local text = ""
	local style = M.STYLE_DEFAULT
	local align = M.CENTER
	local width = 0
	local fixed_width = 0
	local start, current = 0, 0
	
	-- TODO: text can be a string, or a sequence of tables where each table has attributes
	-- "text" and "style". If a string, then the 
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
		else
			rawset(t, key, value)
		end
	end
	field_meta.__tostring = get_plain
	field_meta.__name = "field"
	local new_field = {}
	setmetatable(new_field, field_meta)
	return new_field
end

M.add_field = function(key, alias)
	local pos = type(key) ~= "number" and #fields + 1 or key
	table.insert(fields, pos, new_field())
	if key ~= pos or alias then
		alias = alias or key
		fields[alias] = fields[pos]
		fields[pos].alias = alias
	end
	fields[pos].index = pos
	M.update()
end

M.delete_field = function(key)
	local attrib = type(key) == "string" and "index" or "alias"
	fields[fields[key][attrib]] = nil
	fields[key] = nil
	M.update()
end

local status_meta = {}
status_meta.__index = function (t, key)
	return fields[key]
end
status_meta.__len = function (t, key)
	return #fields
end
status_meta.__newindex = function (t, key, value)
	if not fields[key] then M.add_field(key) end
	fields[key].text = value
end
status_meta.__call = function(func, ...)
	return M.setup_view(...)
end
setmetatable(M, status_meta)

return M
