local M = {}

local commands = require("sftp.commands")
local log = require("sftp.log")

local has_been_setup = false

function M.setup(opts)
  -- plugin/sftp.lua calls setup() with no options on load, which can happen before
  -- or after the user's call, so options apply on every call that passes them.
  if opts and opts.log then
    log.setup(opts.log)
  end

  if has_been_setup then
    return
  end

  vim.api.nvim_create_user_command("SFTPDiff", commands.diff_remote_file, { nargs = "?" })
  vim.api.nvim_create_user_command("SFTPUpload", commands.upload_remote_file, { nargs = "?" })
  vim.api.nvim_create_user_command("SFTPDownload", commands.download_and_replace_file, { nargs = "?" })
  vim.api.nvim_create_user_command("SFTPInit", commands.init_config, {})
  vim.api.nvim_create_user_command("SFTPLog", commands.open_log, {})

  has_been_setup = true
end

return M
