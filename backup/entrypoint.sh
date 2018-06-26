#!/usr/bin/env bash

function upload_dir {
    FROM=$1
    TO=$2
    echo "Uploading dir from $FROM to $TO"
    aws s3 sync "${FROM}" "s3://${TO}" --quiet
}

function clear_dir {
    PATH=$1
    echo "Clearing dir s3://${PATH}"
    aws s3 rm "s3://${PATH}" --recursive
}

function backup_partition {
    PARTITION=$1
    KEY=$2

    clear_dir "${S3_BACKUPS_BUCKET}/${PARTITION}/${KEY}"

    read -r -a array <<< "${TABLES}"
    for TABLE in "${array[@]}"; do
        echo "Backuping table ${TABLE}"
        echo "SQL: ALTER TABLE ${TABLE} FREEZE PARTITION '${PARTITION}'"
        echo "ALTER TABLE ${TABLE} FREEZE PARTITION '${PARTITION}'" | POST "http://${USERNAME}:${PASSWORD}@localhost:8123/"

        CURRENT_NUMBER=$(cat ${BACKUP_PATH}/increment.txt)
        upload_dir "${BACKUP_PATH}/${CURRENT_NUMBER}" "${S3_BACKUPS_BUCKET}/${PARTITION}/${KEY}"
    done
}

function clear_backup_dir {
    echo "REMOVING ALL IN ${BACKUP_PATH}/*"
    rm -rf "${BACKUP_PATH}/*"
}

function main {
    DAY=$(date +"%d")
    YEAR=$(date +"%Y")
    MONTH=$(date +"%m")
    echo "Current date: ${DAY}/${MONTH}/${YEAR}"

    if [[ ${FULL_BACKUP} == 0 ]]; then
        if [[ ${DAY} = "${DAY_TO_UPDATE_LAST_MONTH}" ]]; then
            backup_partition $(date -d "-1 month" +"%Y%m") "full"
        fi
        backup_partition $(date +"%Y%m") ${DAY}
    else
        for CUR_YEAR in $(seq ${START_YEAR} ${YEAR}); do
            for CUR_MONTH in 01 02 03 04 05 06 07 08 09 10 11 12; do
                if [[ ${CUR_YEAR} =  ${YEAR} && ${CUR_MONTH} = ${MONTH} ]]; then
                    backup_partition "${CUR_YEAR}${CUR_MONTH}" ${DAY}
                    break
                fi
                backup_partition "${CUR_YEAR}${CUR_MONTH}" "full"
            done
        done
    fi

    clear_backup_dir
}

main

