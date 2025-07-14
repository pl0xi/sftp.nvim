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

The configuration file should return a Lua table with the following structure:

```lua
return {
  sftp_server = {
    host = "your_sftp_host",
    user = "your_sftp_user",
    remote_path = "/path/to/your/remote/project/root",
    local_path = "/path/to/your/local/project/root" -- Optional: Defaults to the project root
  }
}
```

### `local_path`

The `local_path` option allows you to specify a subdirectory of your project to sync with the remote server. For example, if your project has a `Backend` and `Frontend` directory, but you only want to sync the `Backend` directory, you can set `local_path` to the full path of the `Backend` directory.

When you edit a file, the plugin will calculate the path of the file relative to the `local_path` and use that to construct the remote path. For example, if your `local_path` is set to `/path/to/your/project/Backend` and you edit the file `/path/to/your/project/Backend/api/user.php`, the plugin will look for the file `api/user.php` in the `remote_path` on the SFTP server.
