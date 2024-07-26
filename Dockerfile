FROM bash:alpine3.20

# install git
RUN apk -U upgrade && apk add git --no-cache

COPY entrypoint.sh /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
