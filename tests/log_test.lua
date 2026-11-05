-- Run from the repository root: nvim --headless -l tests/log_test.lua
-- Uses a throwaway state directory and a stub `sftp`, so it needs no server. POSIX only.

local uv = vim.uv or vim.loop

local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
vim.opt.rtp:prepend(root)

local sandbox = vim.fn.tempname()
vim.fn.mkdir(sandbox, "p")
vim.env.XDG_STATE_HOME = sandbox .. "/state"

-- Stub sftp: behaviour is chosen by STUB_MODE.
local bin_dir = sandbox .. "/bin"
vim.fn.mkdir(bin_dir, "p")
vim.fn.writefile({
  "#!/bin/sh",
  'case "$STUB_MODE" in',
  '  ok) echo "stub stdout"; echo "stub warning" >&2; exit 0 ;;',
  '  fail) echo "Connection closed" >&2; exit 255 ;;',
  '  big) head -c 300000 /dev/zero | tr "\\0" x >&2; exit 1 ;;',
  "  signal) kill -TERM $$; sleep 5 ;;",
  "esac",
}, bin_dir .. "/sftp")
vim.fn.setfperm(bin_dir .. "/sftp", "rwxr-xr-x")
local original_path = vim.env.PATH
vim.env.PATH = bin_dir .. ":" .. original_path

-- Project with a server config and an open file.
local project = sandbox .. "/project"
vim.fn.mkdir(project .. "/.sftp", "p")
vim.fn.writefile({
  "return { servers = { default = {",
  '  target = "test-host", remote_path = "/remote", local_path = "' .. project .. '",',
  "} } }",
}, project .. "/.sftp/config.lua")
vim.fn.writefile({ "hello" }, project .. "/file.txt")
vim.cmd("cd " .. vim.fn.fnameescape(project))
vim.cmd("edit file.txt")

local notifications = {}
vim.notify = function(message, level)
  table.insert(notifications, { message = message, level = level })
end

-- `nvim -l` skips plugins, so load the plugin file the way startup would.
dofile(root .. "/plugin/sftp.lua")

local log = require("sftp.log")
local commands = require("sftp.commands")

local function read_log()
  local f = io.open(log.path(), "r")
  if not f then
    return ""
  end
  local content = f:read("*a")
  f:close()
  return content
end

local function reset()
  notifications = {}
  os.remove(log.path())
  os.remove(log.path() .. ".1")
  log.setup({ level = "info", max_size = 1024 * 1024 })
end

local function contains(haystack, needle)
  return haystack:find(needle, 1, true) ~= nil
end

local function notified(needle)
  for _, n in ipairs(notifications) do
    if contains(n.message, needle) then
      return true
    end
  end
  return false
end

-- Runs the upload command against the stub and waits for the failure or success message.
local function upload(mode)
  vim.env.STUB_MODE = mode
  commands.upload_remote_file({ fargs = {} })
  assert(vim.wait(10000, function()
    return #notifications > 0
  end, 10), "upload produced no notification")
end

local tests = {}

function tests.levels_filter_the_file()
  log.setup({ level = "warn" })
  log.debug("debug-msg")
  log.info("info-msg")
  log.warn("warn-msg")
  log.error("error-msg")
  local content = read_log()
  assert(not contains(content, "debug-msg"))
  assert(not contains(content, "info-msg"))
  assert(contains(content, "[WARN] warn-msg"))
  assert(contains(content, "[ERROR] error-msg"))
end

function tests.level_off_writes_nothing_but_still_notifies()
  log.setup({ level = "off" })
  log.error("quiet")
  assert(read_log() == "")
  assert(notified("quiet"))
end

function tests.invalid_level_warns_and_falls_back()
  log.setup({ level = "loud" })
  assert(notified("invalid log level"))
  log.debug("hidden")
  log.info("shown")
  local content = read_log()
  assert(not contains(content, "hidden"))
  assert(contains(content, "shown"))
end

