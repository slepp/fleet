# Fleet command view

Run one shell command on a named set of SSH hosts. Parallel runs show each
host in a separate live tmux pane; serial runs use the invoking terminal by
default.
It works with servers and SSH-capable routers; the remote hosts do not need
Ansible or Python. The local machine needs Bash and OpenSSH. Parallel runs
and visual serial runs also need tmux. `--gui` also needs X and xterm.

From this checkout, link the launcher from a directory on `PATH` to call it
as `fleet`:

```sh
mkdir -p ~/.local/bin
ln -s "$(pwd)/fleet" ~/.local/bin/fleet
```

The launcher resolves its path to find the host sets in this repository.

Create a host set at `sets/servers.hosts`:

```text
# SSH hostnames or aliases, one per line
server1
server2
admin@server3
```

Included sets are `proxmox`, `k3s-control` and `k3s`.
The host lists contain the SSH names provided for this fleet; review them
with `fleet --show SET` before running a command.

Then run:

```sh
fleet --list
fleet --show proxmox
fleet k3s-control -- 'sudo apt-get update && sudo apt-get dist-upgrade -y && sync'
fleet k3s --serial --pace 30s 'sudo apt-get dist-upgrade -y'
fleet k3s --serial --tui --pace 30s 'uptime'
fleet k3s --linger 30s -- 'uptime'
fleet k3s --linger forever -- 'uptime'
fleet --panes 2 proxmox -- 'pveversion'
fleet --gui k3s -- 'uptime'
```

The quoted command runs through each remote account's shell. Quote it once
locally to preserve pipes, redirects and `&&`. Use `sudo` in the command where
needed; SSH allocates a terminal so prompts can appear in the active console
or pane. Keep SSH users, ports, keys and jump hosts in `~/.ssh/config`, then
put those aliases in the host sets. Parallel mode starts all hosts at once
and groups up to four panes in each tmux window by default; `--panes N`
changes the layout, with up to eight panes per window. Completed panes remain
for 10 seconds, then close;
running panes from later windows move into the freed space. Use `--linger 30s`
for a different delay, `--linger 0s` to close immediately, or
`--linger forever` to retain completed panes until you close the session.
A zoomed window keeps its layout until you unzoom it; the next pane retirement
can then fill its gaps.

`--serial` runs hosts in list order in the current terminal and stops on the
first failure. `--pace 30s` waits 30 seconds after one host finishes before
starting the next; `m` and `h` are also accepted. The command's exit status
is the first failed host's status, or zero if all succeed. Add `--tui` for
the tiled tmux view, `--gui` for that view in xterm, or `--detach` to leave
it in a tmux session. `--panes N` and `--linger` apply only to a visual run.
In a visual serial run, a pane closed before it finishes does not release
the next host.
Serial mode waits for the SSH command to finish; keep work in the foreground
if later hosts must wait for it.

Tmux controls: `Ctrl-b n` moves to the next window, `Ctrl-b z` zooms a pane,
and `Ctrl-b d` detaches without stopping the commands. The launcher prints a
reattach command. `--detach` starts a session without opening it. Running
`--gui` opens an xterm window containing the same tiled tmux view. When the
work is done, press `Ctrl-b :`, type `kill-session`, and press Enter to close
the whole session. Closing the xterm window only detaches it.

For visual runs, the launcher's exit status reports whether it created the
view. Check completed panes during the linger period for remote command
results. With a finite linger, the session closes after its last pane retires.
Closing a pane or killing the tmux session may interrupt a running SSH
command; a remote command could continue after the connection ends.
