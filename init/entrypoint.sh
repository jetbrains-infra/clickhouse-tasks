#!/usr/bin/env bash

function load_file {
    local FROM=$1
    local TO=$2
    echo "Loading file from s3://${FROM} to ${TO}"
    aws s3 cp "s3://${FROM}" ${TO}
}

function update_conf {
    echo "Updating configs"
    load_file "${S3_CONFIGS_BUCKET}/${SERVER_CONFIG}" "${CONFIG_PATH}/config.xml"
    load_file "${S3_CONFIGS_BUCKET}/${USERS_CONFIG}" "${CONFIG_PATH}/users.xml"
    echo "Configs updated"
}

function delete_node_zk {
    local TABLE=$1
    local ID=$2
    echo "Deleting ${TABLE} from Zookeeper."
    for i in `seq 1 ${NUMBER_INSTANCES}`;
        do
            echo "Executing delete all on instance${i}"
            ./zookeeper-3.4.9/bin/zkCli.sh -server "${INSTANCE_NAME}${i}.${ZONE_NAME}" rmr "/clickhouse/tables/${TABLE}/replicas/${ID}"
        done
    echo "Deleted ${TABLE} from Zookeeper."
}

function get_scheme_from_cluster {
    local TABLE=$1
    local ID=$2

    if [[ ${TABLE} = *"Local"* ]]; then
        STATEMENT=""
    else
        echo "Getting ${TABLE} scheme from cluster."
        for i in `seq 1 ${NUMBER_INSTANCES}`;
            do
                echo "Getting scheme from node"
                STATEMENT=$(curl --data "SHOW CREATE TABLE ${TABLE}" "http://${USERNAME}:${PASSWORD}@${INSTANCE_NAME}${i}.${ZONE_NAME}:8123/")
                if [[ ${STATEMENT} != *"Exception"* ]]; then
                    STATEMENT=$(echo ${STATEMENT} | sed s/"\\\'"/"'"/g)
                    STATEMENT=$(echo ${STATEMENT} | sed s/"'${i}'"/"'${ID}'"/g)
                    break
                else
                    STATEMENT=""
                fi
            done
    fi
    echo "Got statement: ${STATEMENT}"
}

function main {
    local ID=$(cat ${ID_PATH})
    update_conf

    echo "Node ID is ${ID}"

    echo "Starting registering"
    until $(curl --output /dev/null --silent --head --fail http://localhost:8123); do
        echo 'Waiting Clickhouse to deploy'
        sleep 5
    done
    echo "Initializing Clickhouse"

    read -r -a array <<< "$TABLES"
    for TABLE in "${array[@]}"
    do
        IS_EXISTS=$(curl --data "EXISTS ${TABLE}" "http://${USERNAME}:${PASSWORD}@localhost:8123/")
        echo "Is exists ${TABLE} = ${IS_EXISTS}"
        if [[ ${IS_EXISTS} = "0" ]]; then
            delete_node_zk ${TABLE} ${ID}
            STATEMENT=""
            get_scheme_from_cluster ${TABLE} ${ID}
            if [[ ${STATEMENT} != "" ]]; then
                echo "Executing statement got from cluster"
                curl --data "${STATEMENT}" "http://${USERNAME}:${PASSWORD}@localhost:8123/"
                echo "Statement got from cluster executed"
            else
                echo "Loading init sql for ${TABLE}"
                load_file "${S3_CONFIGS_BUCKET}/${TABLE}.sql" "${TABLE}.sql"
                STATEMENT=$(cat "${TABLE}.sql")
                STATEMENT=$(echo ${STATEMENT} | sed s/'${ID}'/"${ID}"/g)
                curl --data "${STATEMENT}" "http://${USERNAME}:${PASSWORD}@localhost:8123/"
                echo "Init sql executed"
            fi
        else
            echo "Table ${TABLE} already exists."
        fi

        sleep 60
    done

    echo "Done initializing Clickhouse"
}

STATEMENT=""
main