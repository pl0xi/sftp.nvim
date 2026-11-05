# sftp.nvim

A Neovim plugin for syncing files with remote servers.

## Disclaimer

This plugin was primarily developed with the assistance of an AI and was originally created for personal use. While it has been tested, there may be unforeseen bugs or limitations. Please use it with caution and feel free to contribute any improvements!

Tested on Windows and Linux (bash).

## Features

- **File Diffing**: Compare local files with their remote counterparts using `diffsplit`.
- **File Uploading**: Upload local files to the remote server.
- **File Downloading**: Download remote files and replace the current file content.
- **Project-Specific Configuration**: Easily configure settings on a per-project basis.
- **Simple Initialization**: Get started quickly with a single command.
- **Logging**: Clear messages through `vim.notify`, plus a persistent log file for diagnosing failures.

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
- `:SFTPDownload [alias]`: Downloads the remote version of the current file and replaces the local content. If no `alias` is provided, it uses the `default` configuration.
- `:SFTPInit`: Creates a `.sftp/config.lua` file in your project's root with a configuration template.
- `:SFTPLog`: Opens the log file in a split.

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

### Trusting a project config

`.sftp/config.lua` is Lua code, so a config in a cloned repository could run anything. The plugin loads it through Neovim's `vim.secure.read`, the same mechanism as `'exrc'`:

- The first time a command uses a config, and again whenever the file changes, Neovim asks whether to trust it. Choosing `allow` remembers the file's hash; you can also run `:trust` with the file open.
- If you don't allow it, the command stops with no servers configured.
- Tab completion never prompts. It offers aliases only after a command has loaded that exact version of the file in the current session.

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

## Logging

Messages appear through `vim.notify` and are also written to a log file, so you can look into a failure after the notification is gone.

- **Location**: `sftp.log` in `stdpath("log")`. Run `:SFTPLog` to open it in a split.
- **Size**: when the file reaches `max_size` it is moved to `sftp.log.1`, replacing any earlier backup.
- **Recorded at `info`**: the operation, alias, target, local and remote paths, exit code, signal and duration of each transfer, plus every message shown as a notification.
- **Recorded at `debug`**: the `sftp` arguments, its stdout, and its stderr on successful runs.

The log contains hostnames, usernames and file paths, but never the full server configuration. On Linux and macOS a newly created log file is readable only by you. Check the contents before sharing it, for example in a bug report.

Logging is a per-user setting, so it goes in `setup()` instead of `.sftp/config.lua`:

```lua
require("sftp").setup({
  log = {
    level = "info",        -- "debug", "info", "warn", "error" or "off"
    max_size = 1024 * 1024, -- bytes
  },
})
```

`level` only affects the file. Notifications always appear for `info` and above. If the log can't be written, the plugin warns once and carries on without file logging for the rest of the session.

Run `:checkhealth sftp` to check that `sftp` is on your `PATH` and the log file is writable.

A single message is cut to fit `max_size`, and control characters are written as visible escapes such as `\x1b`, so server output can't fake log lines or affect your terminal.

## Security

Paths containing control characters, including newlines, are refused, because they could run commands through the `sftp` batch file.

## Requirements

Neovim 0.9 or newer.
