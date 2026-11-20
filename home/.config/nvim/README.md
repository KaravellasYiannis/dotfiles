# 💤 LazyVim

A starter template for [LazyVim](https://github.com/LazyVim/LazyVim).
Refer to the [documentation](https://lazyvim.github.io/installation) to get started.

## Workspaces

From Windows Neovim or Neovide, use **Ctrl+B, f** or **:Workspace** to open the
picker. Each row shows a status marker, a platform icon, and the native path.
◉ marks the current workspace, ● a running server, and ○ a stopped server.
Running editors opened separately with `nvim` have an orange dot.
Select one to attach to its existing buffers and jobs. Discovery uses Neovim's
default named pipes on Windows and sockets on Linux, including running WSL
distros. Use `:connect` for custom listener addresses the frontend can reach.
Use **Ctrl+B, Shift+L** to return to the previous workspace and **Ctrl+X** in
the picker to stop a server started by the picker.

`:WorkspaceStopAll` checks for unsaved changes before closing workspace servers.
`:WorkspaceStopAll!` force-terminates your Neovim processes, including editors
opened outside the picker. Unsaved changes can be lost. From Windows or a
Windows-managed WSL workspace, it covers the Windows account and the default
user in each running WSL distro. On native Linux, it covers the current user.

Put one parent directory per line in `workspace-roots` in the Neovim config
directory. The picker lists the immediate, non-hidden project directories under
each root. The example below includes a Windows root and a WSL root.

~~~text
C:\Users\you\projects
\\wsl.localhost\Ubuntu\home\you\projects
~~~

Both `\\wsl.localhost` and `\\wsl$` shares are accepted. To open a project directly,
pass its directory to `:Workspace`. Spaces in the path can be entered as-is.

Use Neovim 0.12 or newer on both sides and a Neovide build that supports
`:connect`. WSL projects use the distro's own Neovim and config. The connection
uses [WSL localhost forwarding](https://learn.microsoft.com/windows/wsl/networking)
and WSL interop to reach the Windows frontend and switch back.