function tests.debug_and_record_do_not_notify()
  log.setup({ level = "debug" })
  log.debug("debug-only")
  log.record("error", "record-only")
  local content = read_log()
  assert(contains(content, "debug-only"))
  assert(contains(content, "record-only"))
  assert(#notifications == 0)
end

function tests.line_format_and_multiline_indent()
  log.info("first\nsecond\r\nthird\n")
  local content = read_log()
  assert(
    content:match("^%d%d%d%d%-%d%d%-%d%dT%d%d:%d%d:%d%d[+-]%d%d%d%d %[INFO%] first\n    second\n    third\n$"),
    "unexpected format: " .. content
  )
end

function tests.new_file_is_private()
  log.info("x")
  assert(vim.fn.getfperm(log.path()) == "rw-------", vim.fn.getfperm(log.path()))
end

function tests.rotation_keeps_one_backup()
  log.setup({ max_size = 100 })
  log.info(string.rep("a", 80))
  log.info(string.rep("b", 80))
  log.info(string.rep("c", 80))
  local backup = io.open(log.path() .. ".1", "r"):read("*a")
  assert(contains(backup, "bbb") and not contains(backup, "aaa"))
  local current = read_log()
  assert(contains(current, "ccc") and not contains(current, "bbb"))
end

function tests.unwritable_log_warns_once_and_does_not_raise()
  os.remove(log.path())
  vim.fn.mkdir(log.path(), "p") -- a directory can't be opened for appending
  log.info("one")
  log.info("two")
  local warnings = 0
  for _, n in ipairs(notifications) do
    if contains(n.message, "file logging disabled") then
      warnings = warnings + 1
    end
  end
  vim.fn.delete(log.path(), "d")
  assert(warnings == 1, "expected one warning, got " .. warnings)
  assert(notified("one") and notified("two"), "normal notifications must still appear")
end

function tests.fast_context_is_safe()
  local timer = uv.new_timer()
  local errored
  timer:start(1, 0, function()
    local ok, err = pcall(log.record, "warn", "from-fast")
    if not ok then
      errored = err
    end
    timer:close()
  end)
  assert(vim.wait(2000, function()
    return contains(read_log(), "from-fast") or errored ~= nil
  end, 10))
  assert(not errored, errored)
end

function tests.setup_options_apply_after_automatic_setup()
  require("sftp").setup({ log = { level = "debug" } })
  log.debug("after-setup")
  assert(contains(read_log(), "after-setup"))
  -- A later bare setup(), as plugin/sftp.lua does, must not reset the options.
  require("sftp").setup()
  log.debug("after-bare-setup")
  assert(contains(read_log(), "after-bare-setup"))
end

function tests.upload_success_is_logged()
  log.setup({ level = "debug" })
  upload("ok")
  local content = read_log()
  assert(contains(content, 'upload alias="default" target="test-host"'), content)
  assert(contains(content, "started args=-b"), content)
  assert(contains(content, "succeeded exit=0 signal=0"), content)
  assert(contains(content, "stub stdout"), content)
  assert(contains(content, "stub warning"), content)
  assert(contains(content, "File uploaded successfully"), content)
  assert(#notifications == 1, "the outcome line must not add a notification")
end

function tests.upload_failure_logs_stderr()
  upload("fail")
  local content = read_log()
  assert(contains(content, "failed exit=255 signal=0"), content)
  assert(contains(content, "Connection closed"), content)
  assert(notified("Connection closed"))
end

function tests.large_stderr_is_captured_in_full()
  upload("big")
  local longest = 0
  for run in read_log():gmatch("x+") do
    longest = math.max(longest, #run)
  end
  assert(longest == 300000, "captured " .. longest .. " of 300000 bytes")
end

function tests.killed_process_is_a_failure()
  upload("signal")
  local content = read_log()
  assert(contains(content, "signal=15"), content)
  assert(contains(content, "failed"), content)
  assert(not contains(content, "File uploaded successfully"), content)
  assert(notified("terminated by signal 15"))
end

function tests.missing_sftp_is_logged()
  vim.env.PATH = sandbox .. "/nonexistent"
  local ok, err = pcall(upload, "ok")
  vim.env.PATH = bin_dir .. ":" .. original_path
  assert(ok, err)
  local content = read_log()
  assert(contains(content, "failed to spawn"), content)
  assert(notified("Failed to spawn sftp"))
end

-- Runs in a fixed order so the output is stable.
local names = vim.tbl_keys(tests)
table.sort(names)

local failures = 0
for _, name in ipairs(names) do
  reset()
  local ok, err = pcall(tests[name])
  print((ok and "ok    " or "FAIL  ") .. name .. (ok and "" or ("\n      " .. tostring(err))))
  if not ok then
    failures = failures + 1
  end
end

vim.fn.delete(sandbox, "rf")
print(string.format("\n%d passed, %d failed", #names - failures, failures))
os.exit(failures == 0 and 0 or 1)
