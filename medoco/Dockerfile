# Builds the patched Orthanc from *this* checkout and packages the binary.
#
# This image is the only thing this fork publishes. What consumes it, and how it
# gets deployed, is not this repository's business: a consumer copies the binary
# out of this image and does whatever it needs with it.
#
# Do not run `docker build` against this file by hand -- use ./medoco/build.sh,
# which refuses to build a dirty tree and derives the version for you.
#
# RESOURCES: the static build compiles Boost, DCMTK, OpenSSL and protobuf from
# source. Budget roughly 15 GB of free Docker storage and an hour. JOBS is capped
# at 4 rather than $(nproc) on purpose: an unbounded -j exhausted the disk and
# wedged the build machine during the link step.

# Ubuntu 26.04, because a statically linked binary still links glibc dynamically:
# building here keeps it compatible with anything running that release or newer.
# Raise this only in step with whatever the binary is deployed into.
FROM ubuntu:26.04 AS build

ARG JOBS=4
ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
      build-essential cmake ca-certificates \
      python3 unzip patch pkg-config uuid-dev \
    && rm -rf /var/lib/apt/lists/*

COPY . /src

# A static build, so the binary carries its own third-party dependencies and can
# be dropped into an image it was not built in. Plugins are not rebuilt: they load
# through Orthanc's versioned C API, so existing ones keep working for as long as
# the upstream Orthanc version is unchanged.
WORKDIR /build
RUN cmake /src/OrthancServer \
      -DCMAKE_BUILD_TYPE=Release \
      -DSTATIC_BUILD=ON \
      -DALLOW_DOWNLOADS=ON \
      -DUSE_SYSTEM_civetweb=OFF \
    && make -j"${JOBS}" Orthanc \
    && strip /build/Orthanc


FROM ubuntu:26.04

ARG VERSION
ARG REVISION

# The source label is what discharges the GPLv3 obligation in practice: anyone
# holding this image can find the exact commit it was built from.
LABEL org.opencontainers.image.title="Orthanc (medoco build)" \
      org.opencontainers.image.description="Orthanc with the medoco C-Get transfer syntax patch" \
      org.opencontainers.image.source="https://github.com/medoco-health/OrthancMirror" \
      org.opencontainers.image.revision="${REVISION}" \
      org.opencontainers.image.version="${VERSION}" \
      org.opencontainers.image.licenses="GPL-3.0-or-later"

COPY --from=build /build/Orthanc /usr/local/sbin/Orthanc

# So that `docker run --rm <image>` reports what a tag actually contains, which
# is the quickest way to check that a deployed tag is the build you think it is.
ENTRYPOINT ["/usr/local/sbin/Orthanc"]
CMD ["--version"]
