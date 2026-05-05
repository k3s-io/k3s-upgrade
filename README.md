# k3s-upgrade

k3s-upgrade is an image that is responsible of upgrading k3s version via the [System Upgrade Controller](https://github.com/rancher/system-upgrade-controller), it does that by doing the following:

- Replace the k3s binary with the new version
- Kill the old k3s process allowing the supervisor to restart k3s with the new version

## Build

To build the k3s-upgrade image locally, you can run the following:

```
export ARCH=amd64 TAG=v1.33.5+k3s1 VERSION=v1.33.5+k3s1
make download-assets
docker buildx build --platform=linux/amd64 --build-arg TAG=$TAG --build-arg ARTIFACT=k3s --tag ${REPO:=rancher}/k3s-upgrade:${TAG/+/-} .
```

**Environment Variables:**
- `ARCH`: Target architecture (amd64, arm64, arm/v7)
- `TAG`: Image tag (used for Docker image naming)
- `VERSION`: K3s version (used for downloading artifacts)
- `REPO`: Docker repository (defaults to "rancher")

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
  version: v1.33.5+k3s1 
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

# Contact
For bugs, questions, comments, corrections, suggestions, etc., open an issue in
 [k3s-io/k3s](//github.com/k3s-io/k3s/issues) with a title starting with `[k3s-upgrade] `.
