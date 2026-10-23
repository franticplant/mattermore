# All final targets share exactly the same application payload. Update image
# digests deliberately; see docs/containers.md. Build only from a tracked context.
ARG RUNTIME=minimal
FROM docker.io/library/node:22.22.2-bookworm-slim@sha256:9f6d5975c7dca860947d3915877f85607946403fc55349f39b4bc3688448bb6e AS node
FROM docker.io/library/golang:1.26.8-bookworm@sha256:dc9ad6c05acc7a88e5b71bde60a5fe3bd4b9f0db209011711b464107438a8107 AS toolchain
COPY --from=node /usr/local/ /usr/local/
ENV GOTOOLCHAIN=local GOFLAGS=-mod=readonly
WORKDIR /src
COPY upstream.env LICENSE ./
COPY scripts/ scripts/
COPY patches/ patches/
COPY brand/ brand/
COPY config/ config/
ARG SOURCE_DATE_EPOCH
ARG SOURCE_REVISION
ARG SERVER_COMMIT
ARG CALLS_COMMIT
# The arguments are recorded in BuildKit provenance; the scripts independently
# check the immutable revisions in upstream.env against the fetched tag objects.
RUN expected_server="$SERVER_COMMIT" && expected_calls="$CALLS_COMMIT" && \
    . ./upstream.env && test -n "$SOURCE_DATE_EPOCH" && test -n "$SOURCE_REVISION" && \
    test "$expected_server" = "$SERVER_COMMIT" && test "$expected_calls" = "$CALLS_COMMIT"

FROM toolchain AS server-binary
RUN SKIP_WEBAPP=1 scripts/build-server.sh /out/mattermore-server
FROM server-binary AS server
RUN scripts/build-webapp.sh build/server /out
# mmctl in the inherited image uses glibc. Build the matching source statically
# so Alpine and shell-free variants have the same functioning local-mode CLI.
RUN cd build/server/server && CGO_ENABLED=0 go build -trimpath -buildvcs=false \
    -ldflags='-buildid=' -o /out/mmctl ./cmd/mmctl
RUN mkdir -p /out/build-inputs/server-webapp /out/build-inputs/server && cp upstream.env /out/build-inputs/ && \
    cp build/server/webapp/package-lock.json /out/build-inputs/server-webapp/ && \
    cp build/server/server/go.mod build/server/server/go.sum /out/build-inputs/server/

FROM server AS calls
RUN scripts/build-calls.sh /out && . ./upstream.env && \
    mv /out/mattermore-calls-$CALLS_VERSION.tar.gz /out/mattermore-calls.tar.gz && \
    mkdir -p /out/build-inputs/calls-webapp /out/build-inputs/calls-standalone /out/build-inputs/calls && \
    cp build/calls/webapp/package-lock.json /out/build-inputs/calls-webapp/ && \
    cp build/calls/standalone/package-lock.json /out/build-inputs/calls-standalone/ && \
    cp build/calls/go.mod build/calls/go.sum /out/build-inputs/calls/

FROM docker.io/mattermost/mattermost-team-edition:12.0.1@sha256:b0fdecf049bbb5d224d719bade7f438261b27e7061205f904bcc9e4f2f36eb70 AS upstream
FROM docker.io/library/python:3.14.3-alpine3.23@sha256:faee120f7885a06fcc9677922331391fa690d911c020abb9e8025ff3d908e510 AS payload
COPY --from=upstream /mattermost /mattermost
RUN rm -rf /mattermost/client /mattermost/bin/mattermost /mattermost/bin/mmctl && \
    mkdir -p /mattermost/client/plugins /mattermost/data /mattermost/logs /mattermost/plugins
COPY --from=server /out/mattermore-server /mattermost/bin/mattermost
COPY --from=server /out/mmctl /mattermost/bin/mmctl
COPY --from=server /out/client /mattermost/client
COPY --from=calls /out/mattermore-calls.tar.gz /mattermost/prepackaged_plugins/mattermore-calls-linux-amd64.tar.gz
COPY --from=server /out/build-inputs /mattermost/build-inputs
COPY --from=calls /out/build-inputs /mattermost/build-inputs
COPY LICENSE /mattermost/NOTICE-Mattermore-AGPL.txt
COPY config/overrides.json /overrides.json
COPY scripts/merge-config.py /merge.py
RUN python3 /merge.py /mattermost/config/config.json /overrides.json /mattermost/config/config.json && \
    chmod 600 /mattermost/config/config.json && mkdir -p /mattermost/client/plugins && \
    chown -R 2000:2000 /mattermost

# Minimal retains glibc for inherited third-party plugins, but no shell or
# package manager. No inherited server/webapp layers remain in any final image.
FROM gcr.io/distroless/base-debian12:nonroot@sha256:7f0c72cd138b442ae0deeb69c08b1acf5525439ba251a49ad93c320a061567e5 AS minimal-base
FROM docker.io/library/alpine:3.23@sha256:ff7f0c727dd796aa36787bfcd9a64bf35a6ce72a73451b3359fde849b6703d63 AS alpine-base
FROM registry.access.redhat.com/ubi9/ubi-minimal:9.7@sha256:907b68736aa798b2d38255b7aa070b2a70acb90803864a40f05d0ec47556ddd0 AS ubi-base
FROM registry.access.redhat.com/ubi9/ubi-micro:9.7@sha256:03b67880096c45fbad58a50a5710bd31c3bcfce44f75da95ee6177dc269a72ef AS ubi-micro-base
FROM alpine-base AS debug-base
RUN apk add --no-cache ca-certificates curl bind-tools iproute2 busybox-extras procps strace

FROM ${RUNTIME}-base AS runtime
COPY --from=payload --chown=2000:2000 /mattermost /mattermost
# UBI Micro/Alpine need the same explicit trust bundle as other targets.
COPY --from=upstream /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/ca-certificates.crt
ARG SOURCE_REVISION
ARG VERSION=dev
ARG CREATED
ARG SERVER_COMMIT
ARG CALLS_COMMIT
LABEL org.opencontainers.image.title="Mattermore" \
      org.opencontainers.image.source="https://github.com/franticplant/mattermore" \
      org.opencontainers.image.revision="${SOURCE_REVISION}" \
      org.opencontainers.image.version="${VERSION}" \
      org.opencontainers.image.created="${CREATED}" \
      dev.mattermore.upstream.server="${SERVER_COMMIT}" \
      dev.mattermore.upstream.calls="${CALLS_COMMIT}" \
      org.opencontainers.image.licenses="AGPL-3.0-only" \
      org.opencontainers.image.description="Mattermore: patched Mattermost server, webapp and Calls; third-party licenses in /mattermost"
ENV PATH=/mattermost/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
    SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt \
    MM_SERVICESETTINGS_ENABLELOCALMODE=true MM_INSTALL_TYPE=docker \
    MM_PREPACKAGED_PLUGINS_SKIP=mattermost-plugin-calls-,mattermost-plugin-playbooks- \
    MM_CALLS_GROUP_CALLS_ALLOWED=true
WORKDIR /mattermost
USER 2000:2000
EXPOSE 8065 8067 8074 8443/udp
ENTRYPOINT ["/mattermost/bin/mattermost"]

FROM runtime AS minimal
FROM runtime AS alpine
FROM runtime AS ubi
FROM runtime AS ubi-micro
FROM runtime AS debug

# Independent binary reproduction compares this export, not attestation bytes
# or potentially nondeterministic JavaScript/plugin archives.
FROM scratch AS binary
COPY --from=server-binary /out/mattermore-server /mattermore-server
