FROM debian:trixie-slim

RUN apt-get update && \
    apt-get install -y --no-install-recommends apt-cacher-ng ca-certificates && \
    rm -rf /var/lib/apt/lists/* && \
    mkdir -p /var/cache/apt-cacher-ng /var/log/apt-cacher-ng /run/apt-cacher-ng && \
    chown -R apt-cacher-ng:apt-cacher-ng /var/cache/apt-cacher-ng /var/log/apt-cacher-ng /run/apt-cacher-ng

USER apt-cacher-ng

EXPOSE 3142

ENTRYPOINT ["/usr/sbin/apt-cacher-ng", "-c", "/etc/apt-cacher-ng", "ForeGround=1"]
