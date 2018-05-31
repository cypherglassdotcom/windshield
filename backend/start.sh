#!/bin/bash

./stop.sh

export PORT=4000
export MIX_ENV=prod

/usr/local/bin/mix phx.server "$@" > ./stdout.txt 2> stderr.txt & echo $! > ./phx.server.pid
