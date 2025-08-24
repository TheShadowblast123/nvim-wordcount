local M = {}

local config = {
	use_icons = false,
	position = "right", -- 'left' or 'right' of line/column info
	format = "%s words", -- %s will be replaced with the count
	icon = "", -- Nerd Font icon (pencil)
	toggle_key = nil, -- e.g., "<Leader>wc" to set a toggle key
	show_diff = false, -- Whether to show diff in statusline
}

-- State management
local enabled = false
local original_statusline = nil
local word_count_at_save = {}
local word_count_at_open = {}

-- Store the actual current window for statusline comparison
vim.g.actual_curwin = vim.api.nvim_get_current_win()

-- Update the actual current window on WinEnter
vim.api.nvim_create_autocmd("WinEnter", {
	callback = function()
		vim.g.actual_curwin = vim.api.nvim_get_current_win()
	end,
})

-- Setup function to handle configuration
function M.setup(user_config)
	config = vim.tbl_deep_extend("force", config, user_config or {})

	-- Store the original statusline
	original_statusline = vim.opt.statusline:get()

	-- Set up toggle key if specified
	if config.toggle_key then
		vim.keymap.set("n", config.toggle_key, M.toggle, { desc = "Toggle word count statusline" })
	end

	-- Set up commands
	vim.api.nvim_create_user_command("WordCountCopy", function()
		M.copy_to_clipboard()
	end, { desc = "Copy current word count to clipboard" })

	vim.api.nvim_create_user_command("WordCountCopyDiffOpen", function()
		M.copy_diff_to_clipboard("open")
	end, { desc = "Copy word count diff from open to clipboard" })

	vim.api.nvim_create_user_command("WordCountCopyDiffSave", function()
		M.copy_diff_to_clipboard("save")
	end, { desc = "Copy word count diff from last save to clipboard" })

	vim.api.nvim_create_user_command("WordCountToggleDiff", function()
		M.toggle_diff()
	end, { desc = "Toggle diff display in statusline" })

	-- Track word count at buffer open
	vim.api.nvim_create_autocmd("BufRead", {
		group = vim.api.nvim_create_augroup("WordCountOpen", { clear = true }),
		callback = function(args)
			local buf = args.buf
			word_count_at_open[buf] = M.get_raw_word_count()
		end,
	})

	-- Track word count at save
	vim.api.nvim_create_autocmd("BufWritePost", {
		group = vim.api.nvim_create_augroup("WordCountSave", { clear = true }),
		callback = function(args)
			local buf = args.buf
			word_count_at_save[buf] = M.get_raw_word_count()
		end,
	})
end

-- Get raw word count without formatting
function M.get_raw_word_count()
	local wc = vim.fn.wordcount()
	return wc.words or 0
end

-- Main function to get formatted word count
function M.get_word_count()
	local count = M.get_raw_word_count()

	if config.show_diff then
		local current_buf = vim.api.nvim_get_current_buf()
		local diff_save = count - (word_count_at_save[current_buf] or count)
		local diff_open = count - (word_count_at_open[current_buf] or count)

		if config.use_icons then
			return string.format("%s %d (Δs:%+d, Δo:%+d)", config.icon, count, diff_save, diff_open)
		else
			return string.format("%d words (save:%+d, open:%+d)", count, diff_save, diff_open)
		end
	else
		if config.use_icons then
			return string.format("%s %d", config.icon, count)
		else
			return string.format(config.format, count)
		end
	end
end

-- Get file size in a human-readable format
function M.get_file_size()
	local file = vim.fn.expand("%:p")
	if file == "" then
		return "0B"
	end

	local size = vim.fn.getfsize(file)
	if size <= 0 then
		return "0B"
	end

	local suffixes = { "B", "KB", "MB", "GB" }
	local i = 1
	while size > 1024 and i < #suffixes do
		size = size / 1024
		i = i + 1
	end

	return string.format("%.1f%s", size, suffixes[i])
end

-- Get current mode with icon if enabled
function M.get_mode()
	local mode = vim.fn.mode()
	local mode_map = {
		n = "NORMAL",
		i = "INSERT",
		v = "VISUAL",
		V = "V-LINE",
		[""] = "V-BLOCK",
		c = "COMMAND",
		t = "TERMINAL",
		R = "REPLACE",
	}

	local mode_icon_map = {
		n = "",
		i = "",
		v = "",
		V = "",
		[""] = "",
		c = "",
		t = "",
		R = "",
	}

	local mode_text = mode_map[mode] or mode
	if config.use_icons then
		return string.format("%s %s", mode_icon_map[mode] or "?", mode_text)
	else
		return mode_text
	end
end

