#!/usr/bin/env bash
set -euo pipefail

project_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
real_tmux=$(command -v tmux)
test_dir=$(mktemp -d)
sockets=()

cleanup() {
    local socket
    for socket in "${sockets[@]}"; do
        "$real_tmux" -L "$socket" kill-server >/dev/null 2>&1 || true
    done
    rm -rf -- "$test_dir"
}
trap cleanup EXIT

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

wait_for() {
    local description=$1 deadline
    shift
    deadline=$((SECONDS + 20))
    until "$@"; do
        (( SECONDS < deadline )) || fail "timed out waiting for $description"
        sleep 0.1
    done
}

new_run() {
    local name=$1
    export FLEET_TEST_SOCKET="fleet-test-$$-$RANDOM"
    export FLEET_TEST_STATE="$test_dir/state-$name"
    export FLEET_TEST_HOLD=1
    unset FLEET_TEST_FAIL_HOST
    unset FLEET_TEST_SLOW_SETUP
    mkdir "$FLEET_TEST_STATE"
    sockets+=("$FLEET_TEST_SOCKET")
}

launch() {
    local output
    output=$("$test_dir/fleet" "$@") || fail "fleet launch failed: $output"
    session=$(printf '%s\n' "$output" | sed -n '1s/^Starting .* session //p')
    [[ $session == fleet-* ]] || fail "missing session name: $output"
}

session_gone() {
    ! tmux has-session -t "$1" 2>/dev/null
}

pane_dead() {
    [[ $(tmux list-panes -t "$1:group-1" -F '#{pane_dead}' 2>/dev/null) == 1 ]]
}

packed() {
    local first second
    first=$(tmux list-panes -t "$1:group-1" -F '#{pane_title}' 2>/dev/null) || return 1
    second=$(tmux list-panes -t "$1:group-2" -F '#{pane_title}' 2>/dev/null) || return 1
    [[ $(printf '%s\n' "$first" | wc -l) -eq 2 ]] || return 1
    [[ $(printf '%s\n' "$second" | wc -l) -eq 1 ]] || return 1
    [[ $first != *alpha* && $second != *alpha* ]]
}

mkdir -p "$test_dir/bin" "$test_dir/sets"
cp "$project_root/fleet" "$test_dir/fleet"
chmod +x "$test_dir/fleet"
ln -s "$test_dir/fleet" "$test_dir/bin/fleet"
printf '  # comment\n alpha \n\nbeta\ngamma\r\ndelta\n' > "$test_dir/sets/four.hosts"
printf '%s\n' alpha beta > "$test_dir/sets/two.hosts"
printf '%s\n' alpha > "$test_dir/sets/one.hosts"
printf '%s\n' '-oProxyCommand=bad' > "$test_dir/sets/bad.hosts"

export FLEET_TEST_REAL_TMUX=$real_tmux
cat > "$test_dir/bin/tmux" <<'EOF'
#!/usr/bin/env bash
"$FLEET_TEST_REAL_TMUX" -L "$FLEET_TEST_SOCKET" -f /dev/null "$@"
status=$?
if [[ ${FLEET_TEST_SLOW_SETUP:-0} == 1 && $1 == respawn-pane ]]; then
    sleep 2
