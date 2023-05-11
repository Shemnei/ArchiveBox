#!/usr/bin/env bash

# Drop permissions to run commands as the archivebox user
if [[ "$1" == /* || "$1" == "echo" || "$1" == "archivebox" ]]; then
    # arg 1 is a binary, execute it verbatim
    # e.g. "archivebox init"
    #      "/bin/bash"
    #      "echo"
    exec bash -c "$*"
else
    # no command given, assume args were meant to be passed to archivebox cmd
    # e.g. "add https://example.com"
    #      "manage createsupseruser"
    #      "server 0.0.0.0:8000"
    exec bash -c "archivebox $*"
fi
