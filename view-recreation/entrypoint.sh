#!/usr/bin/env bash

function load_file {
    local FROM=$1
    local TO=$2

    echo "Loading file from s3://${FROM} to ${TO}"
    aws s3 sync "s3://${FROM}" "${TO}" --quiet
}

function drop_table {
    local TABLE=$1

    echo "SQL: DROP TABLE ${TABLE}"
    curl --data "DROP TABLE ${TABLE}" "http://${USERNAME}:${PASSWORD}@localhost:8123/"
}

function create_table {
    local TABLE=$1

    echo "Loading init sql for ${TABLE}"
    load_file "${S3_CONFIGS_BUCKET}/${TABLE}.sql" "${TABLE}.sql"
    STATEMENT=$(cat "${TABLE}.sql")
    STATEMENT=$(echo ${STATEMENT} | sed s/'${ID}'/"${ID}"/g)
    curl --data "${STATEMENT}" "http://${USERNAME}:${PASSWORD}@localhost:8123/"
    echo "Init sql executed"
}

function main {
    local ID=$(cat ${ID_PATH})
    update_conf

    echo "Node ID is ${ID}"

    echo "Starting waiting for recreation"
    until $(curl --output /dev/null --silent --head --fail http://localhost:8123); do
        echo 'Waiting Clickhouse to deploy'
        sleep 5
    done
    echo "Recreating tables in  Clickhouse"

    read -r -a array <<< "$TABLES"
    for TABLE in "${array[@]}"
    do
        IS_EXISTS=$(curl --data "EXISTS ${TABLE}" "http://${USERNAME}:${PASSWORD}@localhost:8123/")
        echo "Is exists ${TABLE} = ${IS_EXISTS}"
        if [[ ${IS_EXISTS} = "1" ]]; then
            drop_table ${TABLE}
        fi
        create_table ${TABLE}
    done

    echo "Done recreating table in Clickhouse"
}

main
