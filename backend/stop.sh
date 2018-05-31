#!/bin/bash

if [ -f "./phx.server.pid" ]; then
    pid=$(cat "./phx.server.pid")
    echo $pid
    kill $pid
    rm -r "./phx.server.pid"
    echo -ne "Stopping WINDSHIELD Phoenix Server"
    while true; do
        [ ! -d "/proc/$pid/fd" ] && break
        echo -ne "."
        sleep 1
    done
    echo -ne "\rWINDSHIELD stopped. \n"
fi
