local M = {}

M.servers = {
  default = {
    target = "your_ssh_alias",
    remote_path = "/path/to/your/remote/project/root",
    local_path = vim.fn.getcwd()
  }
}

-- Configuration for automatic file discrepancy checking
M.discrepancy_check = {
  enabled = false,              -- Enable/disable automatic discrepancy checking on file open
  server = "default",           -- Server alias to use for checking (must match a key in servers)
  delay = 500,                  -- Delay in milliseconds before fetching remote file
}

return M