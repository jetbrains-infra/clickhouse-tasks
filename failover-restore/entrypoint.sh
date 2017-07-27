#!/usr/bin/env bash
echo "Processing files from failover bucket"
touch logs
for file in $(aws s3 ls ${FAILOVER_BUCKET} | awk '{print $4}'); do
    aws s3 cp "s3://${FAILOVER_BUCKET}/${file}" "${file}"
    while IFS='' read -r SQL_STATEMENT || [[ -n "$SQL_STATEMENT" ]]; do
        response=$(curl --data "${SQL_STATEMENT}" --write-out %{http_code} --silent --output logs  http://${USERNAME}:${PASSWORD}@localhost:8123)
        echo "RESULT:"
        cat logs
        if [[ ${response} != "200" ]]; then
            echo "ERROR: ${SQL_STATEMENT}"
        fi
    done < "${file}"
    aws s3 rm "s3://${FAILOVER_BUCKET}/${file}"
done
echo "Files processed"
