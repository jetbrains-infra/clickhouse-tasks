#!/usr/bin/env bash
if [[ ${RESYNC} == 0 ]]; then
    aws s3 sync  "s3://${BACKUP_PROD}" "s3://${BACKUP_STAGING}"
else
    aws s3 sync  "s3://${BACKUP_PROD}" "s3://${BACKUP_STAGING}" --delete
fi