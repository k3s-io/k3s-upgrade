ARG ALPINE=alpine:3.20
FROM ${ALPINE} AS verify
ARG TARGETARCH
ARG TAG
ARG ARTIFACT
WORKDIR /verify

# Copy the pre-downloaded files from the local directory (those files are retrieved by scripts/download)
COPY artifacts/sha256sum-${TARGETARCH}.txt .
COPY artifacts/${ARTIFACT} .

RUN set -x \
 && apk upgrade -U \
 && apk add \
    curl file \
 && apk cache clean \
 && rm -rf /var/cache/apk/*
 
RUN grep -E " k3s(-arm\w*|-s390x)?$" sha256sum-${TARGETARCH}.txt | sha256sum -c \
 && mv -vf ${ARTIFACT} /opt/k3s \
 && chmod +x /opt/k3s \
 && file /opt/k3s

FROM ${ALPINE}
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
