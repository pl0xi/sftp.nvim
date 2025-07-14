local M = {}

M.servers = {
  default = {
    target = "your_ssh_alias",
    remote_path = "/path/to/your/remote/project/root",
    local_path = vim.fn.getcwd()
  }
}

return M