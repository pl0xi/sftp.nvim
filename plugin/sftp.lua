require("sftp").setup()

vim.api.nvim_create_user_command(
  "SftpDiff",
  function(args)
    require("sftp.commands").diff_remote_file(args)
  end,
  {
    nargs = "?",
    complete = function()
      -- Completion must never prompt, or run a config that hasn't been approved.
      local config = require("sftp.core").load_config({ prompt = false })
      local completions = {}
      for alias, _ in pairs(config.servers) do
        table.insert(completions, alias)
      end
      return completions
    end,
    desc = "Diff the current file with its remote version on the SFTP server.",
  }
)

vim.api.nvim_create_user_command(
  "SftpUpload",
  function(args)
    require("sftp.commands").upload_remote_file(args)
  end,
  {
    nargs = "?",
    complete = function()
      -- Completion must never prompt, or run a config that hasn't been approved.
      local config = require("sftp.core").load_config({ prompt = false })
      local completions = {}
      for alias, _ in pairs(config.servers) do
        table.insert(completions, alias)
      end
      return completions
    end,
    desc = "Upload the current file to its remote location on the SFTP server.",
  }
)

vim.api.nvim_create_user_command(
  "SftpDownload",
  function(args)
    require("sftp.commands").download_and_replace_file(args)
  end,
  {
    nargs = "?",
    complete = function()
      -- Completion must never prompt, or run a config that hasn't been approved.
      local config = require("sftp.core").load_config({ prompt = false })
      local completions = {}
      for alias, _ in pairs(config.servers) do
        table.insert(completions, alias)
      end
      return completions
    end,
    desc = "Download the remote version and replace the current file content.",
  }
)

vim.api.nvim_create_user_command(
  "SftpInitConfig",
  function()
    require("sftp.commands").init_config()
  end,
  {
    nargs = 0,
    desc = "Initialize a .sftp/config.lua file in the current directory.",
  }
)

vim.api.nvim_create_user_command(
  "SftpLog",
  function()
    require("sftp.commands").open_log()
  end,
  {
    nargs = 0,
    desc = "Open the sftp.nvim log file in a split.",
  }
)
