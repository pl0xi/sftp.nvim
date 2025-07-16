# sftp.nvim

A Neovim plugin for syncing files with remote servers.

## Disclaimer

This plugin was primarily developed with the assistance of an AI and was originally created for personal use. While it has been tested, there may be unforeseen bugs or limitations. Please use it with caution and feel free to contribute any improvements!

## Features

- **File Diffing**: Compare local files with their remote counterparts using `diffsplit`.
- **File Uploading**: Upload local files to the remote server.
- **Project-Specific Configuration**: Easily configure settings on a per-project basis.
- **Simple Initialization**: Get started quickly with a single command.
- **Enhanced Error Logging**: Clear, informative error messages using `vim.notify`.

## Installation

Install with `lazy.nvim`:

```lua
{
  "your-username/sftp.nvim",
  config = function()
    require("sftp").setup()
  end
}
```

## Commands

- `:SFTPDiff [alias]`: Opens a diff view between the local file and the remote file. If no `alias` is provided, it uses the `default` configuration.
- `:SFTPUpload [alias]`: Uploads the current file to the remote server. If no `alias` is provided, it uses the `default` configuration.
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

You can define multiple server configurations (aliases) in your `config.lua`. To use a specific alias, pass it as an argument to the `:SFTPDiff` or `:SFTPUpload` command:

```
:SFTPDiff staging
```

If no alias is provided, the `default` configuration is used.

### `local_path`

The `local_path` option specifies the local project directory to be synced with the remote server. When you edit a file, the plugin calculates its path relative to `local_path` to determine the corresponding remote path.

For example, if `local_path` is `/path/to/project/src` and you edit `/path/to/project/src/api/main.go`, the plugin will sync it with `api/main.go` inside the `remote_path` on the server.

## Error Logging

The plugin uses `vim.notify` to provide clear and non-intrusive feedback. Errors, such as configuration issues or connection failures, are displayed as notifications, ensuring they are visible without disrupting your workflow.
