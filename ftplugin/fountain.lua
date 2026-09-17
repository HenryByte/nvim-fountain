-- Fountain filetype plugin
local keymaps = require('nvim-fountain.keymaps')
local character_colours = require('nvim-fountain.character_colours')
local config = require('nvim-fountain').config

-- Set up buffer-local options
vim.bo.commentstring = "/* %s */"

-- Set up keymaps
keymaps.setup(config)

-- Set up per-character dialogue colours
character_colours.setup(0, config.character_colours)

-- Set up any buffer-local commands
vim.api.nvim_buf_create_user_command(0, "FountainFormat", function()
  -- Add formatting functionality here
  vim.notify("Formatting fountain document", vim.log.levels.INFO)
end, { desc = "Format fountain document" })
