#!/usr/bin/env bash
# Test server management for Phoenix (parallel to dev on port 4000)
# Usage: scripts/test-server.sh [start|stop|status|restart]
set -euo pipefail

PORT=4001
PIDFILE="/tmp/bibtime-test-server.pid"
LOGFILE="/tmp/bibtime-test-server.log"

kill_port() {
  lsof -ti:"$PORT" 2>/dev/null | xargs kill -9 2>/dev/null || true
}

cleanup_pidfile() {
  if [ -f "$PIDFILE" ]; then
    local pid
    pid=$(cat "$PIDFILE")
    if ! kill -0 "$pid" 2>/dev/null; then
      rm -f "$PIDFILE"
    fi
  fi
}

wait_ready() {
  local max_wait=30
  local i=0
  while [ $i -lt $max_wait ]; do
    if curl -s -o /dev/null -w "" "http://localhost:$PORT" 2>/dev/null; then
      return 0
    fi
    sleep 1
    i=$((i + 1))
  done
  return 1
}

do_start() {
  cleanup_pidfile

  if [ -f "$PIDFILE" ]; then
    local pid
    pid=$(cat "$PIDFILE")
    echo "Test server already running (pid $pid) on port $PORT"
    return 0
  fi

  kill_port

  echo "Starting test server on port $PORT..."
  PORT=$PORT nohup elixir --sname "bibtime_test@localhost" -S mix phx.server > "$LOGFILE" 2>&1 &
  local pid=$!
  echo "$pid" > "$PIDFILE"

  if wait_ready; then
    echo "Test server ready at http://localhost:$PORT (pid $pid)"
  else
    echo "Warning: server started (pid $pid) but health check timed out"
    echo "Check logs: $LOGFILE"
  fi
}

do_stop() {
  cleanup_pidfile

  if [ -f "$PIDFILE" ]; then
    local pid
    pid=$(cat "$PIDFILE")
    echo "Stopping test server (pid $pid)..."
    kill "$pid" 2>/dev/null || true
    rm -f "$PIDFILE"
  fi

  # Also kill anything still on the port
  kill_port
  echo "Test server stopped."
}

do_status() {
  cleanup_pidfile

  if [ -f "$PIDFILE" ]; then
    local pid
    pid=$(cat "$PIDFILE")
    echo "Test server running (pid $pid) on port $PORT"
    return 0
  fi

  if lsof -ti:"$PORT" >/dev/null 2>&1; then
    echo "Something is running on port $PORT (not managed by this script)"
    return 0
  fi

  echo "Test server not running."
  return 1
}

case "${1:-start}" in
  start)   do_start ;;
  stop)    do_stop ;;
  status)  do_status ;;
  restart) do_stop; sleep 1; do_start ;;
  *)       echo "Usage: $0 [start|stop|status|restart]"; exit 1 ;;
esac
