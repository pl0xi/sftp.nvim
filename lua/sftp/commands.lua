local M = {}

local core = require("sftp.core")
local log = require("sftp.log")

-- Use vim.uv (Neovim 0.10+) or vim.loop (older versions)
local uv = vim.uv or vim.loop

-- Helper function to run sftp command using libuv spawn (bypasses shell entirely)
local function run_sftp_command(sftp_args, on_success, on_error)
  local stderr_chunks = {}
  local stdout_chunks = {}

  local stdout = uv.new_pipe(false)
  local stderr = uv.new_pipe(false)

  local handle, pid
  handle, pid = uv.spawn("sftp", {
    args = sftp_args,
    stdio = { nil, stdout, stderr },
  }, function(exit_code, signal)
    -- Close handles
    stdout:close()
    stderr:close()
    if handle then
      handle:close()
    end

    local stderr_output = table.concat(stderr_chunks, "")

    vim.schedule(function()
      if exit_code == 0 then
        on_success()
      else
        on_error(exit_code, stderr_output)
      end
    end)
  end)

  if not handle then
    -- Failed to spawn - pid contains error message
    vim.schedule(function()
      on_error(-1, "Failed to spawn sftp: " .. tostring(pid))
    end)
    return false
  end

  -- Read stderr
  stderr:read_start(function(err, data)
    if data then
      table.insert(stderr_chunks, data)
    end
  end)

  -- Read stdout (not used but prevents blocking)
  stdout:read_start(function(err, data)
    if data then
      table.insert(stdout_chunks, data)
    end
  end)

  return true
end

