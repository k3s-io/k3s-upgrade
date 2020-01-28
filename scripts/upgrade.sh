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

verify_system() {
    if ! type pgrep; then
      fatal 'Can not find pgrep tool'
    fi
    if [ -x /host/sbin/openrc-run ]; then
        HAS_OPENRC=true
        return
    fi
    if [ -d /host/run/systemd ]; then
        HAS_SYSTEMD=true
        return
    fi
    fatal 'Can not find systemd or openrc to use as a process supervisor for k3s'
}

setup_verify_arch() {
    if [ -z "$ARCH" ]; then
        ARCH=$(uname -m)
    fi
    case $ARCH in
        amd64)
            ARCH=amd64
            SUFFIX=
            ;;
        x86_64)
            ARCH=amd64
            SUFFIX=
            ;;
        arm64)
            ARCH=arm64
            SUFFIX=-${ARCH}
            ;;
        aarch64)
            ARCH=arm64
            SUFFIX=-${ARCH}
            ;;
        arm*)
            ARCH=arm
            SUFFIX=-${ARCH}hf
            ;;
        *)
            fatal "Unsupported architecture $ARCH"
    esac
}

get_k3s_process_info() {
  K3S_PID=$(pgrep k3s-)
  if [ -z "$K3S_PID" ]; then
    fatal "K3s is not running on this server"
  fi
  #K3S_BIN_PATH=$(ls  -l /host/proc/${K3S_PID}/exe | awk -F '-> ' '{print $2}')
  K3S_BIN_PATH=$(cat /host/proc/${K3S_PID}/cmdline | awk '{print $1}' | head -n 1)
  if [ -z "$K3S_BIN_PATH" ]; then
    fatal "Failed to fetch the k3s binary path from process $K3S_PID"
  fi
  return
}

replace_binary() {
  NEW_BINARY="/bin/k3s${SUFFIX}"
  if [ ! -f $NEW_BINARY ]; then
    fatal "The new binary $NEW_BINARY doesn't exist"
  fi
  FULL_BIN_PATH="host/$K3S_BIN_PATH"
  cp $NEW_BINARY $FULL_BIN_PATH
  info "K3s binary has been replaced successfully"
  return
}

kill_k3s_process() {
    # the script sends SIGTERM to the process and let the supervisor
    # to automatically restart k3s with the new version
    kill -SIGTERM $K3S_PID
}

{
  verify_system
  setup_verify_arch
  get_k3s_process_info
  replace_binary
  kill_k3s_process
}