fi
exit "$status"
EOF
cat > "$test_dir/bin/ssh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
while [[ ${1:-} != -- ]]; do
    (( $# > 0 )) || exit 90
    shift
done
shift
(( $# == 2 )) || exit 90
host=$1
printf '%s\n' "$2" > "$FLEET_TEST_STATE/command-$host"
printf 'start\t%s\t%s\n' "$host" "$(date +%s%N)" >> "$FLEET_TEST_STATE/events"
: > "$FLEET_TEST_STATE/started-$host"
if [[ ${FLEET_TEST_HOLD:-0} == 1 ]]; then
    deadline=$((SECONDS + 15))
    until [[ -e $FLEET_TEST_STATE/release-$host ]]; do
        (( SECONDS < deadline )) || exit 124
        sleep 0.05
    done
fi
printf 'end\t%s\t%s\n' "$host" "$(date +%s%N)" >> "$FLEET_TEST_STATE/events"
: > "$FLEET_TEST_STATE/completed-$host"
[[ $host != ${FLEET_TEST_FAIL_HOST:-} ]] || exit 7
printf 'output from %s\n' "$host"
EOF
chmod +x "$test_dir/bin/tmux" "$test_dir/bin/ssh"
export PATH="$test_dir/bin:$PATH"

[[ $("$test_dir/bin/fleet" --show four | wc -l) -eq 4 ]] || \
    fail 'linked launcher did not find and parse its host set'

if "$test_dir/fleet" --show bad > "$test_dir/invalid-output" 2>&1; then
    fail 'option-shaped host was accepted'
fi
grep -q 'expected one SSH host or alias' "$test_dir/invalid-output" || \
    fail 'invalid host diagnostic missing'

export FLEET_TEST_STATE="$test_dir/state-serial"
mkdir "$FLEET_TEST_STATE"
export FLEET_TEST_HOLD=0 FLEET_TEST_FAIL_HOST=beta
remote_command=$(cat <<'EOF'
printf '%s\n' "it's ready"
EOF
)
set +e
"$test_dir/fleet" four --serial --pace 1s "$remote_command" > "$test_dir/serial-output" 2>&1
status=$?
set -e
[[ $status -eq 7 ]] || fail "serial failure returned $status, expected 7"
[[ -f $FLEET_TEST_STATE/started-alpha && -f $FLEET_TEST_STATE/started-beta ]] || \
    fail 'serial run missed a host before failure'
[[ ! -f $FLEET_TEST_STATE/started-gamma ]] || fail 'serial run continued after failure'
cmp -s <(printf '%s\n' "$remote_command") "$FLEET_TEST_STATE/command-alpha" || \
    fail 'remote command changed during quoting'
read -r _ alpha_end < <(awk -F '\t' '$1 == "end" && $2 == "alpha" { print $2, $3 }' "$FLEET_TEST_STATE/events")
read -r _ beta_start < <(awk -F '\t' '$1 == "start" && $2 == "beta" { print $2, $3 }' "$FLEET_TEST_STATE/events")
(( beta_start - alpha_end >= 900000000 )) || fail 'serial pace was shorter than one second'

new_run pack
launch four --detach --panes 2 --linger 1s 'uptime'
for host in alpha beta gamma delta; do
    wait_for "$host to start" test -f "$FLEET_TEST_STATE/started-$host"
done
: > "$FLEET_TEST_STATE/release-alpha"
wait_for 'live panes to fill the first window' packed "$session"
for host in beta gamma delta; do : > "$FLEET_TEST_STATE/release-$host"; done
wait_for 'the packed session to close' session_gone "$session"

new_run immediate
export FLEET_TEST_HOLD=0 FLEET_TEST_SLOW_SETUP=1
launch one --detach --linger 0s 'uptime'
test -f "$FLEET_TEST_STATE/completed-alpha" || fail 'host did not finish during slow setup'
wait_for 'zero-delay session to close' session_gone "$session"

new_run default
launch one --detach 'uptime'
wait_for 'default-linger host to start' test -f "$FLEET_TEST_STATE/started-alpha"
: > "$FLEET_TEST_STATE/release-alpha"
wait_for 'default-linger pane to finish' pane_dead "$session"
sleep 2
tmux has-session -t "$session" || fail 'default pane closed before ten seconds'
wait_for 'default-linger session to close' session_gone "$session"

new_run forever
launch one --detach --linger forever 'uptime'
wait_for 'retained host to start' test -f "$FLEET_TEST_STATE/started-alpha"
: > "$FLEET_TEST_STATE/release-alpha"
wait_for 'retained pane to finish' pane_dead "$session"
sleep 1
tmux has-session -t "$session" || fail 'forever pane was removed'
tmux kill-session -t "$session"

new_run visual_serial
launch two --serial --detach --linger 0s 'uptime'
wait_for 'first serial pane to start' test -f "$FLEET_TEST_STATE/started-alpha"
[[ ! -f $FLEET_TEST_STATE/started-beta ]] || fail 'visual serial run started two hosts together'
: > "$FLEET_TEST_STATE/release-alpha"
wait_for 'second serial pane to start' test -f "$FLEET_TEST_STATE/started-beta"
: > "$FLEET_TEST_STATE/release-beta"
wait_for 'visual serial session to close' session_gone "$session"

printf 'PASS: host validation, serial pace and failure, pane packing, linger and visual serial\n'
