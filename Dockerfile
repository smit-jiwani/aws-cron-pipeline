# Use Ubuntu as base image
FROM ubuntu:22.04

WORKDIR /app

# Install required packages
RUN apt-get update && \
    apt-get install -y \
    curl \
    unzip \
    bash \
    findutils \
    && rm -rf /var/lib/apt/lists/*

# Install AWS CLI
RUN curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip" && \
    unzip awscliv2.zip && \
    ./aws/install && \
    rm -rf awscliv2.zip aws

# Copy the upload script and files
COPY main.sh ./main.sh
COPY .env ./.env
COPY files ./files

# Make the script executable
RUN chmod +x ./main.sh

# Set environment variables
ENV PATH="/usr/local/bin:$PATH"

# Run the upload script
CMD ["./main.sh"]