#!/bin/bash

# This Docker ENTRYPOINT script is called by `docker run archivebox ...` or `docker compose run archivebox ...`.
# It takes a CMD as $* shell arguments and runs it following these setup steps:

# - Set the archivebox user to use the correct PUID & PGID
#     1. highest precedence is for valid PUID and PGID env vars passsed in explicitly
#     2. fall back to DETECTED_PUID of files found within existing data dir
#     3. fall back to DEFAULT_PUID if no data dir or its owned by root
# - Create a new /data dir if necessary and set the correct ownership on it
# - Create a new /browsers dir if necessary and set the correct ownership on it
# - Check whether we're running inside QEMU emulation and show a warning if so.
# - Check that enough free space is available on / and /data
# - Drop down to archivebox user permisisons and execute passed CMD command.

# Bash Environment Setup
# http://redsymbol.net/articles/unofficial-bash-strict-mode/
# https://www.gnu.org/software/bash/manual/html_node/The-Set-Builtin.html
# set -o xtrace
# set -o nounset
set -o errexit
set -o errtrace
set -o pipefail
# IFS=$'\n'

# Load global invariants (set by Dockerfile during image build time, not intended to be customized by users at runtime)
export DATA_DIR="${DATA_DIR:-/data}"

# force set the ownership of the data dir contents to the archivebox user and group
# this is needed because Docker Desktop often does not map user permissions from the host properly
chown $PUID:$PGID "$DATA_DIR"
chown $PUID:$PGID "$DATA_DIR"/*

# also chown BROWSERS_DIR because otherwise 'archivebox setup' wont be able to install chrome at runtime
export PLAYWRIGHT_BROWSERS_PATH="${PLAYWRIGHT_BROWSERS_PATH:-/browsers}"
mkdir -p "$PLAYWRIGHT_BROWSERS_PATH/permissions_test_safe_to_delete"
chown $PUID:$PGID "$PLAYWRIGHT_BROWSERS_PATH"
chown $PUID:$PGID "$PLAYWRIGHT_BROWSERS_PATH"/*
rm -Rf "$PLAYWRIGHT_BROWSERS_PATH/permissions_test_safe_to_delete"


# (this check is written in blood in 2023, QEMU silently breaks things in ways that are not obvious)
export IN_QEMU="$(pmap 1 | grep qemu >/dev/null && echo 'True' || echo 'False')"
if [[ "$IN_QEMU" == "True" ]]; then
    echo -e "\n[!] Warning: Running $(uname -m) docker image using QEMU emulation, some things will break!" > /dev/stderr
    echo -e "    chromium (screenshot, pdf, dom), singlefile, and any dependencies that rely on inotify will not run in QEMU." > /dev/stderr
    echo -e "    See here for more info: https://github.com/microsoft/playwright/issues/17395#issuecomment-1250830493\n" > /dev/stderr
fi

# check disk space free on / and /data, warn on <500Mb free, error on <100Mb free
export ROOT_USAGE="$(df --output=pcent,avail / | tail -n 1 | xargs)"
export ROOT_USED_PCT="${ROOT_USAGE%%%*}"
export ROOT_AVAIL_KB="$(echo "$ROOT_USAGE" | awk '{print $2}')"
if [[ "$ROOT_AVAIL_KB" -lt 100000 ]]; then
    echo -e "\n[!] Warning: Docker root filesystem is completely out of space! (${ROOT_USED_PCT}% used on /)" > /dev/stderr
    echo -e "    you need to free up at least 100Mb in your Docker VM to continue:" > /dev/stderr
    echo -e "    \$ docker system prune\n" > /dev/stderr
    df -kh / > /dev/stderr
    exit 3
elif [[ "$ROOT_USED_PCT" -ge 99 ]] || [[ "$ROOT_AVAIL_KB" -lt 500000 ]]; then
    echo -e "\n[!] Warning: Docker root filesystem is running out of space! (${ROOT_USED_PCT}% used on /)" > /dev/stderr
    echo -e "    you may need to free up space in your Docker VM soon:" > /dev/stderr
    echo -e "    \$ docker system prune\n" > /dev/stderr
    df -kh / > /dev/stderr
fi

export DATA_USAGE="$(df --output=pcent,avail /data | tail -n 1 | xargs)"
export DATA_USED_PCT="${DATA_USAGE%%%*}"
export DATA_AVAIL_KB="$(echo "$DATA_USAGE" | awk '{print $2}')"
if [[ "$DATA_AVAIL_KB" -lt 100000 ]]; then
    echo -e "\n[!] Warning: Docker data volume is completely out of space! (${DATA_USED_PCT}% used on /data)" > /dev/stderr
    echo -e "    you need to free up at least 100Mb on the drive holding your data directory" > /dev/stderr
    echo -e "    \$ ncdu -x data\n" > /dev/stderr
    df -kh /data > /dev/stderr
    sleep 5
elif [[ "$DATA_USED_PCT" -ge 99 ]] || [[ "$ROOT_AVAIL_KB" -lt 500000 ]]; then
    echo -e "\n[!] Warning: Docker data volume is running out of space! (${DATA_USED_PCT}% used on /data)" > /dev/stderr
    echo -e "    you may need to free up space on the drive holding your data directory soon" > /dev/stderr
    echo -e "    \$ ncdu -x data\n" > /dev/stderr
    df -kh /data > /dev/stderr
fi


export ARCHIVEBOX_BIN_PATH="$(which archivebox)"

# Drop permissions to run commands as the archivebox user
if [[ "$1" == /* || "$1" == "bash" || "$1" == "sh" || "$1" == "echo" || "$1" == "cat" || "$1" == "whoami" || "$1" == "archivebox" ]]; then
    # handle "docker run archivebox /bin/somecommand --with=some args" by passing args directly to bash -c
    # e.g. "docker run archivebox archivebox init:
    #      "docker run archivebox /venv/bin/ipython3"
    #      "docker run archivebox /bin/bash -c '...'"
    #      "docker run archivebox cat /VERSION.txt"
    exec gosu "$PUID" /bin/bash -c "exec $(printf ' %q' "$@")"
    # printf requotes shell parameters properly https://stackoverflow.com/a/39463371/2156113
    # gosu spawns an ephemeral bash process owned by archivebox user (bash wrapper is needed to load env vars, PATH, and setup terminal TTY)
    # outermost exec hands over current process ID to inner bash process, inner exec hands over inner bash PID to user's command
else
    # handle "docker run archivebox add some subcommand --with=args abc" by calling archivebox to run as args as CLI subcommand
    # e.g. "docker run archivebox help"
    #      "docker run archivebox add --depth=1 https://example.com"
    #      "docker run archivebox manage createsupseruser"
    #      "docker run archivebox server 0.0.0.0:8000"
    exec gosu "$PUID" "$ARCHIVEBOX_BIN_PATH" "$@"
fi
