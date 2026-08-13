#!/bin/zsh
cd "$(dirname "$0")"
PORT=4173 node server.js >/tmp/kikoeru-server.log 2>&1 &
SERVER_PID=$!
sleep 0.6
open "http://localhost:4173"
trap 'kill $SERVER_PID 2>/dev/null' EXIT
wait $SERVER_PID
