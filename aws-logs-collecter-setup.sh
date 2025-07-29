#!/bin/bash

# Prompt for values
read -p "Enter LOG_TYPE: " LOG_TYPE
read -p "Enter DIR_NAME (e.g., aws): " DIR_NAME
read -p "Enter QUEUE_URL: " QUEUE_URL
read -p "Enter ROLE_ARN: " ROLE_ARN
read -p "Enter ACCESS_KEY_ID: " ACCESS_KEY_ID
read -p "Enter SECRET_ACCESS_KEY: " SECRET_ACCESS_KEY

# Derived base path
BASE_PATH="/opt/docker/${DIR_NAME}"

# Confirm configuration
echo -e "\nPlease confirm the configuration:"
echo "LOG_TYPE         : $LOG_TYPE"
echo "DIR_NAME         : $DIR_NAME"
echo "BASE_PATH        : $BASE_PATH"
echo "QUEUE_URL        : $QUEUE_URL"
echo "ROLE_ARN         : $ROLE_ARN"
echo "ACCESS_KEY_ID    : $ACCESS_KEY_ID"
echo "SECRET_ACCESS_KEY: $SECRET_ACCESS_KEY"

read -p "Proceed with these values? (yes/no): " CONFIRM
if [[ "$CONFIRM" != "yes" ]]; then
  echo "Aborted."
  exit 1
fi

# Create necessary directories
mkdir -p "${BASE_PATH}/conf/registry/${LOG_TYPE}"
mkdir -p "${BASE_PATH}/var/tmp"

# Write docker-compose.yml
cat <<EOF > "${BASE_PATH}/conf/docker-compose.yml"
version: '3.7'

services:
  ${LOG_TYPE}:
    image: docker.elastic.co/beats/filebeat:7.17.29
    container_name: ${LOG_TYPE}
    network_mode: host
    volumes:
      - ${BASE_PATH}:/opt/docker/${DIR_NAME}
      - ${BASE_PATH}/conf/${LOG_TYPE}.yaml:/usr/share/filebeat/filebeat.yml
      - ${BASE_PATH}/conf/registry/${LOG_TYPE}:/usr/share/filebeat/data/${LOG_TYPE}
      - ${BASE_PATH}/var/tmp:/opt/docker/${DIR_NAME}/var/tmp
    environment:
      - BEAT_PATH=/usr/share/filebeat
    user: root
    restart: always
EOF

# Write Filebeat configuration YAML
cat <<EOF > "${BASE_PATH}/conf/${LOG_TYPE}.yaml"
################################################################################
                        Configuration - ${LOG_TYPE}                 
################################################################################

#=============================== 📁 Inputs ===================================#

filebeat.inputs:
  - type: aws-s3
    enabled: true
    fields:
      log.type: ${LOG_TYPE}
    fields_under_root: true
    queue_url: ${QUEUE_URL}
    role_arn: ${ROLE_ARN}
    access_key_id: ${ACCESS_KEY_ID}
    secret_access_key: ${SECRET_ACCESS_KEY}

#=========================== 🌏 Global Options ==============================#

filebeat.registry.path: /usr/share/filebeat/data/${LOG_TYPE}

#============================= 🧩 Modules ===================================#

filebeat.config.modules:
  path: \${path.config}/modules.d/*.yml
  reload.enabled: false

#============================== 🛠️  Processors ===============================#

processors:
  - add_tags:
      tags:
        - forwarded
  - add_host_metadata:
      when.not.contains.tags: forwarded

#============================== 🎯 Output ===================================#

output.logstash:
  hosts:
    - 127.0.0.1:12222

#============================= ⚙️  Seccomp Settings ==========================#

seccomp:
  default_action: allow
  syscalls:
    - action: allow
      names:
        - rseq
EOF

echo -e "\n✅ Done. Files written under: ${BASE_PATH}/conf"
