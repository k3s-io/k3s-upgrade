FROM alpine:3.10

ARG ARCH=

ENV K3S_RELEASE https://github.com/rancher/k3s/releases/download/${DRONE_TAG}/k3s${ARCH}

RUN wget -O /bin/k3s ${K3S_RELEASE}
RUN chmod +x /bin/k3s
COPY scripts/upgrade.sh /bin/upgrade.sh

ENTRYPOINT ["/bin/upgrade.sh"]
