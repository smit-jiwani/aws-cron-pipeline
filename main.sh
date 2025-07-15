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

# ====== DEBUG: PRINT ENVIRONMENT VARIABLES (SAFELY) ======
log "🔍 DEBUG: Checking environment variables..."
log "AWS_ACCESS_KEY_ID: ${AWS_ACCESS_KEY_ID:0:10}..." # Only show first 10 chars
log "AWS_SECRET_ACCESS_KEY: ${AWS_SECRET_ACCESS_KEY:0:10}..." # Only show first 10 chars
log "AWS_DEFAULT_REGION: ${AWS_DEFAULT_REGION}"
log "S3_BUCKET: ${S3_BUCKET}"

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

# ====== DEBUG: CHECK AWS CLI VERSION ======
log "🔍 DEBUG: AWS CLI version:"
aws --version

# ====== DEBUG: CHECK AWS CONFIGURATION ======
log "🔍 DEBUG: AWS configuration check:"
aws configure list

# ====== VERIFY AWS CREDENTIALS WITH DETAILED ERROR ======
log "🔐 Verifying AWS credentials..."

# Test with more verbose output
aws_test_output=$(aws sts get-caller-identity 2>&1)
aws_test_exit_code=$?

if [[ $aws_test_exit_code -eq 0 ]]; then
    log "✅ AWS credentials verified successfully."
    log "🔍 AWS Identity: $aws_test_output"
else
    log "❌ ERROR: AWS credentials test failed with exit code: $aws_test_exit_code"
    log "❌ AWS Error Output: $aws_test_output"
    
    # Additional debugging
    log "🔍 DEBUG: Environment variables check:"
    env | grep AWS | while read line; do
        if [[ $line == *"KEY"* ]]; then
            # Mask sensitive keys
            echo "${line:0:20}..."
        else
            echo "$line"
        fi
    done
    
    log "🔍 DEBUG: Trying to test S3 access directly:"
    aws s3 ls 2>&1 | head -5
    
    exit 1
fi

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

# ====== DEBUG: TEST S3 BUCKET ACCESS FIRST ======
log "🔍 DEBUG: Testing S3 bucket access..."
if aws s3 ls "s3://${S3_BUCKET}" --max-items 1 &> /dev/null; then
    log "✅ S3 bucket access confirmed."
else
    log "❌ ERROR: Cannot access S3 bucket: ${S3_BUCKET}"
    log "🔍 DEBUG: Trying to list all buckets:"
    aws s3 ls
    exit 1
fi

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