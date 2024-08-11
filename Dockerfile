FROM bash:alpine3.20

RUN apk -U upgrade && apk add --no-cache git curl yq-go envsubst

COPY cfg			/usr/local/share/cfg
COPY .archive/src			/usr/local/bin/src
COPY .archive/entrypoint.sh	/usr/local/bin/entrypoint.sh

RUN chmod +x /usr/local/bin/entrypoint.sh && chmod -R +x /usr/local/bin/src

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
