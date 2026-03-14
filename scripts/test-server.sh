#!/usr/bin/env bash
# Start Phoenix on port 4001 for testing (parallel to dev on 4000)
set -euo pipefail

PORT=4001

# Kill any existing process on this port
lsof -ti:$PORT | xargs kill -9 2>/dev/null || true

export PORT
exec elixir --sname bibtime_test_$$@localhost -S mix phx.server
