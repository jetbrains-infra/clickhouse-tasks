#!/usr/bin/env bash

function load_file {
    FROM=$1
    TO=$2
    aws s3 cp "s3://${FROM}" ${TO}
}

function update_conf {
    echo "Updating configs"
    load_file "${S3_CONFIGS_BUCKET}/${SERVER_CONFIG}" "${CONFIG_PATH}/config.xml"
    load_file "${S3_CONFIGS_BUCKET}/${USERS_CONFIG}" "${CONFIG_PATH}/users.xml"
    echo "Configs updated"
}

function delete_node_zk {
    TABLE=$1
    ID=$2
    echo "Deleting ${TABLE} from Zookeeper."
    for i in `seq 1 ${NUMBER_INSTANCES}`;
        do
            echo "Executing delete all on instance${i}"
            ./zookeeper-3.4.9/bin/zkCli.sh -server "${INSTANCE_NAME}${i}.${ZONE_NAME}" rmr "/clickhouse/tables/${TABLE}/replicas/${ID}"
        done
    echo "Deleted ${TABLE} from Zookeeper."
}

function get_scheme_from_cluster {
    TABLE=$1
    ID=$2

    echo "Getting ${TABLE} scheme from cluster."
    for i in `seq 1 ${NUMBER_INSTANCES}`;
        do
            echo "Getting scheme from node"
            STATEMENT=$(curl --data "SHOW CREATE TABLE ${TABLE}" "http://${USERNAME}:${PASSWORD}@localhost:8123/")
            if [[ ${STATEMENT} != *"Exception"* ]]; then
                echo "Got statement (not replaced): ${STATEMENT}"
                STATEMENT="${STATEMENT/\'${i}\'/\'${ID}\'}"
                break
            else
                STATEMENT=""
            fi
        done
    echo "Got statement: ${STATEMENT}"
}

function main {
    ID=$(cat ${ID_PATH})
    update_conf

    echo "Starting registering"
    until $(curl --output /dev/null --silent --head --fail http://localhost:8123); do
        echo 'Waiting Clickhouse to deploy'
        sleep 5
    done
    echo "Initializing Clickhouse"

    FS=', ' read -r -a array <<< "$TABLES"
    for TABLE in "${array[@]}"
    do
        IS_EXISTS=$(echo "EXISTS ${TABLE}" | POST "http://${USERNAME}:${PASSWORD}@localhost:8123/")
        echo "Is exists ${TABLE} = ${IS_EXISTS}"
        if [[ ${IS_EXISTS} = "0" ]]; then
            delete_node_zk ${TABLE} ${ID}
        fi

        STATEMENT=""
        get_scheme_from_cluster ${TABLE} ${ID}

        if [[ ${STATEMENT} != "" ]]; then
            echo "Executing statement got from cluster"
            curl --data "${STATEMENT}" "http://${USERNAME}:${PASSWORD}@localhost:8123/"
            echo "Statement got from cluster executed"
        else
            echo "Loading init script for ${TABLE}"
            load_file "${S3_CONFIGS_BUCKET}/${TABLE}-init.sh" "${TABLE}-init.sh"
            chmod +x "${TABLE}-init.sh"
            ./${TABLE}-init.sh ${USERNAME} ${PASSWORD} ${ID}
            echo "Init script executed"
        fi


    done

    echo "Done initializing Clickhouse"
}

main