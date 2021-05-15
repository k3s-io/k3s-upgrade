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
  K3S_PID=$(ps -ef | grep -E "k3s .*(server|agent)" | grep -E -v "(init|grep|channelserver|supervise-daemon)" | awk '{print $1}')
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
  FULL_BIN_PATH="/host$K3S_BIN_PATH"
  if [ ! -f $NEW_BINARY ]; then
    fatal "The new binary $NEW_BINARY doesn't exist"
  fi
  info "Comparing old and new binaries"
  BIN_COUNT="$(sha256sum $NEW_BINARY $FULL_BIN_PATH | cut -d" " -f1 | uniq | wc -l)"
  if [ $BIN_COUNT == "1" ]; then
    info "Binary already been replaced"
    exit 0
  fi
  K3S_CONTEXT=$(getfilecon $FULL_BIN_PATH 2>/dev/null | awk '{print $2}' || true)
  info "Deploying new k3s binary to $K3S_BIN_PATH"
  cp $NEW_BINARY $FULL_BIN_PATH
  if [ -n "${K3S_CONTEXT}" ]; then
    info 'Restoring k3s bin context'
    setfilecon "${K3S_CONTEXT}" $FULL_BIN_PATH
  fi
  info "K3s binary has been replaced successfully"
  return
}

kill_k3s_process() {
    # the script sends SIGTERM to the process and let the supervisor
    # to automatically restart k3s with the new version
    kill -SIGTERM $K3S_PID
    info "Successfully Killed old k3s process $K3S_PID"
}

prepare() {
  set +e
  KUBECTL_BIN="/opt/k3s kubectl"
  MASTER_PLAN=${1}
  if [ -z "$MASTER_PLAN" ]; then
    fatal "Master Plan name is not passed to the prepare step. Exiting"
  fi
  NAMESPACE=$(cat /var/run/secrets/kubernetes.io/serviceaccount/namespace)
  while true; do
    # make sure master plan does exist
    PLAN=$(${KUBECTL_BIN} get plan $MASTER_PLAN -o jsonpath='{.metadata.name}' -n $NAMESPACE 2>/dev/null)
    if [ -z "$PLAN" ]; then
	    info "master plan $MASTER_PLAN doesn't exist"
	    sleep 5
	    continue
    fi
    NUM_NODES=$(${KUBECTL_BIN} get plan $MASTER_PLAN -n $NAMESPACE -o json | jq '.status.applying | length')
    if [ "$NUM_NODES" == "0" ]; then
      break
    fi
    info "Waiting for all master nodes to be upgraded"
    sleep 5
  done
  verify_masters_versions
}

verify_masters_versions() {
  while true; do
    all_updated="true"
    # "control-plane" was introduced in k8s 1.20
    # "master" is deprecated and will be removed in 1.24
    # we need to check for both to upgrade old clusters
    MASTER_NODE_VERSION=$(${KUBECTL_BIN} get nodes --selector='node-role.kubernetes.io/control-plane' -o json | jq -r '.items[].status.nodeInfo.kubeletVersion' | sort -u | tr '+' '-')
    if [ -z "$MASTER_NODE_VERSION" ]; then
      MASTER_NODE_VERSION=$(${KUBECTL_BIN} get nodes --selector='node-role.kubernetes.io/master' -o json | jq -r '.items[].status.nodeInfo.kubeletVersion' | sort -u | tr '+' '-')
    fi
    if [ -z "$MASTER_NODE_VERSION" ]; then
      sleep 5
      continue
    fi
    if [ "$MASTER_NODE_VERSION" == "$SYSTEM_UPGRADE_PLAN_LATEST_VERSION" ]; then
        info "All control plane nodes has been upgraded to version to $MASTER_NODE_VERSION"
		    break
		fi
    info "Waiting for all control plane nodes to be upgraded to version $MODIFIED_VERSION"
	  sleep 5
	  continue
  done
}

upgrade() {
  get_k3s_process_info
  replace_binary
  kill_k3s_process
}

"$@"