-- Get file information (name and modified status)
function M.get_file_info()
	local file = vim.fn.expand("%:t")
	if file == "" then
		return "[No Name]"
	end

	local modified = vim.bo.modified and "+" or ""
	return file .. modified
end

-- Active statusline (for current window)
function M.active()
	local mode = M.get_mode()
	local file_info = M.get_file_info()
	local file_size = M.get_file_size()
	local word_count = M.get_word_count()

	-- Get current line and column information
	local line = vim.fn.line(".")
	local col = vim.fn.virtcol(".")
	local total_lines = vim.fn.line("$")

	-- Left section: mode, file info, file size
	local left = string.format("%%#StatusLine# %s %%#StatusLineNC# %s %%#StatusLine# %s ", mode, file_info, file_size)

	-- Right section: word count, line:column, percentage
	local right
	if config.position == "left" then
		right = string.format("%%#StatusLine# %s | %d:%d | %d/%d ", word_count, line, col, line, total_lines)
	else
		right = string.format("%%#StatusLine# %d:%d | %s | %d/%d ", line, col, word_count, line, total_lines)
	end

	-- Calculate available space for center section
	local width = vim.o.columns
	local left_width = vim.fn.strwidth(left:gsub("%%#%w+#", ""))
	local right_width = vim.fn.strwidth(right:gsub("%%#%w+#", ""))
	local available_space = math.max(0, width - left_width - right_width)

	-- Center section (file path)
	local center = string.format("%%#StatusLineNC# %s ", vim.fn.expand("%:p:~:."))
	local center_truncated = vim.fn.strcharpart(center, 0, available_space)

	return left .. center_truncated .. "%=" .. right
end

-- Inactive statusline (for non-current windows)
function M.inactive()
	local file_info = M.get_file_info()
	local file_size = M.get_file_size()

	return string.format("%%#StatusLineNC# %s %s ", file_info, file_size)
end

-- Statusline condition function (mimics mini.statusline behavior)
function M.statusline_condition()
	if vim.api.nvim_get_current_win() == vim.g.actual_curwin or vim.o.laststatus == 3 then
		return M.active()
	else
		return M.inactive()
	end
end

-- Toggle between word count statusline and original
function M.toggle()
	if enabled then
		-- Restore original statusline
		vim.opt.statusline = original_statusline
		enabled = false
		vim.notify("Word count statusline disabled")
	else
		-- Enable word count statusline
		vim.opt.statusline = "%!v:lua.require('nvim-wordcount').statusline_condition()"
		enabled = true
		vim.notify("Word count statusline enabled")
	end
end

-- Toggle diff display
function M.toggle_diff()
	config.show_diff = not config.show_diff
	if config.show_diff then
		vim.notify("Diff display enabled")
	else
		vim.notify("Diff display disabled")
	end

	-- Refresh statusline if enabled
	if enabled then
		vim.opt.statusline = "%!v:lua.require('statusline-word-count').statusline_condition()"
	end
end

-- Copy current word count to clipboard
function M.copy_to_clipboard()
	local count = M.get_raw_word_count()
	local text = tostring(count)

	-- Copy to system clipboard
	vim.fn.setreg("+", text)
	vim.fn.setreg('"', text)

	vim.notify("Word count copied to clipboard: " .. text)
	return text
end

-- Copy diff to clipboard
function M.copy_diff_to_clipboard(diff_type)
	local count = M.get_raw_word_count()
	local current_buf = vim.api.nvim_get_current_buf()
	local diff, text

	if diff_type == "save" then
		local saved = word_count_at_save[current_buf] or count
		diff = count - saved
		text = string.format("%+d (current: %d, saved: %d)", diff, count, saved)
	else -- 'open'
		local opened = word_count_at_open[current_buf] or count
		diff = count - opened
		text = string.format("%+d (current: %d, opened: %d)", diff, count, opened)
	end

	-- Copy to system clipboard
	vim.fn.setreg("+", tostring(diff))
	vim.fn.setreg('"', tostring(diff))

	vim.notify("Word count diff copied to clipboard: " .. text)
	return diff
end

-- Enable the statusline
function M.enable()
	if not enabled then
		M.toggle()
	end
end

-- Disable the statusline
function M.disable()
	if enabled then
		M.toggle()
	end
end

-- Set up autocommand to update statusline when text changes (only when enabled)
local group = vim.api.nvim_create_augroup("StatuslineWordCount", { clear = true })
vim.api.nvim_create_autocmd({ "InsertLeave", "TextChanged", "BufEnter" }, {
	group = group,
	callback = function()
		if enabled then
			vim.opt.statusline = "%!v:lua.require('statusline-word-count').statusline_condition()"
		end
	end,
})

return M
