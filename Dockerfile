ARG ALPINE=alpine:3.20
FROM ${ALPINE} AS verify
ARG TARGETARCH
ARG TAG
WORKDIR /verify
ADD https://github.com/k3s-io/k3s/releases/download/${TAG}/sha256sum-${TARGETARCH}.txt .
RUN set -x \
 && apk upgrade -U \
 && apk add \
    curl file \
 && apk cache clean \
 && rm -rf /var/cache/apk/*
 
RUN if [ "${TARGETARCH}" == "amd64" ]; then \
      export ARTIFACT="k3s"; \
    elif [ "${TARGETARCH}" == "arm" ]; then \
      export ARTIFACT="k3s-armhf"; \
    else \
      export ARTIFACT="k3s-${TARGETARCH}"; \
    fi \
 && curl --output ${ARTIFACT}  --fail --location https://github.com/k3s-io/k3s/releases/download/${TAG}/${ARTIFACT} \
 && grep -E " k3s(-arm\w*|-s390x)?$" sha256sum-${TARGETARCH}.txt | sha256sum -c \
 && mv -vf ${ARTIFACT} /opt/k3s \
 && chmod +x /opt/k3s \
 && file /opt/k3s

FROM ${ALPINE}
ARG ARCH
ARG TAG
RUN apk upgrade -U \
 && apk add \
    jq libselinux-utils procps \
 && apk cache clean \
 && rm -rf /var/cache/apk/*
COPY --from=verify /opt/k3s /opt/k3s
COPY scripts/upgrade.sh /bin/upgrade.sh
ENTRYPOINT ["/bin/upgrade.sh"]
CMD ["upgrade"]
