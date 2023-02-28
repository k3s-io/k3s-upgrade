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
  K3S_PID=$(ps -ef | grep -E "k3s .*(server|agent)" | grep -E -v "(init|grep|channelserver|supervise-daemon)" | awk '{print $2}')

  if [ -z "$K3S_PID" ]; then
    fatal "K3s is not running on this server"
  fi

  if [ "$(echo $K3S_PID | wc -w)" != "1" ]; then
    for PID in $K3S_PID; do
      ps -fp $PID || true
    done
    fatal "Found multiple K3s pids"
  fi

  K3S_PPID=$(ps -p $K3S_PID -o ppid= | awk '{print $1}')
  info "K3S binary is running with pid $K3S_PID, parent pid $K3S_PPID"

  # When running with the --log flag, the 'k3s server|agent' process is nested under a 'k3s init' process.
  # If the parent pid is not 1 (init/systemd) then we are nested and need to operate against that 'k3s init' pid instead.
  # Make sure that the parent pid is actually k3s though, as openrc systems may run k3s under supervise-daemon instead of
  # as a child process of init.
  if [ "$K3S_PPID" != "1" ] && grep -qs k3s /host/proc/${K3S_PPID}/cmdline; then
    K3S_PID="${K3S_PPID}"
  fi

  # When running in k3d, k3s will be pid 1 and is always at /bin/k3s
  if [ "$K3S_PID" == "1" ]; then
    K3S_BIN_PATH="/bin/k3s"
  else
    K3S_BIN_PATH=$(awk 'NR==1 {print $1}' /host/proc/${K3S_PID}/cmdline)
  fi

  if [ -z "$K3S_BIN_PATH" ]; then
    fatal "Failed to fetch the k3s binary path from pid $K3S_PID"
  fi
  return
}

replace_binary() {
  NEW_BINARY="/opt/k3s"
  FULL_BIN_PATH="/host$K3S_BIN_PATH"

  if [ ! -f "$NEW_BINARY" ]; then
    fatal "The new binary $NEW_BINARY doesn't exist"
  fi

  info "Comparing old and new binaries"
  BIN_CHECKSUMS="$(sha256sum $NEW_BINARY $FULL_BIN_PATH)"

  if [ "$?" != "0" ]; then
    fatal "Failed to calculate binary checksums"
  fi

  BIN_COUNT="$(echo "${BIN_CHECKSUMS}" | awk '{print $1}' | uniq | wc -l)"
  if [ "$BIN_COUNT" == "1" ]; then
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
    info "Successfully killed old k3s pid $K3S_PID"
}

prepare() {
  set +e
  KUBECTL_BIN="/opt/k3s kubectl"
  CONTROLPLANE_PLAN=${1}

  if [ -z "$CONTROLPLANE_PLAN" ]; then
    fatal "Control-plane Plan name was not passed to the prepare step. Exiting"
  fi

  NAMESPACE=$(cat /var/run/secrets/kubernetes.io/serviceaccount/namespace)
  while true; do
    # make sure control-plane plan does exist
    PLAN=$(${KUBECTL_BIN} get plan $CONTROLPLANE_PLAN -o jsonpath='{.metadata.name}' -n $NAMESPACE 2>/dev/null)
    if [ -z "$PLAN" ]; then
	    info "Waiting for control-plane Plan $CONTROLPLANE_PLAN to be created"
	    sleep 5
	    continue
    fi
    NUM_NODES=$(${KUBECTL_BIN} get plan $CONTROLPLANE_PLAN -n $NAMESPACE -o json | jq '.status.applying | length')
    if [ "$NUM_NODES" == "0" ]; then
      break
    fi
    info "Waiting for all control-plane nodes to be upgraded"
    sleep 5
  done
  verify_controlplane_versions
}

verify_controlplane_versions() {
  while true; do
    CONTROLPLANE_NODE_VERSION=$(${KUBECTL_BIN} get nodes --selector='node-role.kubernetes.io/control-plane' -o json | jq -r '.items[].status.nodeInfo.kubeletVersion' | sort -u | tr '+' '-')
    if [ -z "$CONTROLPLANE_NODE_VERSION" ]; then
      sleep 5
      continue
    fi
    if [ "$CONTROLPLANE_NODE_VERSION" == "$SYSTEM_UPGRADE_PLAN_LATEST_VERSION" ]; then
        info "All control-plane nodes have been upgraded to version to $CONTROLPLANE_NODE_VERSION"
		    break
		fi
    info "Waiting for all control-plane nodes to be upgraded to version $MODIFIED_VERSION"
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
