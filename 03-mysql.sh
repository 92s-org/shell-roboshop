#!/bin/bash

source ./common.sh

dnf module disable mysql -y &>> $LOGS_FILE
dnf module enable mysql:8.4 -y &>> $LOGS_FILE
VALIDATE $? "Enabling MySQL 8.4"

dnf install mysql-server -y &>> $LOGS_FILE
VALIDATE $? "Installing MySQL Server"

systemctl enable mysqld &>> $LOGS_FILE
systemctl start mysqld
VALIDATE $? "Starting MySQL"

# the root password can be set only once, the second time it fails
mysql -uroot -pRoboShop@1 -e "SELECT 1" &>> $LOGS_FILE
if [ $? -ne 0 ]; then
    mysql_secure_installation --set-root-pass RoboShop@1 &>> $LOGS_FILE
    VALIDATE $? "Setting root password"
else
    SKIP "Root password already set"
fi

echo "---- Checks ----"
CHECK_SERVICE mysqld
CHECK_PORT 3306
if mysql -uroot -pRoboShop@1 -e "SELECT 1" &>/dev/null; then
    PASS "root login works"
else
    FAIL "root login failed"
fi
CHECK_SUMMARY
