# Use official Golang image as build stage
FROM golang:1.21 as builder
WORKDIR /app
COPY . .
RUN cd cmd && go build -o file-uploader main.go

# Use a minimal image for running
FROM ubuntu:22.04
WORKDIR /app
COPY --from=builder /app/cmd/file-uploader ./file-uploader
COPY files ./files

# Install AWS CLI
RUN apt-get update && \
    apt-get install -y curl unzip && \
    curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip" && \
    unzip awscliv2.zip && \
    ./aws/install && \
    rm -rf awscliv2.zip aws

ENV PATH="/usr/local/bin:$PATH"

CMD ["/app/file-uploader"]
