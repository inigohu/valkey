FROM gcr.io/distroless/static@sha256:c6d5981545ce1406d33e61434c61e9452dad93ecd8397c41e89036ef977a88f4
COPY bin/valkey-linux-amd64 /usr/local/bin/valkey
CMD ["valkey"]
