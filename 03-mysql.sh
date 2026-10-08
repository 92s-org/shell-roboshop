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

# a new MySQL has no root password, so "mysql -uroot" logs in without one
# root@localhost: login on this server, root@%: login from other servers (shipping loads the data)
mysql -uroot -pRoboShop@1 -e "SELECT 1" &>> $LOGS_FILE
if [ $? -ne 0 ]; then
    mysql -uroot -e "
        ALTER USER 'root'@'localhost' IDENTIFIED BY 'RoboShop@1';
        CREATE USER IF NOT EXISTS 'root'@'%' IDENTIFIED BY 'RoboShop@1';
        GRANT ALL PRIVILEGES ON *.* TO 'root'@'%' WITH GRANT OPTION;
    " &>> $LOGS_FILE
    VALIDATE $? "Setting root password"
else
    SKIP "Root password already set"
fi

echo "---- Checks ----"
CHECK_SERVICE mysqld
CHECK_PORT 3306
if mysql -uroot -pRoboShop@1 -e "SELECT 1" &>/dev/null; then
    PASS "root login with password works"
else
    FAIL "root login with password failed"
fi
if mysql -uroot -pRoboShop@1 -N -e "SELECT user FROM mysql.user WHERE user='root' AND host='%'" 2>/dev/null | grep -q root; then
    PASS "root can log in from other servers"
else
    FAIL "root@% is missing, shipping cannot load the data"
fi
CHECK_SUMMARY
