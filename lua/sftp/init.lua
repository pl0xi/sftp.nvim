local M = {}

local commands = require("sftp.commands")
local discrepancy = require("sftp.discrepancy")

local has_been_setup = false
local autocmd_group = nil

--- Setup the SFTP plugin with optional user configuration
--- @param opts table|nil Optional configuration overrides
function M.setup(opts)
  if has_been_setup then
    return
  end

  -- Apply user configuration if provided
  if opts then
    local config = require("sftp.config")

    -- Merge discrepancy_check options
    if opts.discrepancy_check then
      for k, v in pairs(opts.discrepancy_check) do
        config.discrepancy_check[k] = v
      end
    end

    -- Merge servers if provided
    if opts.servers then
      for k, v in pairs(opts.servers) do
        config.servers[k] = v
      end
    end
  end

  -- Create commands
  vim.api.nvim_create_user_command("SFTPDiff", commands.diff_remote_file, { nargs = "?" })
  vim.api.nvim_create_user_command("SFTPUpload", commands.upload_remote_file, { nargs = "?" })
  vim.api.nvim_create_user_command("SFTPDownload", commands.download_and_replace_file, { nargs = "?" })
  vim.api.nvim_create_user_command("SFTPInit", commands.init_config, {})

  -- Set up autocmd for discrepancy checking on file open
  M._setup_discrepancy_autocmd()

  has_been_setup = true
end

--- Set up the autocmd for automatic discrepancy checking
function M._setup_discrepancy_autocmd()
  autocmd_group = vim.api.nvim_create_augroup("SFTPDiscrepancyCheck", { clear = true })

  vim.api.nvim_create_autocmd("BufReadPost", {
    group = autocmd_group,
    pattern = "*",
    callback = function(args)
      local bufnr = args.buf
      -- Only check regular files (skip special buffers, directories, etc.)
      local buftype = vim.api.nvim_buf_get_option(bufnr, "buftype")
      if buftype ~= "" then
        return
      end

      discrepancy.check_file(bufnr)
    end,
    desc = "Check for file discrepancies with remote server",
  })

  -- Clear checked status when buffer is deleted
  vim.api.nvim_create_autocmd("BufDelete", {
    group = autocmd_group,
    pattern = "*",
    callback = function(args)
      discrepancy.clear_checked(args.buf)
    end,
    desc = "Clear discrepancy check status on buffer delete",
  })
end

return M