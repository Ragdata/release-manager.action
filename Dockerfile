FROM bash:alpine3.20

# install essential utilities
RUN apk -U upgrade && apk add --no-cache git curl yq-go envsubst

COPY scripts /usr/local/bin/scripts
COPY cfg /usr/local/share/cfg
COPY entrypoint.sh /usr/local/bin/entrypoint.sh

RUN chmod +x /usr/local/bin/entrypoint.sh && \
    chmod -R +x /usr/local/bin/scripts

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
