
# Dockerfile for crosser building container
#
# (c) 2023 Marko Lindqvist
#
# This program is licensed under Gnu General Public License version 2.
#

FROM debian:bookworm

MAINTAINER Marko Lindqvist

RUN DEBIAN_FRONTEND=noninteractive apt-get update && \
    DEBIAN_FRONTEND=noninteractive apt-get upgrade --yes && \
    DEBIAN_FRONTEND=noninteractive apt-get clean --yes

RUN mkdir /build

COPY entry.sh crosser_build.sh debian.sh /build/

RUN DEBIAN_FRONTEND=noninteractive /build/debian.sh

ARG CROSSER_UID

RUN adduser --gecos "" --uid ${CROSSER_UID} --disabled-password crosser

WORKDIR /build

ENTRYPOINT ["/build/entry.sh", "-c", "--"]
