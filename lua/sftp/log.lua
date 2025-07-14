local M = {}

function M.info(message)
  vim.notify(message, vim.log.levels.INFO)
end

function M.error(message)
  vim.notify(message, vim.log.levels.ERROR)
end

return M
