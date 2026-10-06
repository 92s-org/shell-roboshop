#!/bin/bash

source ./common.sh

dnf install golang -y &>> $LOGS_FILE
VALIDATE $? "Installing Go"

CREATE_APP_USER
DOWNLOAD_APP dispatch

cd /app
go build -o dispatch . &>> $LOGS_FILE
VALIDATE $? "Building dispatch"

SETUP_SERVICE dispatch

echo "---- Checks ----"
sleep 5 # give dispatch time to connect
CHECK_SERVICE dispatch
CHECK_CONNECT rabbitmq.$DOMAIN_NAME 5672
# dispatch has no port, so check its log
if journalctl -u dispatch --since "1 minute ago" | grep -q "connected to RabbitMQ"; then
    PASS "dispatch connected to RabbitMQ"
else
    FAIL "dispatch is not connected to RabbitMQ, check: journalctl -u dispatch"
fi
CHECK_SUMMARY
