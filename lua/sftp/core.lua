local M = {}

function M.load_config()
  local default_config = require("sftp.config")
  local project_config_path = vim.fn.getcwd() .. "/.sftp/config.lua"

  -- Check if the project-specific config file exists
  if vim.fn.filereadable(project_config_path) == 1 then
    local project_config = dofile(project_config_path)
    -- Merge the project config into the default config
    for k, v in pairs(project_config) do
      default_config[k] = v
    end
  end

  return default_config
end

return M