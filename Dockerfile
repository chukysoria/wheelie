ARG DISTRO
ARG DISTROVER
ARG ARCH

FROM ghcr.io/chukysoria/baseimage-${DISTRO}:${ARCH}-${DISTROVER} as builder

ARG DISTRO
ARG DISTROVER
ARG ARCH

# grpcio build args
ARG GRPC_BUILD_WITH_BORING_SSL_ASM=false
ARG GRPC_PYTHON_BUILD_SYSTEM_OPENSSL=true 
ARG GRPC_PYTHON_BUILD_WITH_CYTHON=true 
ARG GRPC_PYTHON_DISABLE_LIBC_COMPATIBILITY=true

RUN \
  echo "**** Installing dependencies ****" && \
  if [ -f /usr/bin/apt ]; then \
    echo "**** Detected Ubuntu ****" && \
    apt-get update && \
    apt-get install --no-install-recommends -y \
      cargo \
      cmake \
      g++ \
      git \
      libffi-dev \
      libglib2.0-dev \
      libjpeg-dev \
      libssl-dev \
      libwebp-dev \
      libxml2-dev \
      libxslt1-dev \
      make \
      patchelf \
      python3-dev \
      python3-pip \
      python3-venv \
      zlib1g-dev; \
  else \
    echo "**** Detected Alpine ****" && \
    apk add --no-cache --virtual=build-dependencies \
      cargo \
      cmake \
      g++ \
      gcc \
      geos-dev \
      git \
      glib-dev \
      jpeg-dev \
      libffi-dev \
      libwebp-dev \
      libxml2-dev \
      libxslt-dev \
      make \
      musl-dev \
      openssl-dev \
      patchelf \
      pkgconfig \
      py3-pip \
      python3-dev \
      zlib-dev; \
  fi && \
  echo "**** Updating pip and building wheels ****" && \
  if [ "${DISTRO}" = "alpine" ]; then \
    INDEXDISTRO="${DISTRO}-${DISTROVER}"; \
  else \
    INDEXDISTRO="${DISTRO}"; \
  fi && \
  python3 -m venv /build-env && \
  . /build-env/bin/activate && \
  pip install -U pip setuptools wheel "cython<3" auditwheel

ARG PACKAGES
COPY packages.txt /packages.txt
RUN \
  . /build-env/bin/activate && \
  mkdir -p /build && \
  if [ -z "${PACKAGES}" ]; then \
    PACKAGES=$(cat /packages.txt); \
  fi && \
  # ignore official arm32v7 wheel of grpcio and wrapt
  if [ "${DISTRO}" = "alpine" ] && [ "${ARCH}" = "arm32v7" ]; then \
    GRPCIOSKIP="--no-binary grpcio"; \
  else \
    GRPCIOSKIP=""; \
  fi && \
  if [ "${ARCH}" = "arm32v7" ]; then \
    WRAPTNATIVE="--no-binary wrapt" && \
    NUMPYBLAS='--config-settings=setup-args="-Dallow-noblas=true"' ; \
  else \
    WRAPTNATIVE="" && \
    NUMPYBLAS=""; \
  fi && \
  pip wheel --wheel-dir=/build --extra-index-url="https://gitlab.com/api/v4/projects/49075787/packages/pypi/simple" \
  --no-cache-dir -v ${GRPCIOSKIP} ${WRAPTNATIVE} \
    $NUMPYBLAS ${PACKAGES} && \
  echo "**** Wheels built are: ****" && \
  ls /build && \
  echo "**** Reparing built wheels ****" && \
  mkdir -p /build-repaired && \
  WHEEL_FILES="$(ls /build/*)"; \
  for wheel_file in ${WHEEL_FILES}; do \
    case "${wheel_file}" in \
      *"musllinux"*|*"none-any"*) \
        mv "${wheel_file}" "/build-repaired/" ;; \
      *) \
        auditwheel repair -w "/build-repaired" "${wheel_file}" || mv "${wheel_file}" "/build-repaired/";; \
    esac; \
  done && \
  echo "**** Wheels to export are: ****" && \
  ls /build-repaired

FROM scratch as artifacts

COPY --from=builder /build-repaired /build
