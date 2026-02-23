ARG DEBIAN_VERSION=bookworm

# ---------- build stage ----------
FROM debian:${DEBIAN_VERSION}-slim AS build

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    apt-get update && \
    apt-get install -y --no-install-recommends build-essential git cmake libssl-dev ca-certificates

WORKDIR /build

RUN git clone --depth 1 --branch feat-jina-v5-text \
    https://github.com/jina-ai/llama.cpp.git .

RUN cmake -S . -B out -DCMAKE_BUILD_TYPE=Release \
    -DGGML_NATIVE=OFF \
    -DLLAMA_BUILD_TESTS=OFF && \
    cmake --build out -j $(nproc)

RUN mkdir -p /app/lib && \
    cp out/bin/llama-server /app/ && \
    find out/bin -name "*.so*" -exec cp -P {} /app/lib/ \;

# ---------- runtime stage ----------
FROM debian:${DEBIAN_VERSION}-slim AS server

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    apt-get update && \
    apt-get install -y --no-install-recommends libgomp1 curl ca-certificates && \
    rm -rf /tmp/*

RUN useradd --system --create-home --no-log-init llama
USER llama

COPY --from=build --chown=llama /app/llama-server /app/llama-server
COPY --from=build --chown=llama /app/lib/         /app/lib/

ENV LD_LIBRARY_PATH=/app/lib

WORKDIR /app
ENV LLAMA_ARG_HOST=0.0.0.0

HEALTHCHECK --interval=15s --timeout=5s --start-period=30s --retries=3 \
    CMD ["curl", "-f", "http://localhost:8080/health"]

ENTRYPOINT ["/app/llama-server"]
