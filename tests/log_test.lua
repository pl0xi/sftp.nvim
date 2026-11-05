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
  '  capture) cp "$2" "$BATCH_COPY"; exit 0 ;;',
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
vim.fn.mkdir(vim.fn.stdpath("state"), "p") -- vim.secure.trust keeps its database here
assert(vim.secure.trust({ action = "allow", path = project .. "/.sftp/config.lua" }))
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

function tests.control_chars_are_escaped()
  log.error("real\rFORGED [INFO] ok\27[2J\7\0 \194\155 caf\195\169\ttab")
  local content = read_log()
  assert(not content:find("[%z\1-\8\11-\31\127]"), content)
  assert(not content:find("\194\155", 1, true), content)
  assert(contains(content, "real\\x0dFORGED"), content)
  assert(contains(content, "\\x1b[2J\\x07\\x00 \\x9b"), content)
  assert(contains(content, "caf\195\169\ttab"), "must keep UTF-8 and tabs: " .. content)
end

function tests.oversized_message_fits_max_size()
  log.setup({ max_size = 1000 })
  log.error(string.rep("x", 5000000))
  local content = read_log()
  assert(#content <= 1000, "file is " .. #content .. " bytes")
  assert(contains(content, "[truncated]"), content)
  assert(contains(content, "xxxx"), content)
end

function tests.existing_log_and_backup_become_private()
  vim.fn.mkdir(vim.fn.fnamemodify(log.path(), ":h"), "p")
  vim.fn.writefile({ string.rep("a", 200) }, log.path())
  vim.fn.setfperm(log.path(), "rw-r--r--")
  log.info("tighten")
  assert(vim.fn.getfperm(log.path()) == "rw-------", vim.fn.getfperm(log.path()))

  vim.fn.setfperm(log.path(), "rw-r--r--")
  log.setup({ max_size = 100 })
  log.info("rotate")
  assert(vim.fn.getfperm(log.path() .. ".1") == "rw-------", vim.fn.getfperm(log.path() .. ".1"))
end

function tests.uncreatable_log_directory_does_not_raise()
  local blocker = sandbox .. "/blocker"
  vim.fn.writefile({}, blocker)
  local state_home = vim.env.XDG_STATE_HOME
  vim.env.XDG_STATE_HOME = blocker
  local ok, err = pcall(function()
    log.info("still-notified")
    assert(notified("still-notified"))
    assert(notified("file logging disabled"))
    assert(log.status().writable == false)
  end)
  vim.env.XDG_STATE_HOME = state_home
  assert(ok, err)
end

-- Stubs mkdir because a real blocked state directory would also hide the trust database.
function tests.log_failure_does_not_break_an_upload()
  local real_mkdir = vim.fn.mkdir
  vim.fn.mkdir = function()
    error("Vim:E739: Cannot create directory")
  end
  local ok, err = pcall(function()
    vim.env.STUB_MODE = "ok"
    commands.upload_remote_file({ fargs = {} })
    assert(vim.wait(5000, function()
      return notified("File uploaded successfully")
    end, 10), "the upload's success path did not run")
    assert(notified("file logging disabled"))
  end)
  vim.fn.mkdir = real_mkdir
  assert(ok, err)
end

-- Opens a file with the given name in the project and uploads it, returning the batch file text.
local function upload_captured(filename)
  local batch_copy = sandbox .. "/batch-copy"
  os.remove(batch_copy)
  vim.env.BATCH_COPY = batch_copy
  vim.fn.writefile({ "x" }, project .. "/" .. filename)
  vim.cmd("edit " .. vim.fn.fnameescape(project .. "/" .. filename))
  upload("capture")
  vim.cmd("edit file.txt")
  os.remove(project .. "/" .. filename)
  local f = io.open(batch_copy, "r")
  if not f then
    return nil
  end
  local content = f:read("*a")
  f:close()
  return content
end

function tests.batch_paths_are_escaped()
  local batch = upload_captured('we"ird*name?.txt')
  assert(batch, "sftp did not run")
  assert(contains(batch, 'we\\"ird*name?.txt" "/remote/we\\"ird*name?.txt"'), batch)
end

function tests.line_breaks_in_paths_are_refused()
  local filename = 'a"\n!touch PWNED\n"b'
  vim.fn.writefile({ "x" }, project .. "/" .. filename)
  local buf = vim.api.nvim_create_buf(true, false)
  vim.api.nvim_buf_set_name(buf, project .. "/" .. filename)
  vim.api.nvim_set_current_buf(buf)
  local batch_copy = sandbox .. "/batch-copy"
  os.remove(batch_copy)
  vim.env.BATCH_COPY = batch_copy
  upload("capture")
  vim.cmd("edit file.txt")
  vim.api.nvim_buf_delete(buf, { force = true })
  os.remove(project .. "/" .. filename)
  assert(notified("Refusing to transfer"))
  vim.wait(200)
  assert(vim.fn.filereadable(batch_copy) == 0, "sftp must not run")
end

-- Makes a project whose config leaves a marker file when it runs, then enters it.
-- Returns the marker path and the config path. The caller must leave via `leave_project`.
local function hostile_project(name)
  local dir = sandbox .. "/" .. name
  vim.fn.mkdir(dir .. "/.sftp", "p")
  local marker = dir .. "/RAN"
  local config = dir .. "/.sftp/config.lua"
  vim.fn.writefile({
    "vim.fn.writefile({ 'x' }, '" .. marker .. "')",
    "return { servers = { " .. name .. " = { target = 't', remote_path = '/r', local_path = '" .. dir .. "' } } }",
  }, config)
  vim.cmd("cd " .. vim.fn.fnameescape(dir))
  return marker, config
end

local function leave_project()
  vim.cmd("cd " .. vim.fn.fnameescape(project))
end

local core = require("sftp.core")

function tests.completion_does_not_run_an_unapproved_config()
  local marker = hostile_project("completion_project")
  local completions = vim.fn.getcompletion("SftpUpload ", "cmdline")
  leave_project()
  assert(vim.fn.filereadable(marker) == 0, "config ran during tab completion")
  assert(#completions == 0, vim.inspect(completions))
end

function tests.ignored_prompt_does_not_run_the_config()
  local marker = hostile_project("ignored_project")
  local real_confirm = vim.fn.confirm
  local prompted = false
  vim.fn.confirm = function()
    prompted = true
    return 1 -- "ignore"
  end
  local config = core.load_config()
  vim.fn.confirm = real_confirm
  leave_project()
  assert(prompted, "expected a trust prompt")
  assert(vim.fn.filereadable(marker) == 0, "untrusted config ran")
  assert(next(config.servers) == nil, vim.inspect(config.servers))
  assert(notified("not trusted"))
end

function tests.denied_config_does_not_run()
  local marker, path = hostile_project("denied_project")
  assert(vim.secure.trust({ action = "deny", path = path }))
  local config = core.load_config()
  leave_project()
  assert(vim.fn.filereadable(marker) == 0, "denied config ran")
  assert(next(config.servers) == nil, vim.inspect(config.servers))
end

function tests.denied_project_does_not_inherit_earlier_servers()
  assert(core.load_config().servers.default.target == "test-host")
  local _, path = hostile_project("stale_project")
  assert(vim.secure.trust({ action = "deny", path = path }))
  local config = core.load_config()
  leave_project()
  assert(config.servers.default == nil, "kept servers from the previous project")
end

function tests.trusted_config_loads_and_then_completes()
  local marker, path = hostile_project("trusted_project")
  assert(vim.secure.trust({ action = "allow", path = path }))

  local before = vim.fn.getcompletion("SftpUpload ", "cmdline")
  assert(#before == 0, "completion must wait for a command to load the config")

  local config = core.load_config()
  assert(vim.fn.filereadable(marker) == 1, "trusted config did not run")
  assert(config.servers.trusted_project, vim.inspect(config.servers))

  local after = vim.fn.getcompletion("SftpUpload ", "cmdline")
  assert(vim.deep_equal(after, { "trusted_project" }), vim.inspect(after))

  -- An edit invalidates the approval for completion.
  os.remove(marker)
  vim.fn.writefile({ "vim.fn.writefile({ 'x' }, '" .. marker .. "')", "return { servers = {} }" }, path)
  local changed = vim.fn.getcompletion("SftpUpload ", "cmdline")
  leave_project()
  assert(vim.fn.filereadable(marker) == 0, "edited config ran during tab completion")
  assert(#changed == 0, vim.inspect(changed))
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
