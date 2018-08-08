#!/usr/bin/env bash

function load_file {
    local FROM=$1
    local TO=$2

    echo "Loading file from s3://${FROM} to ${TO}"
    aws s3 cp "s3://${FROM}" ${TO}
}

function drop_table {
    local TABLE=$1
    local ADDRESS=$2

    echo "SQL: DROP TABLE ${TABLE}"
    curl --data "DROP TABLE ${TABLE}" "http://${USERNAME}:${PASSWORD}@${ADDRESS}:8123/"
}

function create_table {
    local TABLE=$1
    local ID=$2
    local ADDRESS=$3

    echo "Loading init sql for ${TABLE}"
    load_file "${S3_CONFIGS_BUCKET}/${TABLE}.sql" "${TABLE}.sql"
    STATEMENT=$(cat "${TABLE}.sql")
    STATEMENT=$(echo ${STATEMENT} | sed s/'${ID}'/"${ID}"/g)
    curl --data "${STATEMENT}" "http://${USERNAME}:${PASSWORD}@${ADDRESS}:8123/"
    echo "Init sql executed"
}

function main {
    for i in `seq 1 ${NUMBER_INSTANCES}`; do
        local ADDRESS="${INSTANCE_NAME}${i}.${ZONE_NAME}"
        read -r -a array <<< "$TABLES"
        for TABLE in "${array[@]}"
        do
            IS_EXISTS=$(curl --data "EXISTS ${TABLE}" "http://${USERNAME}:${PASSWORD}@${ADDRESS}:8123/")
            echo "Is exists ${TABLE} = ${IS_EXISTS}"
            if [[ ${IS_EXISTS} = "1" ]]; then
                drop_table ${TABLE} ${ADDRESS}
            fi
            create_table ${TABLE} ${i} ${ADDRESS}
        done
    done

    echo "Done recreating table in Clickhouse"
}

main
