local M = {}

local word_count_at_save = {}
local word_count_at_open = {}

function M.setup(opts)
	opts = opts or {}
	local keymaps = opts.keymaps or {}

	-- Set default keybinds if not provided
	local word_count_key = keymaps.word_count or "<Leader>wc"
	local diff_open_key = keymaps.diff_open or "<Leader>do"
	local diff_save_key = keymaps.diff_save or "<Leader>ds"
	vim.api.nvim_create_autocmd("BufRead", {
		group = vim.api.nvim_create_augroup("WordCountOpen", { clear = true }),
		callback = function(args)
			local buf = args.buf
			word_count_at_open[buf] = M.get_raw_word_count()
		end,
	})

	vim.api.nvim_create_autocmd("BufWritePost", {
		group = vim.api.nvim_create_augroup("WordCountSave", { clear = true }),
		callback = function(args)
			local buf = args.buf
			word_count_at_save[buf] = M.get_raw_word_count()
		end,
	})

	vim.api.nvim_create_user_command("WordCountCopy", function()
		M.copy_to_clipboard()
	end, { desc = "Copy current word count to clipboard" })

	vim.api.nvim_create_user_command("WordCountCopyDiffOpen", function()
		M.copy_diff_to_clipboard("open")
	end, { desc = "Copy word count diff from open to clipboard" })

	vim.api.nvim_create_user_command("WordCountCopyDiffSave", function()
		M.copy_diff_to_clipboard("save")
	end, { desc = "Copy word count diff from last save to clipboard" })
	if word_count_key then
		vim.keymap.set("n", word_count_key, "<cmd>WordCountCopy<cr>", { desc = "Copy word count to clipboard" })
	end

	if diff_open_key then
		vim.keymap.set(
			"n",
			diff_open_key,
			"<cmd>WordCountCopyDiffOpen<cr>",
			{ desc = "Copy word count diff from open" }
		)
	end

	if diff_save_key then
		vim.keymap.set(
			"n",
			diff_save_key,
			"<cmd>WordCountCopyDiffSave<cr>",
			{ desc = "Copy word count diff from save" }
		)
	end
end

function M.get_raw_word_count()
	local wc = vim.fn.wordcount()
	return wc.words or 0
end

function M.copy_to_clipboard()
	local count = M.get_raw_word_count()
	local text = tostring(count)

	-- Copy to system clipboard
	vim.fn.setreg("+", text)
	vim.fn.setreg('"', text)

	vim.notify("Word count copied to clipboard: " .. text)
	return text
end

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

	vim.fn.setreg("+", tostring(diff))
	vim.fn.setreg('"', tostring(diff))

	vim.notify("Word count diff copied to clipboard: " .. text)
	return diff
end

return M
