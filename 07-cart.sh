#!/bin/bash

source ./common.sh

dnf module disable nodejs -y &>> $LOGS_FILE
dnf module enable nodejs:24 -y &>> $LOGS_FILE
VALIDATE $? "Enabling Node.js 24"

dnf install nodejs -y &>> $LOGS_FILE
VALIDATE $? "Installing Node.js"

CREATE_APP_USER
DOWNLOAD_APP cart

cd /app
npm install &>> $LOGS_FILE
VALIDATE $? "Installing dependencies"

SETUP_SERVICE cart

echo "---- Checks ----"
WAIT_FOR_URL http://localhost:8080/health 30
CHECK_SERVICE cart
CHECK_PORT 8080
CHECK_CONNECT redis.$DOMAIN_NAME 6379
CHECK_CONNECT catalogue.$DOMAIN_NAME 8080
CHECK_URL http://localhost:8080/health 200

# adding a product also checks the connection to catalogue
CODE=$(curl -s -o /dev/null -w "%{http_code}" -X POST http://localhost:8080/add/scriptcheck/RMC/1)
if [ "$CODE" == "200" ]; then
    PASS "added a product to a test cart"
else
    FAIL "adding a product returned $CODE, expected 200 (502 means cart cannot reach catalogue)"
fi
curl -s -X DELETE http://localhost:8080/cart/scriptcheck &>/dev/null # remove the test cart
CHECK_SUMMARY
