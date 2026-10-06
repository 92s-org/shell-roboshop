#!/bin/bash

source ./common.sh

dnf module disable redis -y &>> $LOGS_FILE
dnf module enable redis:7 -y &>> $LOGS_FILE
VALIDATE $? "Enabling Redis 7"

dnf install redis -y &>> $LOGS_FILE
VALIDATE $? "Installing Redis"

# user and cart connect from other servers
sed -i -e 's/^bind 127.0.0.1/bind 0.0.0.0/' -e 's/^protected-mode yes/protected-mode no/' /etc/redis/redis.conf
VALIDATE $? "Allowing remote connections"

systemctl enable redis &>> $LOGS_FILE
systemctl restart redis
VALIDATE $? "Starting Redis"

echo "---- Checks ----"
CHECK_SERVICE redis
CHECK_PORT 6379
if [ "$(redis-cli ping)" == "PONG" ]; then
    PASS "redis-cli ping returned PONG"
else
    FAIL "redis-cli ping did not return PONG"
fi
CHECK_SUMMARY
