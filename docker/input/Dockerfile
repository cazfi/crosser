
# Dockerfile for crosser building container
#
# (c) 2023-2024 Marko Lindqvist
#
# This program is licensed under Gnu General Public License version 2.
#

FROM ubuntu:noble

MAINTAINER Marko Lindqvist

RUN DEBIAN_FRONTEND=noninteractive apt-get update && \
    DEBIAN_FRONTEND=noninteractive apt-get upgrade --yes && \
    DEBIAN_FRONTEND=noninteractive apt-get clean --yes

RUN mkdir /build

COPY entry.sh crosser_build.sh debian.sh /build/

RUN DEBIAN_FRONTEND=noninteractive /build/debian.sh

ARG CROSSER_UID
# uid 1000 is already user "ubuntu"
RUN if test "${CROSSER_UID}" != "1000" ; then \
    adduser --gecos "" --uid ${CROSSER_UID} --disabled-password crosser && \
    echo "crosser" > /build/username.txt ; else echo "ubuntu" > /build/username.txt ; fi

WORKDIR /build

ENTRYPOINT ["/build/entry.sh", "-c", "--"]