function M.diff_remote_file(args)
  local alias = (args and args.fargs and args.fargs[1]) or "default"
  local config = core.load_config()

  local server_config = config.servers[alias]
  if not server_config then
    log.error("SFTP configuration for alias '" .. alias .. "' not found.")
    return
  end

  if not server_config.remote_path then
    log.error("Configuration for alias '" .. alias .. "' is missing 'remote_path'.")
    return
  end

  if not server_config.local_path then
    log.error("Configuration for alias '" .. alias .. "' is missing 'local_path'.")
    return
  end

  local local_file = vim.api.nvim_buf_get_name(0)
  if local_file == "" then
    log.error("No file open in current buffer.")
    return
  end

  -- Prepare paths
  local downloaded_temp_file = vim.fn.tempname()

  -- Resolve local_path to an absolute path, assuming it's relative to cwd if not absolute
  local absolute_local_path = vim.fn.fnamemodify(server_config.local_path, ":p")

  -- Normalize path separators to forward slashes for consistency
  local normalized_local_file = string.gsub(local_file, "[\\/]+", "/")
  local normalized_local_path = string.gsub(absolute_local_path, "[\\/]+", "/")

  -- Ensure local_path is a prefix and calculate relative path
  local relative_file
  -- Use string.find to check for the prefix. The 'plain' argument (true) avoids magic chars.
  if string.find(normalized_local_file, normalized_local_path, 1, true) == 1 then
    relative_file = string.sub(normalized_local_file, #normalized_local_path + 1)
    -- remove leading slash if present
    if string.sub(relative_file, 1, 1) == "/" then
      relative_file = string.sub(relative_file, 2)
    end
  else
    log.error("The current file is not inside the configured 'local_path'.")
    log.error("File path: " .. local_file)
    log.error("Configured local_path: " .. server_config.local_path)
    log.error("Resolved absolute local_path: " .. absolute_local_path)
    return
  end

  -- Construct remote path, ensuring no double slashes
  local remote_file
  if string.sub(server_config.remote_path, -1) == "/" then
    remote_file = server_config.remote_path .. relative_file
  else
    remote_file = server_config.remote_path .. "/" .. relative_file
  end

  -- Create a batch file for sftp
  local batch_temp_file = vim.fn.tempname()
  -- sftp's 'get' command might prefer forward slashes for the local path too
  local normalized_download_path = string.gsub(downloaded_temp_file, "\\", "/")
  local batch_content = string.format('get "%s" "%s"', remote_file, normalized_download_path)

  local f, err = io.open(batch_temp_file, "w")
  if not f then
    log.error("Failed to create sftp batch file: " .. tostring(err))
    return
  end
  f:write(batch_content)
  f:close()

  -- Construct the sftp target
  local sftp_target
  if server_config.target then
    sftp_target = server_config.target
  elseif server_config.host and server_config.user then
    sftp_target = string.format("%s@%s", server_config.user, server_config.host)
  else
    log.error("Invalid SFTP configuration for alias '" .. alias .. "'. Provide either 'target' or both 'host' and 'user'.")
    os.remove(batch_temp_file) -- cleanup
    return
  end

  -- Execute the command using libuv spawn (bypasses shell entirely)
  local sftp_args = { "-b", batch_temp_file, sftp_target }

  local success = run_sftp_command(sftp_args,
    function() -- on_success
      os.remove(batch_temp_file)
      vim.cmd("diffsplit " .. downloaded_temp_file)
      vim.defer_fn(function()
        os.remove(downloaded_temp_file)
      end, 1000)
    end,
    function(exit_code, stderr_output) -- on_error
      os.remove(batch_temp_file)
      local error_message = "Error downloading remote file."
      if stderr_output and stderr_output ~= "" then
        error_message = error_message .. " SFTP output:\n" .. stderr_output
      else
        error_message = error_message .. " Check your SFTP configuration and if the file exists on the remote server. Exit code: " .. tostring(exit_code)
      end
      log.error(error_message)
      os.remove(downloaded_temp_file)
    end
  )

  if not success then
    os.remove(batch_temp_file)
  end
end


function M.upload_remote_file(args)
  local alias = (args and args.fargs and args.fargs[1]) or "default"
  local config = core.load_config()

  local server_config = config.servers[alias]
  if not server_config then
    log.error("SFTP configuration for alias '" .. alias .. "' not found.")
    return
  end

  if not server_config.remote_path then
    log.error("Configuration for alias '" .. alias .. "' is missing 'remote_path'.")
    return
  end

  if not server_config.local_path then
    log.error("Configuration for alias '" .. alias .. "' is missing 'local_path'.")
    return
  end

  local local_file = vim.api.nvim_buf_get_name(0)
  if local_file == "" then
    log.error("No file open in current buffer.")
    return
  end

  -- Resolve local_path to an absolute path, assuming it's relative to cwd if not absolute
  local absolute_local_path = vim.fn.fnamemodify(server_config.local_path, ":p")

  -- Normalize path separators to forward slashes for consistency
  local normalized_local_file = string.gsub(local_file, "[\\/]+", "/")
  local normalized_local_path = string.gsub(absolute_local_path, "[\\/]+", "/")

  -- Ensure local_path is a prefix and calculate relative path
  local relative_file
  if string.find(normalized_local_file, normalized_local_path, 1, true) == 1 then
    relative_file = string.sub(normalized_local_file, #normalized_local_path + 1)
    -- remove leading slash if present
    if string.sub(relative_file, 1, 1) == "/" then
      relative_file = string.sub(relative_file, 2)
    end
  else
    log.error("The current file is not inside the configured 'local_path'.")
    log.error("File path: " .. local_file)
    log.error("Configured local_path: " .. server_config.local_path)
    log.error("Resolved absolute local_path: " .. absolute_local_path)
    return
  end

  -- Construct remote path, ensuring no double slashes
  local remote_file
  if string.sub(server_config.remote_path, -1) == "/" then
    remote_file = server_config.remote_path .. relative_file
  else
    remote_file = server_config.remote_path .. "/" .. relative_file
  end

  -- Create a batch file for sftp
  local batch_temp_file = vim.fn.tempname()
  -- sftp client might prefer forward slashes for the local path
  local normalized_local_file_for_sftp = string.gsub(local_file, "\\", "/")
  local batch_content = string.format('put "%s" "%s"', normalized_local_file_for_sftp, remote_file)

  local f, err = io.open(batch_temp_file, "w")
  if not f then
    log.error("Failed to create sftp batch file: " .. tostring(err))
    return
  end
  f:write(batch_content)
  f:close()

  -- Construct the sftp target
  local sftp_target
  if server_config.target then
    sftp_target = server_config.target
  elseif server_config.host and server_config.user then
    sftp_target = string.format("%s@%s", server_config.user, server_config.host)
  else
    log.error("Invalid SFTP configuration for alias '" .. alias .. "'. Provide either 'target' or both 'host' and 'user'.")
    os.remove(batch_temp_file) -- cleanup
    return
  end

  -- Execute the command using libuv spawn (bypasses shell entirely)
  local sftp_args = { "-b", batch_temp_file, sftp_target }

  local success = run_sftp_command(sftp_args,
    function() -- on_success
      os.remove(batch_temp_file)
      log.info("File uploaded successfully to: " .. remote_file)
    end,
    function(exit_code, stderr_output) -- on_error
      os.remove(batch_temp_file)
      local error_message = "Error uploading remote file."
      if stderr_output and stderr_output ~= "" then
        error_message = error_message .. " SFTP output:\n" .. stderr_output
      else
        error_message = error_message .. " Check your SFTP configuration and permissions. Exit code: " .. tostring(exit_code)
      end
      log.error(error_message)
    end
  )

  if not success then
    os.remove(batch_temp_file)
  end
end

function M.download_and_replace_file(args)
  local alias = (args and args.fargs and args.fargs[1]) or "default"
  local config = core.load_config()

  local server_config = config.servers[alias]
  if not server_config then
    log.error("SFTP configuration for alias '" .. alias .. "' not found.")
    return
  end

  if not server_config.remote_path then
    log.error("Configuration for alias '" .. alias .. "' is missing 'remote_path'.")
    return
  end

  if not server_config.local_path then
    log.error("Configuration for alias '" .. alias .. "' is missing 'local_path'.")
    return
  end

  local local_file = vim.api.nvim_buf_get_name(0)
  if local_file == "" then
    log.error("No file open in current buffer.")
    return
  end

  -- Prepare paths
  local downloaded_temp_file = vim.fn.tempname()

  -- Resolve local_path to an absolute path, assuming it's relative to cwd if not absolute
  local absolute_local_path = vim.fn.fnamemodify(server_config.local_path, ":p")

  -- Normalize path separators to forward slashes for consistency
  local normalized_local_file = string.gsub(local_file, "[\\/]+", "/")
  local normalized_local_path = string.gsub(absolute_local_path, "[\\/]+", "/")

  -- Ensure local_path is a prefix and calculate relative path
  local relative_file
  -- Use string.find to check for the prefix. The 'plain' argument (true) avoids magic chars.
  if string.find(normalized_local_file, normalized_local_path, 1, true) == 1 then
    relative_file = string.sub(normalized_local_file, #normalized_local_path + 1)
    -- remove leading slash if present
    if string.sub(relative_file, 1, 1) == "/" then
      relative_file = string.sub(relative_file, 2)
    end
  else
    log.error("The current file is not inside the configured 'local_path'.")
    log.error("File path: " .. local_file)
    log.error("Configured local_path: " .. server_config.local_path)
    log.error("Resolved absolute local_path: " .. absolute_local_path)
    return
  end

  -- Construct remote path, ensuring no double slashes
  local remote_file
  if string.sub(server_config.remote_path, -1) == "/" then
    remote_file = server_config.remote_path .. relative_file
  else
    remote_file = server_config.remote_path .. "/" .. relative_file
  end

  -- Create a batch file for sftp
  local batch_temp_file = vim.fn.tempname()
  -- sftp's 'get' command might prefer forward slashes for the local path too
  local normalized_download_path = string.gsub(downloaded_temp_file, "\\", "/")
  local batch_content = string.format('get "%s" "%s"', remote_file, normalized_download_path)

  local f, err = io.open(batch_temp_file, "w")
  if not f then
    log.error("Failed to create sftp batch file: " .. tostring(err))
    return
  end
  f:write(batch_content)
  f:close()

  -- Construct the sftp target
  local sftp_target
  if server_config.target then
    sftp_target = server_config.target
  elseif server_config.host and server_config.user then
    sftp_target = string.format("%s@%s", server_config.user, server_config.host)
  else
    log.error("Invalid SFTP configuration for alias '" .. alias .. "'. Provide either 'target' or both 'host' and 'user'.")
    os.remove(batch_temp_file) -- cleanup
    return
  end

  -- Execute the command using libuv spawn (bypasses shell entirely)
  local sftp_args = { "-b", batch_temp_file, sftp_target }

  local success = run_sftp_command(sftp_args,
    function() -- on_success
      os.remove(batch_temp_file)
      -- Read the downloaded file content
      local downloaded_content = {}
      local file = io.open(downloaded_temp_file, "r")
      if file then
        for line in file:lines() do
          table.insert(downloaded_content, line)
        end
        file:close()

        -- Replace current buffer content with downloaded content
        vim.api.nvim_buf_set_lines(0, 0, -1, false, downloaded_content)
        -- Mark buffer as modified
        vim.api.nvim_buf_set_option(0, "modified", true)

        log.info("File content replaced with remote version from: " .. remote_file)
      else
        log.error("Failed to read downloaded file: " .. downloaded_temp_file)
      end

      -- Clean up temp file
      os.remove(downloaded_temp_file)
    end,
    function(exit_code, stderr_output) -- on_error
      os.remove(batch_temp_file)
      local error_message = "Error downloading remote file."
      if stderr_output and stderr_output ~= "" then
        error_message = error_message .. " SFTP output:\n" .. stderr_output
      else
        error_message = error_message .. " Check your SFTP configuration and if the file exists on the remote server. Exit code: " .. tostring(exit_code)
      end
      log.error(error_message)
      os.remove(downloaded_temp_file)
    end
  )

  if not success then
    os.remove(batch_temp_file)
  end
end

function M.init_config()
  local sftp_dir = vim.fn.getcwd() .. "/.sftp"
  if vim.fn.isdirectory(sftp_dir) == 0 then
    local ok, err = pcall(vim.fn.mkdir, sftp_dir)
    if not ok then
      log.error("Failed to create directory " .. sftp_dir .. ": " .. tostring(err))
      return
    end
  end

  local config_path = sftp_dir .. "/config.lua"
  if vim.fn.filereadable(config_path) == 1 then
    log.info("SFTP config file already exists.")
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

  local f, err = io.open(config_path, "w")
  if f then
    f:write(config_template)
    f:close()
    log.info("SFTP config file created at: " .. config_path)
  else
    log.error("Error creating SFTP config file " .. config_path .. ": " .. tostring(err))
  end
end

return M
