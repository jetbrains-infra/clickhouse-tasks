#!/usr/bin/env bash

function upload_dir {
    FROM=$1
    TO=$2
    echo "Uploading dir from $FROM to $TO"
    aws s3 sync "${FROM}" "s3://${TO}" --quiet --delete
}

function backup_partition {
    TABLE=$1
    PARTITION=$2
    KEY=$3

    echo "Backuping table ${TABLE}"
    echo "SQL: ALTER TABLE ${TABLE} FREEZE PARTITION '${PARTITION}'"
    echo "ALTER TABLE ${TABLE} FREEZE PARTITION '${PARTITION}'" | POST "http://${USERNAME}:${PASSWORD}@localhost:8123/"

    CURRENT_NUMBER=$(cat ${BACKUP_PATH}/increment.txt)
    upload_dir "${BACKUP_PATH}/${CURRENT_NUMBER}" "${S3_BACKUPS_BUCKET}/${PARTITION}/${KEY}"
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
        FS=', ' read -r -a array <<< "$TABLES"
        for TABLE in "${array[@]}"; do
            if [[ ${DAY} = "${DAY_TO_UPDATE_LAST_MONTH}" ]]; then
                backup_partition ${TABLE} $(date -d "-1 month" +"%Y%m") "full"
            fi
            backup_partition ${TABLE} $(date +"%Y%m") ${DAY}
        done
    else
        for CUR_YEAR in $(seq ${START_YEAR} ${YEAR}); do
            for CUR_MONTH in 01 02 03 04 05 06 07 08 09 10 11 12; do
                if [[ ${CUR_YEAR} =  ${YEAR} && ${CUR_MONTH} = ${MONTH} ]]; then
                    FS=', ' read -r -a array <<< "$TABLES"
                    for TABLE in "${array[@]}"; do
                        backup_partition ${TABLE} "${CUR_YEAR}${CUR_MONTH}" ${DAY}
                    done
                    break
                fi
                FS=', ' read -r -a array <<< "$TABLES"
                for TABLE in "${array[@]}"; do
                    backup_partition ${TABLE} "${CUR_YEAR}${CUR_MONTH}" "full"
                done
            done
        done
    fi

    clear_backup_dir
}

main

