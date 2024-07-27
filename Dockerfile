FROM bash:alpine3.20

# install essential utilities
RUN apk -U upgrade && apk add --no-cache git yq-go

COPY scripts /scripts
COPY entrypoint.sh /entrypoint.sh

RUN chmod +x /entrypoint.sh && chmod -R +x /scripts

ENTRYPOINT ["/entrypoint.sh"]
