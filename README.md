# k3s-upgrade

k3s-upgrade is an image that is responsible of upgrading k3s version via the [System Upgrade Controller](https://github.com/rancher/system-upgrade-controller), it does that by doing the following:

- Replace the k3s binary with the new version
- Kill the old k3s process allowing the supervisor to restart k3s with the new version

## Build

To build the k3s-upgrade image locally, you can run the following:

```
export ARCH=amd64 TAG=v1.17.2+k3s1
docker build --build-arg ARCH --build-arg TAG --tag ${REPO:=k3s-io}/k3s-upgrade:${TAG/+/-} .
```

## Usage

### Prerequisites

- K3s has to be installed using the install script using the curl command:
```
curl -sfL https://get.k3s.io | sh -
```

## Example

1- To use the image with the system-upgrade-controller, you have first to run the controller either directly or deploy it on the k3s cluster:

```
kubectl apply -f https://raw.githubusercontent.com/rancher/system-upgrade-controller/master/manifests/system-upgrade-controller.yaml
```

You should see the upgrade controller starting in `system-upgrade` namespace.

2- Label the nodes you want to upgrade with the right label:
```
kubectl label node <node-name> k3s-upgrade=true
```

3- Run the upgrade plan in the k3s cluster

```
---
apiVersion: upgrade.cattle.io/v1
kind: Plan
metadata:
  name: k3s-latest
  namespace: system-upgrade
spec:
  concurrency: 1
  version: v1.17.2-k3s1
  nodeSelector:
    matchExpressions:
      - {key: k3s-upgrade, operator: Exists}
  serviceAccountName: system-upgrade
  drain:
    force: true
  upgrade:
    image: rancher/k3s-upgrade
``` 

The upgrade controller should watch for this plan and execute the upgrade on the labeled nodes. For more information about system-upgrade-controller and plan options please visit [system-upgrade-controller](https://github.com/rancher/system-upgrade-controller) official repo.


## Downgrade Prevention

Starting with the 2023-07 releases ([v1.27.4+k3s1](https://github.com/k3s-io/k3s-upgrade/releases/tag/v1.27.4%2Bk3s1), [v1.26.7+k3s1](https://github.com/k3s-io/k3s-upgrade/releases/tag/v1.26.7%2Bk3s1), [v1.25.12+k3s1](https://github.com/k3s-io/k3s-upgrade/releases/tag/v1.25.12%2Bk3s1), [v1.24.16+k3s1](https://github.com/k3s-io/k3s-upgrade/releases/tag/v1.24.16%2Bk3s1))

Kubernetes does not support downgrades of control-plane components. The k3s-upgrade image used by upgrade plans will refuse to downgrade K3s, failing the plan and leaving your nodes cordoned.

Here is an example cluster, showing failed upgrade pods and cordoned nodes:

```console
ubuntu@user:~$ kubectl get pods -n system-upgrade
NAME                                                              READY   STATUS    RESTARTS   AGE
apply-k3s-server-on-ip-172-31-0-16-with-7af95590a5af8e8c3-2cdc6   0/1     Error     0          9m25s
apply-k3s-server-on-ip-172-31-10-23-with-7af95590a5af8e8c-9xvwg   0/1     Error     0          14m
apply-k3s-server-on-ip-172-31-13-213-with-7af95590a5af8e8-8j72v   0/1     Error     0          18m
system-upgrade-controller-7c4b84d5d9-kkzr6                        1/1     Running   0          20m
ubuntu@user:~$ kubectl get nodes
NAME               STATUS                     ROLES                       AGE   VERSION
ip-172-31-0-16     Ready,SchedulingDisabled   control-plane,etcd,master   19h   v1.27.4+k3s1
ip-172-31-10-23    Ready,SchedulingDisabled   control-plane,etcd,master   19h   v1.27.4+k3s1
ip-172-31-13-213   Ready,SchedulingDisabled   control-plane,etcd,master   19h   v1.27.4+k3s1
ip-172-31-2-13     Ready                      <none>                      19h   v1.27.4+k3s1
```
You can return your cordoned nodes to service by either of the following methods:
* Change the version or channel on your plan to target a release that is the same or newer than what is currently running on the cluster, so that the plan succeeds.
* Delete the plan and manually uncordon the nodes.
  Use `kubectl get plan -n system-upgrade` to find the plan name, then `kubectl delete plan -n system-upgrade PLAN_NAME` to delete it. Once the plan has been deleted, use `kubectl uncordon NODE_NAME` to uncordon each of the nodes.

# Contact
For bugs, questions, comments, corrections, suggestions, etc., open an issue in
 [k3s-io/k3s](//github.com/k3s-io/k3s/issues) with a title starting with `[k3s-upgrade] `.
