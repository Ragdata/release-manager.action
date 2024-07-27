FROM bash:alpine3.20

# install essential utilities
RUN apk -U upgrade && apk add --no-cache git yq-go

COPY scripts /usr/local/bin/scripts
COPY entrypoint.sh /usr/local/bin/entrypoint.sh

RUN chmod +x /usr/local/bin/entrypoint.sh && chmod -R +x /usr/local/bin/scripts

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
