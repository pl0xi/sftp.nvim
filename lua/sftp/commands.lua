local M = {}

local core = require("sftp.core")

function M.diff_remote_file(args)
  local alias = args.fargs[1] or "default"
  local config = core.load_config()

  local server_config = config.servers[alias]
  if not server_config then
    print("SFTP configuration for alias '" .. alias .. "' not found.")
    return
  end

  local local_file = vim.api.nvim_buf_get_name(0)
  if local_file == "" then
    print("No file open in current buffer.")
    return
  end

  local temp_file = vim.fn.tempname()
  local relative_file = string.sub(local_file, #server_config.local_path + 2)
  local remote_file = server_config.remote_path .. "/" .. relative_file

  local sftp_command
  if server_config.target then
    sftp_command = string.format("sftp %s:%s %s", server_config.target, remote_file, temp_file)
  elseif server_config.host and server_config.user then
    sftp_command = string.format("sftp %s@%s:%s %s", server_config.user, server_config.host, remote_file, temp_file)
  else
    print("Invalid SFTP configuration for alias '" .. alias .. "'. Provide either 'target' or both 'host' and 'user'.")
    return
  end

  local job_id = vim.fn.jobstart(sftp_command, {
    on_exit = function(_, exit_code)
      if exit_code == 0 then
        vim.schedule(function()
          vim.cmd("diffsplit " .. temp_file)
          vim.defer_fn(function()
            os.remove(temp_file)
          end, 1000)
        end)
      else
        print("Error downloading remote file. Check your SFTP configuration and if the file exists on the remote server.")
      end
    end,
  })

  if job_id == 0 or job_id == -1 then
    print("Failed to start SFTP download job.")
  end
end

function M.init_config()
  local sftp_dir = vim.fn.getcwd() .. "/.sftp"
  if vim.fn.isdirectory(sftp_dir) == 0 then
    vim.fn.mkdir(sftp_dir)
  end

  local config_path = sftp_dir .. "/config.lua"
  if vim.fn.filereadable(config_path) == 1 then
    print("SFTP config file already exists.")
    return
  end

  local config_template = [[return {
  servers = {
    default = {
      target = "your_ssh_alias",
      remote_path = "/path/to/your/remote/project/root",
      local_path = vim.fn.getcwd() -- Defaults to the current working directory
    }
  }
}
]]

  local f = io.open(config_path, "w")
  if f then
    f:write(config_template)
    f:close()
    print("SFTP config file created at: " .. config_path)
  else
    print("Error creating SFTP config file.")
  end
end

return M