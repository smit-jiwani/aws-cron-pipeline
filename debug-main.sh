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
required_vars=(AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_DEFAULT_REGION S3_BUCKET)

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
aws_test_output=$(aws sts get-caller-identity --region "$AWS_DEFAULT_REGION" 2>&1)
if [[ $? -eq 0 ]]; then
    log "✅ AWS credentials verified successfully."
    log "🔍 AWS Identity: $aws_test_output"
else
    log "❌ ERROR: AWS credentials test failed"
    log "❌ AWS Error Output: $aws_test_output"
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

# ====== FIND LAST MODIFIED FILE ON S3 ======
log "🕵️ Finding latest modified object in S3..."

latest_s3_time=$(aws s3api list-objects-v2 \
    --bucket "$S3_BUCKET" \
    --prefix "$S3_PREFIX/" \
    --query 'Contents[?LastModified!=`null`].[LastModified]' \
    --output text \
    --region "$AWS_DEFAULT_REGION" | sort | tail -n 1)

if [[ -z "$latest_s3_time" ]]; then
    log "ℹ️ No files found in S3. Will upload all files."
    s3_latest_epoch=0
else
    log "🕒 Latest modified time on S3: $latest_s3_time"
    s3_latest_epoch=$(date -d "$latest_s3_time" +%s)
    log "🔢 S3 last modified (epoch): $s3_latest_epoch"
fi

# ====== UPLOAD NEW FILES ONLY ======
log "🚚 Uploading only files with epoch newer than S3 last update..."

uploaded_count=0
skipped_count=0

find "$SOURCE_DIR" -type f | while read -r filepath; do
    # Expect folder structure like: /rms/1721121234/app.log
    epoch_dir=$(echo "$filepath" | awk -F'/' '{for(i=1;i<=NF;i++) if ($i ~ /^[0-9]{10,}$/) print $i}' | head -n 1)

    if [[ -n "$epoch_dir" && "$epoch_dir" =~ ^[0-9]+$ ]]; then
        if [[ "$epoch_dir" -gt "$s3_latest_epoch" ]]; then
            s3_key="${filepath#$SOURCE_DIR/}"
            s3_uri="s3://${S3_BUCKET}/${S3_PREFIX}/${s3_key}"

            log "⬆️ Uploading: $filepath → $s3_uri"
            aws s3 cp "$filepath" "$s3_uri" --storage-class STANDARD_IA --region "$AWS_DEFAULT_REGION" | tee -a "$LOG_FILE"

            if [[ "$VERIFY_UPLOAD" == "true" ]]; then
                log "🔍 Verifying upload: $s3_uri"
                aws s3 ls "$s3_uri" --region "$AWS_DEFAULT_REGION" | tee -a "$LOG_FILE"
            fi

            ((uploaded_count++))
        else
            log "⏩ Skipping old file (epoch=$epoch_dir < $s3_latest_epoch): $filepath"
            ((skipped_count++))
        fi
    else
        log "⚠️ Could not extract valid epoch from path: $filepath"
        ((skipped_count++))
    fi
done

log "✅ Upload process complete."
log "📄 Uploaded files: $uploaded_count"
log "📁 Skipped files: $skipped_count"
log "📊 Upload summary logged to: $LOG_FILE"
