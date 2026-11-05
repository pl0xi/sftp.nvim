local M = {}

local uv = vim.uv or vim.loop

-- File thresholds. "off" is only a threshold, never a message level.
local LEVELS = { debug = 1, info = 2, warn = 3, error = 4, off = 5 }

local VIM_LEVELS = {
  debug = vim.log.levels.DEBUG,
  info = vim.log.levels.INFO,
  warn = vim.log.levels.WARN,
  error = vim.log.levels.ERROR,
}

local state = {
  level = "info",
  max_size = 1024 * 1024,
  -- Set after a write fails, so a broken log warns once rather than on every message.
  disabled = false,
}

-- Only call from the main loop: vim.fn is unavailable in fast contexts.
function M.path()
  return vim.fn.stdpath("log") .. "/sftp.log"
end

local function open_log()
  local path = M.path()
  vim.fn.mkdir(vim.fn.fnamemodify(path, ":h"), "p")
  return uv.fs_open(path, "a", 384) -- 384 is 0600: the log holds hosts and paths
end

local function rotate_if_needed(path, incoming_size)
  local stat = uv.fs_stat(path)
  if stat and stat.type == "file" and stat.size + incoming_size > state.max_size then
    local backup = path .. ".1"
    os.remove(backup) -- os.rename fails on Windows if the target exists
    os.rename(path, backup)
  end
end

local function format_line(level, message, timestamp)
  local text = tostring(message):gsub("\r\n", "\n"):gsub("%s+$", "")
  -- Indenting continuation lines stops multi-line output from forging log entries.
  text = text:gsub("\n", "\n    ")
  return string.format("%s [%s] %s\n", timestamp, level:upper(), text)
end

local function disable_file_logging(err)
  state.disabled = true
  vim.notify(
    "sftp.nvim: file logging disabled for this session: " .. tostring(err),
    vim.log.levels.WARN
  )
end

local function write_line(line)
  rotate_if_needed(M.path(), #line)

  local fd, open_err = open_log()
  if not fd then
    disable_file_logging(open_err)
    return
  end

  local written, write_err = uv.fs_write(fd, line)
  uv.fs_close(fd)
  if not written then
    disable_file_logging(write_err)
  end
end

local function dispatch(level, message, should_notify)
  -- Taken now, because a fast-context message is written later.
  local timestamp = os.date("%Y-%m-%dT%H:%M:%S%z")

  local function emit()
    if not state.disabled and LEVELS[level] >= LEVELS[state.level] then
      write_line(format_line(level, message, timestamp))
    end
    if should_notify then
      vim.notify(message, VIM_LEVELS[level])
    end
  end

  if vim.in_fast_event() then
    vim.schedule(emit)
  else
    emit()
  end
end

-- Merges into the current options, so a later call without an option keeps its value.
function M.setup(opts)
  opts = opts or {}

  if opts.level ~= nil then
    local level = type(opts.level) == "string" and opts.level:lower() or nil
    if level and LEVELS[level] then
      state.level = level
    else
      state.level = "info"
      vim.notify(
        "sftp.nvim: invalid log level '" .. tostring(opts.level) .. "', using 'info'.",
        vim.log.levels.WARN
      )
    end
  end

  if opts.max_size ~= nil then
    if type(opts.max_size) == "number" and opts.max_size > 0 then
      state.max_size = opts.max_size
    else
      vim.notify(
        "sftp.nvim: invalid log max_size '" .. tostring(opts.max_size) .. "', keeping "
          .. state.max_size .. ".",
        vim.log.levels.WARN
      )
    end
  end

  state.disabled = false
end

-- Reports the active settings and whether the log can be opened. For :checkhealth.
function M.status()
  local fd, err = open_log()
  if fd then
    uv.fs_close(fd)
  end
  return {
    path = M.path(),
    level = state.level,
    max_size = state.max_size,
    disabled = state.disabled,
    writable = fd ~= nil,
    error = err,
  }
end

-- Writes to the log file only, for detail that shouldn't interrupt the user.
function M.record(level, message)
  dispatch(level, message, false)
end

function M.debug(message)
  dispatch("debug", message, false)
end

function M.info(message)
  dispatch("info", message, true)
end

function M.warn(message)
  dispatch("warn", message, true)
end

function M.error(message)
  dispatch("error", message, true)
end

return M
