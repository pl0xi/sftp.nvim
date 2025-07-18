local M = {}

local commands = require("sftp.commands")

local has_been_setup = false

function M.setup()
  if has_been_setup then
    return
  end

  vim.api.nvim_create_user_command("SFTPDiff", commands.diff_remote_file, { nargs = "?" })
  vim.api.nvim_create_user_command("SFTPUpload", commands.upload_remote_file, { nargs = "?" })
  vim.api.nvim_create_user_command("SFTPDownload", commands.download_and_replace_file, { nargs = "?" })
  vim.api.nvim_create_user_command("SFTPInit", commands.init_config, {})

  has_been_setup = true
end

return M