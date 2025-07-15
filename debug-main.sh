#!/bin/bash

# ====== LOGGING FUNCTION ======
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

# ====== SETUP ======
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$SCRIPT_DIR/.env"
LOG_FILE="$SCRIPT_DIR/logs/upload.log"

mkdir -p "$SCRIPT_DIR/logs"

log "🚀 Starting S3 upload script..."
log "🔧 Loading environment variables..."

# Load .env
if [[ -f "$ENV_FILE" ]]; then
    set -o allexport
    source "$ENV_FILE"
    set +o allexport
    log "✅ Environment variables loaded from .env file."
else
    log "ℹ️ No .env file found. Using environment variables from shell."
fi

# ====== DEBUG: Print environment variables (safely) ======
log "🔍 DEBUG: Checking environment variables..."
log "AWS_ACCESS_KEY_ID: ${AWS_ACCESS_KEY_ID:0:10}..."
log "AWS_SECRET_ACCESS_KEY: ${AWS_SECRET_ACCESS_KEY:0:10}..."
log "AWS_DEFAULT_REGION: ${AWS_DEFAULT_REGION}"
log "S3_BUCKET: ${S3_BUCKET}"
log "S3_PREFIX: ${S3_PREFIX}"
log "SOURCE_DIR: ${SOURCE_DIR}"
log "VERIFY_UPLOAD: ${VERIFY_UPLOAD}"

# ====== VALIDATE REQUIRED VARIABLES ======
required_vars=(
    "AWS_ACCESS_KEY_ID"
    "AWS_SECRET_ACCESS_KEY"
    "AWS_DEFAULT_REGION"
    "S3_BUCKET"
)

SOURCE_DIR="${SOURCE_DIR:-$SCRIPT_DIR/files}"
S3_PREFIX="${S3_PREFIX:-uploads}"
VERIFY_UPLOAD="${VERIFY_UPLOAD:-true}"

for var in "${required_vars[@]}"; do
    if [[ -z "${!var}" ]]; then
        log "❌ ERROR: Missing $var environment variable"
        exit 1
    fi
done

log "✅ All required environment variables are set."

# ====== AWS CLI Check ======
if ! command -v aws &> /dev/null; then
    log "❌ ERROR: AWS CLI not installed. Please install it first."
    exit 1
fi

log "🔍 AWS CLI version:"
aws --version

log "🔍 AWS configuration check:"
aws configure list

log "🔍 DEBUG: AWS environment used:"
env | grep AWS_

# ====== VERIFY AWS CREDENTIALS ======
log "🔐 Verifying AWS credentials..."
log "🔍 DEBUG: Running 'aws sts get-caller-identity'..."
aws_test_output=$(aws sts get-caller-identity --region "$AWS_DEFAULT_REGION" 2>&1)
aws_test_exit_code=$?

if [[ $aws_test_exit_code -eq 0 ]]; then
    log "✅ AWS credentials verified successfully."
    log "🔍 AWS Identity: $aws_test_output"
else
    log "❌ ERROR: AWS credentials test failed with exit code: $aws_test_exit_code"
    log "❌ AWS Error Output: $aws_test_output"
    log "⚠️ DEBUG: You may want to recheck your secret key or region configuration."
    exit 1
fi

# ====== CHECK SOURCE DIRECTORY ======
if [[ ! -d "$SOURCE_DIR" ]]; then
    log "❌ ERROR: SOURCE_DIR '$SOURCE_DIR' does not exist."
    exit 1
fi

if [[ -z "$(ls -A "$SOURCE_DIR")" ]]; then
    log "❌ ERROR: SOURCE_DIR '$SOURCE_DIR' is empty. Nothing to upload."
    exit 1
fi

# ====== PREPARE S3 DESTINATION ======
s3_prefix="${S3_PREFIX}"
s3_destination="s3://${S3_BUCKET}/${s3_prefix}"

log "📂 Source: $SOURCE_DIR"
log "☁️ Destination: $s3_destination"

file_count=$(find "$SOURCE_DIR" -type f | wc -l)
log "📄 Files to upload: $file_count"

log "🔍 DEBUG: Final S3 destination path is:"
log "aws s3 cp \"$SOURCE_DIR\" \"$s3_destination\" --recursive --storage-class STANDARD_IA"

# ====== TEST S3 BUCKET ACCESS (improved with s3api) ======
log "🔍 Testing S3 bucket access..."
bucket_check_output=$(aws s3api list-objects --bucket "$S3_BUCKET" --max-items 1 --region "$AWS_DEFAULT_REGION" 2>&1)
if [[ $? -eq 0 ]]; then
    log "✅ S3 bucket access confirmed."
else
    log "❌ ERROR: Cannot access S3 bucket: ${S3_BUCKET}"
    log "❌ AWS Error Output:"
    echo "$bucket_check_output"
    exit 1
fi

# ====== UPLOAD TO S3 ======
log "⬆️ Uploading files..."
log "🔍 DEBUG: Upload command: aws s3 cp \"$SOURCE_DIR\" \"$s3_destination\" --recursive --storage-class STANDARD_IA"

if aws s3 cp "$SOURCE_DIR" "$s3_destination" --recursive --storage-class STANDARD_IA --region "$AWS_DEFAULT_REGION" 2>&1 | tee -a "$LOG_FILE"; then
    log "✅ Upload completed successfully."
    log "🔗 S3 Location: $s3_destination"

    if [[ "${VERIFY_UPLOAD}" == "true" ]]; then
        log "🔍 Verifying upload contents..."
        aws s3 ls "$s3_destination" --recursive --human-readable --summarize --region "$AWS_DEFAULT_REGION" | tee -a "$LOG_FILE"
    fi

    log "📊 Upload summary logged to: $LOG_FILE"
    exit 0
else
    log "❌ Upload failed. Check log file at $LOG_FILE"
    exit 1
fi
