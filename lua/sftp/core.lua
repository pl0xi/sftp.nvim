local M = {}
local log = require("sftp.log")

function M.load_config()
  local default_config = require("sftp.config")
  local project_config_path = vim.fn.getcwd() .. "/.sftp/config.lua"

  -- Check if the project-specific config file exists
  if vim.fn.filereadable(project_config_path) == 1 then
    log.info("Project-specific config found at: " .. project_config_path)
    local ok, project_config_or_err = pcall(dofile, project_config_path)
    if not ok then
      log.error("Error loading project config file (" .. project_config_path .. "):\n" .. project_config_or_err)
      return default_config
    end

    local project_config = project_config_or_err
    -- Merge the project config into the default config
    for k, v in pairs(project_config) do
      default_config[k] = v
    end
  end

  return default_config
end

return M