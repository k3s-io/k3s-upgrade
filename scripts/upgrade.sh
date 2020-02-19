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
  NEW_BINARY="/opt/k3s"
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

check_hash(){
    sha_cmd="sha256sum"

    if [ ! -x "$(command -v $sha_cmd)" ]; then
    sha_cmd="shasum -a 256"
    fi

    if [ -x "$(command -v $sha_cmd)" ]; then

    K3S_RELEASE_CHECKSUM=$(echo $K3S_RELEASE_CHECKSUM | sed "s/sha256sum.txt/sha256sum-amd64.txt/g")
    (cd /opt && curl -sSL K3S_RELEASE_CHECKSUM | head -1 | $sha_cmd -c >/dev/null)
        if [ "$?" != "0" ]; then
            fatal "Binary checksum didn't match. Exiting"
        fi
    fi
}

prepare() {
  KUBECTL_BIN="/opt/k3s kubectl"
  MASTER_PLAN=${1}
  if [ -z "$MASTER_PLAN" ]; then
    fatal "Master Plan name is not passed to the prepare step. Exiting"
  fi
  NAMESPACE=$(cat /var/run/secrets/kubernetes.io/serviceaccount/namespace)
  # make sure master plan does exist
  ${KUBECTL_BIN} get plan $MASTER_PLAN -n $NAMESPACE &>/dev/null || fatal "master plan $MASTER_PLAN doesn't exist"
  while true; do
    NUM_NODES=$(${KUBECTL_BIN} get plan $MASTER_PLAN -n $NAMESPACE -o json | jq '.status.applying | length')
    if [ "$NUM_NODES" == "0" ]; then
      break
    fi
    info "Waiting for all master nodes to be upgraded"
    sleep 5
  done
}

upgrade() {
  check_hash
  get_k3s_process_info
  replace_binary
  kill_k3s_process
}

"$@"