-- nvim-fountain export module
local M = {}

-- Default export configuration
local default_config = {
	output_dir = nil,
	-- Base directory for :FountainExportPDFDir (mirrors the source's path,
	-- relative to the cwd, underneath this directory)
	pdf_dir = "pdf",
	pdf = {
		options = "--overwrite",
		-- Builds the command (as a list, for vim.fn.system) used to export.
		-- Override this to use a different program (e.g. screenplain) with
		-- its own argument layout.
		command = function(current_file, output_path, options)
			local cmd = { "afterwriting", "--source", current_file, "--pdf", output_path }

			if options and options ~= "" then
				for option in string.gmatch(options, "%S+") do
					table.insert(cmd, option)
				end
			end

			return cmd
		end,
	},
}

-- Get export configuration
local function get_config()
	local config = require("nvim-fountain").config.export or {}
	return vim.tbl_deep_extend("force", default_config, config)
end

-- Save the buffer, run the configured export command, and report the result
local function run_export(config, current_file, output_path)
	vim.cmd("write")

	local output_dir = vim.fn.fnamemodify(output_path, ":h")
	if vim.fn.isdirectory(output_dir) == 0 then
		vim.fn.mkdir(output_dir, "p")
	end

	-- Build the command (overridable via config.export.pdf.command)
	local cmd = config.pdf.command(current_file, output_path, config.pdf.options)

	vim.notify("Running: " .. table.concat(cmd, " "), vim.log.levels.INFO)

	-- Use system() instead of jobstart for direct execution
	local result = vim.fn.system(cmd)

	if vim.v.shell_error == 0 then
		vim.notify("Successfully exported to " .. output_path, vim.log.levels.INFO)
	else
		vim.notify("Export failed: " .. result, vim.log.levels.ERROR)
	end
end

-- Export to PDF using afterwriting - direct system call approach
function M.export_pdf(output_path)
	local config = get_config()
	local current_file = vim.fn.expand("%:p")
	local filename = vim.fn.fnamemodify(current_file, ":t:r") .. ".pdf"

	-- Determine output path
	if not output_path then
		output_path = config.output_dir or vim.fn.expand("%:p:r") .. ".pdf"
	end

	-- If output_path is a directory, export into it using the source filename
	if vim.fn.isdirectory(output_path) == 1 then
		output_path = output_path:gsub("/+$", "") .. "/" .. filename
	end

	run_export(config, current_file, output_path)
end

-- Export to PDF underneath base_dir, mirroring the source file's path
-- relative to the cwd, e.g. dir1/dir2/file.fountain -> pdf/dir1/dir2/file.pdf
function M.export_pdf_dir(base_dir)
	local config = get_config()
	local current_file = vim.fn.expand("%:p")

	if not base_dir or base_dir == "" then
		base_dir = config.pdf_dir
	end

	local relative_path = vim.fn.fnamemodify(current_file, ":.")
	if relative_path:sub(1, 1) == "/" then
		-- fnamemodify couldn't make it relative (file is outside the cwd)
		vim.notify("File is outside the current directory, exporting by filename only", vim.log.levels.WARN)
		relative_path = vim.fn.fnamemodify(current_file, ":t")
	end

	local relative_pdf = vim.fn.fnamemodify(relative_path, ":r") .. ".pdf"
	local output_path = base_dir:gsub("/+$", "") .. "/" .. relative_pdf

	run_export(config, current_file, output_path)
end

return M
