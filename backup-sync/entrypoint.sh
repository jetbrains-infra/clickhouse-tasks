#!/usr/bin/env bash
aws s3 sync  "s3://${BACKUP_PROD}" "s3://${BACKUP_STAGING}" --delete
