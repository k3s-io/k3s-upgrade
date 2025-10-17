UNAME_M = $(shell uname -m)
ifndef TARGET_PLATFORMS
	ifeq ($(UNAME_M), x86_64)
		TARGET_PLATFORMS:=linux/amd64
	else ifeq ($(UNAME_M), aarch64)
		TARGET_PLATFORMS:=linux/arm64
	else 
		TARGET_PLATFORMS:=linux/$(UNAME_M)
	endif
endif

ifeq ($(ARCH), amd64)
    ARTIFACT := k3s
else ifeq ($(ARCH), arm64)
    ARTIFACT := k3s-arm64
else ifeq ($(ARCH), arm/v7)
    ARTIFACT := k3s-armhf
endif

TAG ?= ${TAG}
# sanitize the tag
DOCKER_TAG := $(shell echo $(TAG) | sed 's/+/-/g')

export DOCKER_BUILDKIT?=1

ARCH ?= amd64
REPO ?= rancher
IMAGE = $(REPO)/k3s-upgrade:$(DOCKER_TAG)

BUILD_OPTS = \
	--platform=$(TARGET_PLATFORMS) \
	--build-arg TAG=$(TAG) \
	--build-arg ARTIFACT=$(ARTIFACT) \
	--tag "$(IMAGE)"

.PHONY: push-image
push-image: download-assets
	docker buildx build \
		$(BUILD_OPTS) \
		$(IID_FILE_FLAG) \
		--sbom=true \
		--attest type=provenance,mode=max \
		--push \
		--file ./Dockerfile \
		.

.PHONY: publish-manifest
publish-manifest:
	IMAGE=$(IMAGE) ./scripts/publish-manifest

.PHONY: download-assets
download-assets: 
	ARCH=$(ARCH) ARTIFACT=$(ARTIFACT) VERSION=$(VERSION) ./scripts/download
