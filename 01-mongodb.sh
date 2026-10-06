#!/bin/bash

source ./common.sh

cp $SCRIPT_DIR/mongo.repo /etc/yum.repos.d/mongo.repo
VALIDATE $? "Adding MongoDB repo"

dnf install mongodb-org -y &>> $LOGS_FILE
VALIDATE $? "Installing MongoDB 7.0"

# catalogue and user connect from other servers, so listen on all addresses
sed -i 's/127.0.0.1/0.0.0.0/' /etc/mongod.conf
VALIDATE $? "Allowing remote connections"

systemctl enable mongod &>> $LOGS_FILE
systemctl restart mongod
VALIDATE $? "Starting MongoDB"

echo "---- Checks ----"
sleep 3 # mongod needs a moment to open the port
CHECK_SERVICE mongod
CHECK_PORT 27017
if ss -lnt | grep -q "0.0.0.0:27017"; then
    PASS "MongoDB listens on 0.0.0.0"
else
    FAIL "MongoDB listens only on localhost, check bindIp in /etc/mongod.conf"
fi
CHECK_SUMMARY
