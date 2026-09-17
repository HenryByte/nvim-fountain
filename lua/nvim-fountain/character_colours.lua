-- nvim-fountain character colours module
-- Highlights each character's cue and dialogue lines in a distinct colour,
-- so it's easy to tell who's speaking at a glance.
local M = {}

M.namespace = vim.api.nvim_create_namespace("nvim_fountain_character_colours")

-- Default colour palette, cycled through as new characters are found.
M.palette = {
	"#e6194b",
	"#3cb44b",
	"#4363d8",
	"#f58231",
	"#911eb4",
	"#46f0f0",
	"#f032e6",
	"#bfef45",
	"#fabed4",
	"#469990",
	"#dcbeff",
	"#9a6324",
	"#808000",
	"#ffd8b1",
	"#000075",
}

local function is_blank(line)
	return line == nil or line:match("^%s*$") ~= nil
end

local function is_scene_heading(line)
	return line:match("^%s*%.%S") ~= nil
		or line:match("^%s*[IiEe][NnXx][TtEe]%.?[%s/]") ~= nil
		or line:match("^%s*[Ii]/[Ee][%.%s]") ~= nil
end

local function is_transition(line)
	return line:match("^%s*[%u][%u%s]* TO:%s*$") ~= nil or line:match("^%s*>") ~= nil
end

local function strip_extension(line)
	return vim.trim((line:gsub("%(.-%)%s*$", "")))
end

-- Strip a trailing extension like "(V.O.)" or "(CONT'D)" and a leading
-- forced-character "@" marker, so e.g. "MOM (V.O.)" and "MOM (CONT'D)" both
-- map back to the same character (and colour).
local function extract_name(line)
	local name = vim.trim(line):gsub("^@", "")
	return strip_extension(name)
end

local function is_character_cue(lines, idx)
	local line = lines[idx]
	if is_blank(line) then
		return false
	end
	if not is_blank(lines[idx - 1]) then
		return false
	end
	if is_blank(lines[idx + 1]) then
		return false
	end
	if is_scene_heading(line) or is_transition(line) then
		return false
	end

	local forced = line:match("^%s*@") ~= nil
	local name_part = strip_extension(line)
	if name_part == "" then
		return false
	end

	if not forced then
		if not name_part:match("%a") then
			return false -- no letters at all
		end
		if name_part ~= name_part:upper() then
			return false -- contains lowercase letters
		end
	end

	return true
end

-- Find character cue lines in a buffer.
-- Returns a list of { idx = <1-based line number>, name = <character name> }
-- and the buffer's lines (both reused by M.apply).
function M.find_characters(bufnr)
	local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
	local cues = {}
	for i = 1, #lines do
		if is_character_cue(lines, i) then
			table.insert(cues, { idx = i, name = extract_name(lines[i]) })
		end
	end
	return cues, lines
end

-- Map each distinct character name to a colour, in the order that name
-- first appears among `cues`. This is a pure function of the cue list, so
-- reopening an unmodified file always reproduces the same mapping, and with
-- up to `#palette` characters every one of them gets a distinct colour.
local function assign_colours(cues, palette)
	local colour_by_name = {}
	local count = 0
	for _, cue in ipairs(cues) do
		if not colour_by_name[cue.name] then
			colour_by_name[cue.name] = palette[(count % #palette) + 1]
			count = count + 1
		end
	end
	return colour_by_name
end

local function group_name_for(name)
	return "FountainCharacter_" .. name:gsub("%W", "_")
end

-- (Re)compute character colours for a buffer and paint the cue/dialogue
-- lines. Safe to call repeatedly (e.g. on every buffer change).
function M.apply(bufnr, opts)
	opts = opts or {}
	bufnr = bufnr or vim.api.nvim_get_current_buf()
	if not vim.api.nvim_buf_is_valid(bufnr) then
		return
	end

	local palette = opts.palette or M.palette
	local highlight_dialogue = opts.highlight_dialogue
	if highlight_dialogue == nil then
		highlight_dialogue = true
	end

	vim.api.nvim_buf_clear_namespace(bufnr, M.namespace, 0, -1)

	local cues, lines = M.find_characters(bufnr)
	local colour_by_name = assign_colours(cues, palette)
	for _, cue in ipairs(cues) do
		local colour = colour_by_name[cue.name]
		local group = group_name_for(cue.name)
		vim.api.nvim_set_hl(0, group, { fg = colour, default = true })

		vim.api.nvim_buf_add_highlight(bufnr, M.namespace, group, cue.idx - 1, 0, -1)

		if highlight_dialogue then
			local j = cue.idx + 1
			while j <= #lines and not is_blank(lines[j]) do
				vim.api.nvim_buf_add_highlight(bufnr, M.namespace, group, j - 1, 0, -1)
				j = j + 1
			end
		end
	end
end

local scheduled = {}

local function schedule_apply(bufnr, opts)
	if scheduled[bufnr] then
		return
	end
	scheduled[bufnr] = true
	vim.defer_fn(function()
		scheduled[bufnr] = nil
		if vim.api.nvim_buf_is_valid(bufnr) then
			M.apply(bufnr, opts)
		end
	end, 200)
end

-- Remove highlights and stop auto-refreshing for a buffer.
function M.disable(bufnr)
	bufnr = bufnr or vim.api.nvim_get_current_buf()
	vim.api.nvim_buf_clear_namespace(bufnr, M.namespace, 0, -1)
	pcall(vim.api.nvim_del_augroup_by_name, "nvim_fountain_character_colours_" .. bufnr)
end

-- Enable per-character colours for a buffer and keep them refreshed as the
-- buffer changes.
function M.setup(bufnr, opts)
	bufnr = bufnr or vim.api.nvim_get_current_buf()
	opts = opts or {}
	if opts.enabled == false then
		return
	end

	M.apply(bufnr, opts)

	local augroup = vim.api.nvim_create_augroup("nvim_fountain_character_colours_" .. bufnr, { clear = true })
	vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI", "BufWritePost" }, {
		buffer = bufnr,
		group = augroup,
		callback = function()
			schedule_apply(bufnr, opts)
		end,
	})
end

-- Toggle character colours on/off for a buffer.
function M.toggle(bufnr, opts)
	bufnr = bufnr or vim.api.nvim_get_current_buf()
	local marks = vim.api.nvim_buf_get_extmarks(bufnr, M.namespace, 0, -1, {})
	if #marks > 0 then
		M.disable(bufnr)
	else
		M.setup(bufnr, opts)
	end
end

return M
