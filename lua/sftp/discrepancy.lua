local M = {}

local core = require("sftp.core")
local log = require("sftp.log")

-- Track buffers that have already been checked to avoid duplicate checks
local checked_buffers = {}

--- Check if a file has discrepancies with its remote version
--- @param bufnr number Buffer number to check
--- @param config table Configuration table (optional, will load if not provided)
function M.check_file(bufnr, config)
  config = config or core.load_config()

  local discrepancy_config = config.discrepancy_check
  if not discrepancy_config or not discrepancy_config.enabled then
    return
  end

  local alias = discrepancy_config.server or "default"
  local server_config = config.servers[alias]

  if not server_config then
    -- Silently return if server not found (don't spam errors on every file open)
    return
  end

  if not server_config.remote_path or not server_config.local_path then
    return
  end

  local local_file = vim.api.nvim_buf_get_name(bufnr)
  if local_file == "" then
    return
  end

  -- Skip if already checked this buffer
  if checked_buffers[bufnr] then
    return
  end

  -- Resolve local_path to an absolute path
  local absolute_local_path = vim.fn.fnamemodify(server_config.local_path, ":p")

  -- Normalize path separators
  local normalized_local_file = string.gsub(local_file, "[\\/]+", "/")
  local normalized_local_path = string.gsub(absolute_local_path, "[\\/]+", "/")

  -- Check if file is within the configured local_path
  if string.find(normalized_local_file, normalized_local_path, 1, true) ~= 1 then
    -- File is not in the configured path, skip silently
    return
  end

  -- Calculate relative path
  local relative_file = string.sub(normalized_local_file, #normalized_local_path + 1)
  if string.sub(relative_file, 1, 1) == "/" then
    relative_file = string.sub(relative_file, 2)
  end

  -- Construct remote path
  local remote_file
  if string.sub(server_config.remote_path, -1) == "/" then
    remote_file = server_config.remote_path .. relative_file
  else
    remote_file = server_config.remote_path .. "/" .. relative_file
  end

  -- Mark as checked to prevent duplicate checks
  checked_buffers[bufnr] = true

  -- Apply delay before fetching
  local delay = discrepancy_config.delay or 500
  vim.defer_fn(function()
    -- Ensure buffer still exists and is valid
    if not vim.api.nvim_buf_is_valid(bufnr) then
      checked_buffers[bufnr] = nil
      return
    end

    M._fetch_and_compare(bufnr, server_config, local_file, remote_file, alias)
  end, delay)
end

--- Internal function to fetch remote file and compare
--- @param bufnr number Buffer number
--- @param server_config table Server configuration
--- @param local_file string Local file path
--- @param remote_file string Remote file path
--- @param alias string Server alias name
function M._fetch_and_compare(bufnr, server_config, local_file, remote_file, alias)
  local downloaded_temp_file = vim.fn.tempname()
  local batch_temp_file = vim.fn.tempname()

  -- Create batch file for sftp
  local normalized_download_path = string.gsub(downloaded_temp_file, "\\", "/")
  local batch_content = string.format('get "%s" "%s"', remote_file, normalized_download_path)

  local f, err = io.open(batch_temp_file, "w")
  if not f then
    return
  end
  f:write(batch_content)
  f:close()

  -- Determine sftp target
  local sftp_target
  if server_config.target then
    sftp_target = server_config.target
  elseif server_config.host and server_config.user then
    sftp_target = string.format("%s@%s", server_config.user, server_config.host)
  else
    os.remove(batch_temp_file)
    return
  end

  local sftp_command = string.format('sftp -b "%s" %s', batch_temp_file, sftp_target)

  -- Execute the command
  local job_id = vim.fn.jobstart(sftp_command, {
    on_exit = function(_, exit_code)
      -- Cleanup batch file
      os.remove(batch_temp_file)

      if exit_code == 0 then
        vim.schedule(function()
          M._compare_files(bufnr, local_file, downloaded_temp_file, remote_file, alias)
          os.remove(downloaded_temp_file)
        end)
      else
        -- Remote file doesn't exist or connection failed, silently ignore
        os.remove(downloaded_temp_file)
      end
    end,
  })

  if job_id == 0 or job_id == -1 then
    os.remove(batch_temp_file)
  end
end

--- Compare local buffer content with downloaded remote file
--- @param bufnr number Buffer number
--- @param local_file string Local file path
--- @param remote_temp_file string Path to downloaded remote file
--- @param remote_path string Remote file path (for display)
--- @param alias string Server alias name
function M._compare_files(bufnr, local_file, remote_temp_file, remote_path, alias)
  -- Ensure buffer is still valid
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end

  -- Read local buffer content
  local local_lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

  -- Read remote file content
  local remote_lines = {}
  local file = io.open(remote_temp_file, "r")
  if not file then
    return
  end

  for line in file:lines() do
    table.insert(remote_lines, line)
  end
  file:close()

  -- Compare the files
  local has_discrepancy = false

  if #local_lines ~= #remote_lines then
    has_discrepancy = true
  else
    for i, local_line in ipairs(local_lines) do
      if local_line ~= remote_lines[i] then
        has_discrepancy = true
        break
      end
    end
  end

  if has_discrepancy then
    local filename = vim.fn.fnamemodify(local_file, ":t")
    local message = string.format(
      "File discrepancy detected: '%s' differs from remote version on server '%s'. Use :SftpDiff %s to view differences.",
      filename,
      alias,
      alias
    )
    log.warn(message)
  end
end

--- Clear the checked status for a buffer (useful when reloading)
--- @param bufnr number Buffer number
function M.clear_checked(bufnr)
  checked_buffers[bufnr] = nil
end

--- Clear all checked buffers
function M.clear_all_checked()
  checked_buffers = {}
end

return M
