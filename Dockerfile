ARG ALPINE=alpine:3.15.4
FROM ${ALPINE} AS verify
ARG ARCH
ARG TAG
WORKDIR /verify
ADD https://github.com/k3s-io/k3s/releases/download/${TAG}/sha256sum-${ARCH}.txt .
RUN set -x \
 && apk --no-cache add \
    curl \
    file
RUN if [ "${ARCH}" == "amd64" ]; then \
      export ARTIFACT="k3s"; \
    elif [ "${ARCH}" == "arm" ]; then \
      export ARTIFACT="k3s-armhf"; \
    elif [ "${ARCH}" == "arm64" ]; then \
      export ARTIFACT="k3s-arm64"; \
    elif [ "${ARCH}" == "s390x" ]; then \
      export ARTIFACT="k3s-s390x"; \
    fi \
 && curl --output ${ARTIFACT}  --fail --location https://github.com/k3s-io/k3s/releases/download/${TAG}/${ARTIFACT} \
 && grep -E " k3s(-arm\w*|-s390x)?$" sha256sum-${ARCH}.txt | sha256sum -c \
 && mv -vf ${ARTIFACT} /opt/k3s \
 && chmod +x /opt/k3s \
 && file /opt/k3s

FROM ${ALPINE}
ARG ARCH
ARG TAG
RUN apk --no-cache add \
    jq libselinux-utils
COPY --from=verify /opt/k3s /opt/k3s
COPY scripts/upgrade.sh /bin/upgrade.sh
ENTRYPOINT ["/bin/upgrade.sh"]
CMD ["upgrade"]
