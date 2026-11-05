local M = {}
local log = require("sftp.log")

-- Config path -> sha256 of the contents a command has loaded with the user's trust,
-- so completion can offer aliases without ever prompting.
local approved = {}

local function no_servers()
  local config = vim.deepcopy(require("sftp.config"))
  config.servers = {}
  return config
end

-- Returns the file's contents only if this exact version is already approved.
local function read_approved(path)
  local file = io.open(path, "rb")
  if not file then
    return nil
  end
  local contents = file:read("*a")
  file:close()
  if approved[path] == vim.fn.sha256(contents) then
    return contents
  end
  return nil
end

-- opts.prompt = false never asks about trust, and skips anything not yet approved.
function M.load_config(opts)
  local prompt = not (opts and opts.prompt == false)
  -- A copy, so one project's servers can't carry over into another project.
  local config = vim.deepcopy(require("sftp.config"))
  local project_config_path = vim.fn.getcwd() .. "/.sftp/config.lua"

  -- Check if the project-specific config file exists
  if vim.fn.filereadable(project_config_path) == 0 then
    return config
  end

  local contents
  if prompt then
    -- The file is code that may have arrived with a cloned repository.
    contents = vim.secure.read(project_config_path)
    if not contents then
      log.warn(
        "Project config is not trusted, so no servers are configured: " .. project_config_path
          .. "\nRun the command again to choose 'allow', or use :trust with the file open."
      )
      return no_servers()
    end
    approved[project_config_path] = vim.fn.sha256(contents)
  else
    contents = read_approved(project_config_path)
    if not contents then
      return no_servers()
    end
  end

  log.debug("Project-specific config found at: " .. project_config_path)
  local chunk, load_err = load(contents, "@" .. project_config_path)
  local ok, project_config_or_err = false, load_err
  if chunk then
    ok, project_config_or_err = pcall(chunk)
  end
  if not ok then
    log.error("Error loading project config file (" .. project_config_path .. "):\n" .. tostring(project_config_or_err))
    return no_servers()
  end
  if type(project_config_or_err) ~= "table" then
    log.error("Project config file must return a table: " .. project_config_path)
    return no_servers()
  end

  -- Merge the project config into the default config
  for k, v in pairs(project_config_or_err) do
    config[k] = v
  end

  return config
end

return M
