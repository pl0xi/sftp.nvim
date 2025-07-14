# sftp.nvim

Syncing files with remote servers.

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

## Features

- Compare local files with their remote counterparts using `diffsplit`.
- Project-specific configuration for easy setup.
- Simple initialization command to get started quickly.

## Commands

- `:SFTPDiff` - Opens a diff view between the local file and the remote file.
- `:SFTPInit` - Creates a `.sftp/config.lua` file in your project's root with a configuration template.

## Configuration

To configure the plugin, you can create a `.sftp/config.lua` file in your project's root. You can create this file manually or by running the `:SFTPInit` command.

The configuration file should return a Lua table with a `servers` table, where each entry is a named server configuration. The default configuration is under the alias `default`.

Each server configuration can either use an SSH `target` (alias) or direct `host` and `user` credentials. If `target` is provided, it will be prioritized.

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

If you use the `target` field, it corresponds to an alias in your SSH configuration file (`~/.ssh/config`). This allows you to use your SSH aliases to connect to the remote server, which is a more secure and convenient approach.

Here's an example of how you might configure your SSH alias:

```
Host your_ssh_alias
  HostName your_sftp_host
  User your_sftp_user
  IdentityFile ~/.ssh/your_private_key
```

### Aliases

You can define multiple server configurations, or "aliases", in your configuration file. To use a specific alias, you can pass it as an argument to the `:SFTPDiff` command:

```
:SFTPDiff staging
```

If you don't provide an alias, the `default` configuration will be used.

### `local_path`

The `local_path` option allows you to specify a subdirectory of your project to sync with the remote server. For example, if your project has a `Backend` and `Frontend` directory, but you only want to sync the `Backend` directory, you can set `local_path` to the full path of the `Backend` directory.

When you edit a file, the plugin will calculate the path of the file relative to the `local_path` and use that to construct the remote path. For example, if your `local_path` is set to `/path/to/your/project/Backend` and you edit the file `/path/to/your/project/Backend/api/user.php`, the plugin will look for the file `api/user.php` in the `remote_path` on the SFTP server.
