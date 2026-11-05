local M = {}

function M.check()
  -- The report_* names are the pre-0.10 API.
  local health = vim.health
  local start = health.start or health.report_start
  local ok = health.ok or health.report_ok
  local warn = health.warn or health.report_warn
  local error = health.error or health.report_error
  local info = health.info or health.report_info

  start("sftp.nvim")

  if vim.fn.executable("sftp") == 1 then
    ok("sftp executable found: " .. vim.fn.exepath("sftp"))
  else
    error("sftp executable not found on PATH")
  end

  local status = require("sftp.log").status()
  info("Log file: " .. status.path)
  info("Log level: " .. status.level)
  info("Rotates at: " .. status.max_size .. " bytes")

  if not status.writable then
    error("Log file is not writable: " .. tostring(status.error))
  elseif status.disabled then
    warn("File logging was disabled this session after a write failed")
  else
    ok("Log file is writable")
  end
end

return M
