#!/bin/sh -xe

info()
{
    echo '[INFO] ' "$@"
}

fatal()
{
    echo '[ERROR] ' "$@" >&2
    exit 1
}

get_k3s_process_info() {
  K3S_PID=$(ps -ef | grep -E "k3s .*(server|agent)" | grep -E -v "(init|grep)" | awk '{print $1}')
  if [ -z "$K3S_PID" ]; then
    fatal "K3s is not running on this server"
  fi
  info "K3S binary is running with pid $K3S_PID"
  K3S_BIN_PATH=$(cat /host/proc/${K3S_PID}/cmdline | awk '{print $1}' | head -n 1)
  if [ "$K3S_PID" == "1" ]; then
    # add exception for k3d clusters
    K3S_BIN_PATH="/bin/k3s"
  fi
  if [ -z "$K3S_BIN_PATH" ]; then
    fatal "Failed to fetch the k3s binary path from process $K3S_PID"
  fi
  return
}

replace_binary() {
  NEW_BINARY="/bin/k3s"
  info "Deploying new k3s binary to $K3S_BIN_PATH"
  if [ ! -f $NEW_BINARY ]; then
    fatal "The new binary $NEW_BINARY doesn't exist"
  fi
  FULL_BIN_PATH="/host$K3S_BIN_PATH"
  cp $NEW_BINARY $FULL_BIN_PATH
  info "K3s binary has been replaced successfully"
  return
}

kill_k3s_process() {
    # the script sends SIGTERM to the process and let the supervisor
    # to automatically restart k3s with the new version
    kill -SIGTERM $K3S_PID
    info "Successfully Killed old k3s process $K3S_PID"
}

{
  get_k3s_process_info
  replace_binary
  kill_k3s_process
}
