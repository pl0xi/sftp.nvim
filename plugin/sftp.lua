local commands = require("sftp.commands")

vim.api.nvim_create_user_command("SFTPInit", commands.init_config, {})