#!/usr/bin/env bash

function clear_dir {
    read -r -a array <<< "$TABLES"
    for TABLE in "${array[@]}"; do
        rm -rf "${CLICKHOUSE_DATA_PATH}/${DATABASE}/${TABLE}/detached/"*
    done
}

function drop_partition {
    local TABLE=$1
    local PARTITION=$2
    local ADDRESS=$3

    echo "SQL: ALTER TABLE ${TABLE} DROP PARTITION '${PARTITION}'"
    echo "ALTER TABLE ${TABLE} DROP PARTITION '${PARTITION}'" | POST "http://${USERNAME}:${PASSWORD}@${ADDRESS}:8123/"
}

function truncate_table {
    local TABLE=$1

    echo "Truncating table ${TABLE}"

    for i in `seq 1 ${NUMBER_INSTANCES}`; do
        local ADDRESS="${INSTANCE_NAME}${i}.${ZONE_NAME}"
        local IS_LEADER=$(echo "select is_leader from system.replicas where table = '$TABLE'" | POST "http://${USERNAME}:${PASSWORD}@${ADDRESS}:8123/")
        if [[ ${IS_LEADER} = "1" ]]; then
            for CUR_YEAR in $(seq ${START_YEAR} ${YEAR}); do
                for CUR_MONTH in 01 02 03 04 05 06 07 08 09 10 11 12; do
                    drop_partition ${TABLE} "${CUR_YEAR}${CUR_MONTH}" ${ADDRESS}
                done
            done
        fi
    done

    echo "Table truncated"
}

function load_file {
    local FROM=$1
    local TO=$2
    echo "Loading file from s3://${FROM} to ${TO}"
    aws s3 sync "s3://${FROM}" "${TO}" --quiet
}

function attach_partition {
    local TABLE=$1
    local PARTITION=$2
    local KEY=$3

    load_file "${S3_BACKUPS_BUCKET}/${PARTITION}/${KEY}/data/${DATABASE}/${TABLE}" "${CLICKHOUSE_DATA_PATH}/${DATABASE}/${TABLE}/detached"

    chown -R 105:106 "${CLICKHOUSE_DATA_PATH}/${DATABASE}/${TABLE}/detached"
    echo "SQL: ALTER TABLE ${TABLE} ATTACH PARTITION '${PARTITION}'"
    echo "ALTER TABLE ${TABLE} ATTACH PARTITION '${PARTITION}'" | POST "http://${USERNAME}:${PASSWORD}@localhost:8123/"
}

function main {
    if [[ ${EXECUTE_SCRIPT} == 0 ]]; then
        exit
    fi

    clear_dir

    read -r -a array <<< "$TABLES"
    for TABLE in "${array[@]}"; do
        truncate_table ${TABLE}
    done

    for CUR_YEAR in $(seq ${START_YEAR} ${YEAR}); do
        for CUR_MONTH in 01 02 03 04 05 06 07 08 09 10 11 12; do
            if [[ ${CUR_YEAR} =  ${YEAR} && ${CUR_MONTH} = ${MONTH} ]]; then
                read -r -a array <<< "$TABLES"
                for TABLE in "${array[@]}"; do
                    attach_partition ${TABLE} $(date -d "-1 day" +"%Y%m") $(date -d "-1 day" +"%d")
                done
                break
            fi

            read -r -a array <<< "$TABLES"
            for TABLE in "${array[@]}"; do
                attach_partition ${TABLE} "${CUR_YEAR}${CUR_MONTH}" "full"
            done
        done
    done
}

YEAR=$(date +"%Y")
MONTH=$(date +"%m")
DAY=$(date +"%d")

main
