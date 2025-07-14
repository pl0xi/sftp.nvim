local M = {}

local core = require("sftp.core")

function M.diff_remote_file()
  local config = core.load_config()
  local local_file = vim.api.nvim_buf_get_name(0)
  if local_file == "" then
    print("No file open in current buffer.")
    return
  end

  local temp_file = vim.fn.tempname()
  local relative_file = string.sub(local_file, #config.sftp_server.local_path + 2)
  local remote_file = config.sftp_server.remote_path .. "/" .. relative_file

  local sftp_command = string.format("sftp %s@%s:%s %s", config.sftp_server.user, config.sftp_server.host, remote_file, temp_file)

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
  sftp_server = {
    host = "your_sftp_host",
    user = "your_sftp_user",
    remote_path = "/path/to/your/remote/project/root",
    local_path = vim.fn.getcwd() -- Defaults to the current working directory
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