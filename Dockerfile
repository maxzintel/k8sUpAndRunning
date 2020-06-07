# NOTE THIS IS AN EXAMPLE DOCKERFILE FOR DEMO CONTAINER KUARD.
# BUILDING THIS WILL NOT WORK WITHOUT THE ACTUAL DEMO APP CODE.
# Stage 1: Build
FROM golang:1.11-alpine AS build

# Install Node and NPM
RUN apk update && apk upgrade && apk add --no-cache git nodejs bash npm

# Get dependencies for Go and part of build
RUN go get -u github.com/jteeuwen/go-bindata/...
RUN go get github.com/tools/godep

WORKDIR /go/src/github.com/kubernetes-up-and-running/kuard

# Copy all sources into WorkDir
COPY . .

# Set of env vars that the build expects
ENV verbose=0
ENV PKG=github.com/kubernetes-up-and-running/kuard
ENV ARCH=amd64
ENV version=test

# Do the build. Script is part of incoming sources.
RUN build/build.sh

# Stage 2: Deployment.
FROM alpine

USER nobody:nobody
COPY --from=build /go/bin/kuard /kuard

CMD [ "/kuard" ]