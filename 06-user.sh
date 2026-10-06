#!/bin/bash

source ./common.sh

dnf module disable nodejs -y &>> $LOGS_FILE
dnf module enable nodejs:24 -y &>> $LOGS_FILE
VALIDATE $? "Enabling Node.js 24"

dnf install nodejs -y &>> $LOGS_FILE
VALIDATE $? "Installing Node.js"

CREATE_APP_USER
DOWNLOAD_APP user

cd /app
npm install &>> $LOGS_FILE
VALIDATE $? "Installing dependencies"

SETUP_SERVICE user

echo "---- Checks ----"
WAIT_FOR_URL http://localhost:8080/health 30
CHECK_SERVICE user
CHECK_PORT 8080
CHECK_CONNECT mongodb.$DOMAIN_NAME 27017
CHECK_CONNECT redis.$DOMAIN_NAME 6379
CHECK_URL http://localhost:8080/health 200

# the demo user is loaded by 05-catalogue.sh
CODE=$(curl -s -o /dev/null -w "%{http_code}" -X POST http://localhost:8080/login \
    -H "Content-Type: application/json" -d '{"name":"roboshop","password":"RoboShop@1"}')
if [ "$CODE" == "200" ]; then
    PASS "demo user roboshop can log in"
else
    FAIL "demo user login returned $CODE, expected 200 (run 05-catalogue.sh first, it loads the demo user)"
fi
CHECK_SUMMARY
