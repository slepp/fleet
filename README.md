# fleet

Run one command across a named set of SSH hosts. Parallel runs show live output
in labelled tmux panes. Serial runs use the invoking terminal by default. The
remote hosts need SSH access, not Ansible or Python.

## Requirements

The launcher runs on Linux with Bash 4 or newer, GNU coreutils and OpenSSH.
Parallel runs and visual serial runs also need tmux. `--gui` needs X and xterm.
The tmux view has been tested with tmux 3.6.

## Install

From this checkout, link the executable from a directory on `PATH`:

```sh
mkdir -p ~/.local/bin
ln -s "$(pwd)/fleet" ~/.local/bin/fleet
```

The launcher follows the link to find its host sets. Ensure `~/.local/bin` is
on your `PATH`, or run `./fleet` from this directory.

## Host sets

Each file in `sets/` named `SET.hosts` defines one set. Put one SSH hostname or
alias per line; blank lines and lines beginning with `#` are ignored. Connection
users, ports, keys and jump hosts belong in `~/.ssh/config`. Normal SSH host key
checking still applies.

The included sets are `proxmox`, `k3s-control` and `k3s`. To add a personal set
without tracking it in Git, create a file such as `sets/lab.local.hosts`:

```text
# One SSH alias per line
server1
server2
admin@server3
```

```sh
fleet --list
fleet --show lab.local
```

Keep credentials out of host set files. Review the resolved host list with
`--show` before a maintenance command.

## Run commands

Pass the remote shell command as one quoted argument. `--` separates it from
launcher options and preserves shell operators such as `&&`, pipes and
redirections:

```sh
fleet k3s-control -- 'sudo apt-get update && sudo apt-get dist-upgrade -y && sync'
fleet proxmox -- 'pveversion'
```

Parallel mode starts all hosts at once, with four panes per tmux window by
default. `--panes N` sets one to eight panes per window. Completed panes close
after 10 seconds; running panes from later windows move into the available
space. Change the delay with `--linger 0s`, `--linger 30s` or
`--linger forever`. A zoomed window keeps its layout until it is unzoomed; a
later pane retirement can then fill its gaps.

Serial mode runs hosts in the order listed in the set and stops on the first
failure. `--pace` waits after one host finishes before starting the next. The
command exits with the failed host's status, or zero if all hosts succeed:

```sh
fleet k3s --serial --pace 30s 'sudo apt-get dist-upgrade -y'
```

Serial mode uses the console unless `--tui`, `--gui` or `--detach` requests a
tmux view. `--panes` and `--linger` apply to visual runs. Keep remote work in
the foreground if later hosts must wait for it. SSH allocates a terminal so
password and sudo prompts can appear in the active console or pane.

## Tmux controls

`Ctrl-b n` moves to the next window, `Ctrl-b z` zooms a pane, and `Ctrl-b d`
detaches without stopping work. The launcher prints a reattach command.
`--gui` opens the same tiled view in an xterm window. Closing xterm only
detaches it.

With a finite linger, the tmux session closes after the last pane retires.
With `--linger forever`, press `Ctrl-b :`, type `kill-session`, and press Enter
to close it. A visual run's launcher exit status reports whether the view was
created; inspect individual panes for remote command results before they
close. Killing a pane or session during a command can interrupt SSH while
remote work continues.

## Tests and contributions

Run these checks before submitting a change:

```sh
bash -n fleet tests/run.sh
shellcheck fleet tests/run.sh
bash tests/run.sh
```

The behavioural suite replaces SSH with a local fake and uses an isolated tmux
server. It never connects to the included hosts. Add tests for changes to
command execution, ordering or pane lifetime.

## Licence

MIT © 2026 Stephen Olesen. See [LICENSE](LICENSE).
