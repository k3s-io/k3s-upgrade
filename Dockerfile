FROM alpine:3.10

ARG ARCH=
ARG VERSION="v1.17.2+k3s1"

ENV K3S_RELEASE https://github.com/rancher/k3s/releases/download/${VERSION}/k3s${ARCH}

RUN wget -O /bin/k3s${ARCH} ${K3S_RELEASE}
RUN chmod +x /bin/k3s${ARCH}
COPY scripts/upgrade.sh /bin/upgrade.sh

ENTRYPOINT ["/bin/upgrade.sh"]
