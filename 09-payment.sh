#!/bin/bash

source ./common.sh

dnf install python3.14 python3.14-pip -y &>> $LOGS_FILE
VALIDATE $? "Installing Python 3.14"

CREATE_APP_USER
DOWNLOAD_APP payment

cd /app
python3.14 -m venv /app/.venv &>> $LOGS_FILE
VALIDATE $? "Creating virtual environment"

/app/.venv/bin/pip install -r requirements.txt &>> $LOGS_FILE
VALIDATE $? "Installing dependencies"

SETUP_SERVICE payment

echo "---- Checks ----"
WAIT_FOR_URL http://localhost:8080/health 30
CHECK_SERVICE payment
CHECK_PORT 8080
CHECK_CONNECT cart.$DOMAIN_NAME 8080
CHECK_CONNECT user.$DOMAIN_NAME 8080
CHECK_CONNECT rabbitmq.$DOMAIN_NAME 5672
CHECK_URL http://localhost:8080/health 200
CHECK_SUMMARY
