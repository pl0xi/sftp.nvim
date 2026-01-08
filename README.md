# sftp.nvim

A Neovim plugin for syncing files with remote servers.

## Disclaimer

This plugin was primarily developed with the assistance of an AI and was originally created for personal use. While it has been tested, there may be unforeseen bugs or limitations. Please use it with caution and feel free to contribute any improvements!
Only tested on Windows

## Features

- **File Diffing**: Compare local files with their remote counterparts using `diffsplit`.
- **File Uploading**: Upload local files to the remote server.
- **File Downloading**: Download remote files and replace the current file content.
- **Automatic Discrepancy Detection**: Automatically check for differences between local and remote files when opening a file.
- **Project-Specific Configuration**: Easily configure settings on a per-project basis.
- **Simple Initialization**: Get started quickly with a single command.
- **Enhanced Error Logging**: Clear, informative error messages using `vim.notify`.

## Installation

Install with `lazy.nvim`:

```lua
{
  "your-username/sftp.nvim",
  config = function()
    require("sftp").setup({
      -- Optional: Enable automatic discrepancy detection
      discrepancy_check = {
        enabled = true,     -- Enable automatic checking on file open
        server = "default", -- Server alias to use for checking
        delay = 500,        -- Delay in ms before fetching remote file
      }
    })
  end
}
```

## Commands

- `:SFTPDiff [alias]`: Opens a diff view between the local file and the remote file. If no `alias` is provided, it uses the `default` configuration.
- `:SFTPUpload [alias]`: Uploads the current file to the remote server. If no `alias` is provided, it uses the `default` configuration.
- `:SFTPDownload [alias]`: Downloads the remote version of the current file and replaces the local content. If no `alias` is provided, it uses the `default` configuration.
- `:SFTPInit`: Creates a `.sftp/config.lua` file in your project's root with a configuration template.

## Configuration

Create a `.sftp/config.lua` file in your project's root to configure the plugin. You can create this file manually or by running the `:SFTPInit` command.

The configuration file should return a Lua table with a `servers` table. Each entry in the `servers` table is a named server configuration (e.g., `default`, `staging`).

Each server configuration can use either an SSH `target` (alias) or direct `host` and `user` credentials. Using `target` is recommended for better security and convenience.

```lua
return {
  servers = {
    default = {
      -- Option 1: Using an SSH alias (recommended)
      target = "your_ssh_alias",
      -- Option 2: Using direct host and user
      -- host = "your_sftp_host",
      -- user = "your_sftp_user",
      remote_path = "/path/to/your/remote/project/root",
      local_path = vim.fn.getcwd() -- Defaults to the current working directory
    },
    staging = {
      target = "staging_ssh_alias",
      remote_path = "/path/to/your/staging/root",
      local_path = vim.fn.getcwd()
    }
  }
}
```

### SSH Configuration

The `target` field corresponds to an alias in your SSH configuration file (`~/.ssh/config`). This allows you to leverage your existing SSH configurations for secure connections.

Example `~/.ssh/config` entry:
```
Host your_ssh_alias
  HostName your_sftp_host
  User your_sftp_user
  IdentityFile ~/.ssh/your_private_key
```

### Aliases

You can define multiple server configurations (aliases) in your `config.lua`. To use a specific alias, pass it as an argument to the `:SFTPDiff`, `:SFTPUpload`, or `:SFTPDownload` command:

```
:SFTPDiff staging
:SFTPUpload staging
:SFTPDownload staging
```

If no alias is provided, the `default` configuration is used.

### `local_path`

The `local_path` option specifies the local project directory to be synced with the remote server. When you edit a file, the plugin calculates its path relative to `local_path` to determine the corresponding remote path.

For example, if `local_path` is `/path/to/project/src` and you edit `/path/to/project/src/api/main.go`, the plugin will sync it with `api/main.go` inside the `remote_path` on the server.

### Automatic Discrepancy Detection

The plugin can automatically check for differences between local and remote files when you open a file. This is useful for detecting when the remote file has been modified by someone else.

To enable this feature, add a `discrepancy_check` section to your configuration:

```lua
return {
  servers = {
    default = {
      target = "your_ssh_alias",
      remote_path = "/path/to/your/remote/project/root",
      local_path = vim.fn.getcwd()
    }
  },
  discrepancy_check = {
    enabled = true,     -- Enable automatic checking on file open
    server = "default", -- Server alias to use for checking
    delay = 500,        -- Delay in milliseconds before fetching remote file
  }
}
```

#### Configuration Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `enabled` | boolean | `false` | Enable or disable automatic discrepancy checking |
| `server` | string | `"default"` | Server alias to use for remote file comparison |
| `delay` | number | `500` | Delay in milliseconds before fetching the remote file |

When a discrepancy is detected, you'll see a warning notification suggesting to use `:SftpDiff` to view the differences.

You can also configure this in your `setup()` call:

```lua
require("sftp").setup({
  discrepancy_check = {
    enabled = true,
    server = "production",
    delay = 1000,
  }
})
```

## Error Logging

The plugin uses `vim.notify` to provide clear and non-intrusive feedback. Errors, such as configuration issues or connection failures, are displayed as notifications, ensuring they are visible without disrupting your workflow.
