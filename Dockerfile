FROM alpine:3.10

ARG ARCH
ARG DRONE_TAG

ENV K3S_RELEASE https://github.com/rancher/k3s/releases/download/${DRONE_TAG}/k3s${ARCH}
ENV K3S_RELEASE_CHECKSUM https://github.com/rancher/k3s/releases/download/${DRONE_TAG}/sha256sum${ARCH}.txt

RUN apk add -U jq curl
RUN curl -L -o /opt/k3s ${K3S_RELEASE}
RUN chmod +x /opt/k3s
COPY scripts/upgrade.sh /bin/upgrade.sh

ENTRYPOINT ["/bin/upgrade.sh"]
CMD ["upgrade"]
