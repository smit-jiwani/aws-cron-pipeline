#!/bin/bash

# ====== LOGGING FUNCTION ======
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

# ====== DOCKER-OPTIMIZED SETUP ======
SCRIPT_DIR="/app"
ENV_FILE="$SCRIPT_DIR/.env"
LOG_FILE="$SCRIPT_DIR/logs/upload.log"

# Create logs directory if it doesn't exist
mkdir -p "$SCRIPT_DIR/logs"

log "🐳 Starting S3 upload in Docker container..."
log "🔧 Loading environment variables..."

# Load .env file if it exists, otherwise use environment variables
if [[ -f "$ENV_FILE" ]]; then
    set -o allexport
    source "$ENV_FILE"
    set +o allexport
    log "✅ Environment variables loaded from .env file."
else
    log "ℹ️ Using environment variables from Docker."
fi

# ====== VALIDATE REQUIRED VARIABLES ======
required_vars=(
    "AWS_ACCESS_KEY_ID"
    "AWS_SECRET_ACCESS_KEY" 
    "AWS_DEFAULT_REGION"
    "S3_BUCKET"
)

# Set default values for Docker environment
SOURCE_DIR="${SOURCE_DIR:-/app/files}"
S3_PREFIX="${S3_PREFIX:-uploads}"
VERIFY_UPLOAD="${VERIFY_UPLOAD:-true}"

for var in "${required_vars[@]}"; do
    if [[ -z "${!var}" ]]; then
        log "❌ ERROR: Missing $var environment variable"
        exit 1
    fi
done

log "✅ All required environment variables are set."

# ====== CHECK AWS CLI ======
if ! command -v aws &> /dev/null; then
    log "❌ ERROR: AWS CLI not installed."
    exit 1
fi

# ====== VERIFY AWS CREDENTIALS ======
log "🔐 Verifying AWS credentials..."
if ! aws sts get-caller-identity &> /dev/null; then
    log "❌ ERROR: AWS credentials are invalid or expired."
    log "Please check your AWS_ACCESS_KEY_ID: ${AWS_ACCESS_KEY_ID}, AWS_SECRET_ACCESS_KEY: ${AWS_SECRET_ACCESS_KEY}, and AWS_DEFAULT_REGION: ${AWS_DEFAULT_REGION}, AWS_URL: ${S3_BUCKET}."
    exit 1
fi
log "✅ AWS credentials verified."

# ====== CHECK SOURCE DIRECTORY ======
if [[ ! -d "$SOURCE_DIR" ]]; then
    log "❌ ERROR: SOURCE_DIR '$SOURCE_DIR' does not exist or is not a directory."
    exit 1
fi

# ====== CHECK IF SOURCE DIR IS EMPTY ======
if [[ ! "$(ls -A "$SOURCE_DIR")" ]]; then
    log "❌ ERROR: SOURCE_DIR '$SOURCE_DIR' is empty. Nothing to upload."
    exit 1
fi

# ====== PREPARE S3 PATH ======
timestamp=$(date +%s)
s3_prefix="${S3_PREFIX}/${timestamp}"
s3_destination="s3://${S3_BUCKET}/${s3_prefix}"

# ====== UPLOAD ======
log "🚀 Starting upload..."
log "📂 Source: $SOURCE_DIR"
log "☁️ Destination: $s3_destination"

# Count files to upload
file_count=$(find "$SOURCE_DIR" -type f | wc -l)
log "📄 Files to upload: $file_count"

# Perform the upload with progress and error handling
if aws s3 cp "$SOURCE_DIR" "$s3_destination" --recursive --storage-class STANDARD_IA 2>&1 | tee -a "$LOG_FILE"; then
    log "✅ Upload completed successfully."
    log "🔗 S3 Location: $s3_destination"
    
    # Optional: List uploaded files for verification
    if [[ "${VERIFY_UPLOAD}" == "true" ]]; then
        log "🔍 Verifying upload..."
        aws s3 ls "$s3_destination" --recursive --human-readable --summarize | tee -a "$LOG_FILE"
    fi
    
    log "🎉 All files uploaded successfully!"
    log "📊 Upload summary logged to: $LOG_FILE"
    
    # Container will exit with success code
    exit 0
else
    log "❌ Upload failed. Check $LOG_FILE for details."
    exit 1
fi