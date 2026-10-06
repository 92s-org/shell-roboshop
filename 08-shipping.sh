#!/bin/bash

source ./common.sh
MYSQL_HOST=mysql.$DOMAIN_NAME

dnf module enable maven:3.9 -y &>> $LOGS_FILE
dnf install maven java-25-openjdk-devel -y &>> $LOGS_FILE
VALIDATE $? "Installing Java 25 and Maven"

# maven also installs Java 21, make Java 25 the default
# the folder name has the exact version, so take it from the alternatives list
JAVA_25=$(alternatives --display java | grep -o "/usr/lib/jvm/java-25[^ ]*/bin/java" | head -1)
alternatives --set java $JAVA_25
VALIDATE $? "Setting Java 25 as default"

# JAVA_HOME tells maven which Java to use, profile.d keeps it after logout
# /usr/lib/jvm/java-25-openjdk-<version>/bin/java -> /usr/lib/jvm/java-25-openjdk-<version>
echo "export JAVA_HOME=$(dirname $(dirname $JAVA_25))" > /etc/profile.d/java.sh
source /etc/profile.d/java.sh
echo "JAVA_HOME=$JAVA_HOME" &>> $LOGS_FILE

CREATE_APP_USER
DOWNLOAD_APP shipping

cd /app
mvn clean package &>> $LOGS_FILE
VALIDATE $? "Building shipping (takes a few minutes)"

mv target/shipping.jar shipping.jar
VALIDATE $? "Moving shipping.jar"

dnf install mysql -y &>> $LOGS_FILE
VALIDATE $? "Installing MySQL client"

# load the data before starting the service, only when the cities database is missing
mysql -h $MYSQL_HOST -uroot -pRoboShop@1 -e "USE cities" &>> $LOGS_FILE
if [ $? -ne 0 ]; then
    mysql -h $MYSQL_HOST -uroot -pRoboShop@1 < /app/db/master-data.sql &>> $LOGS_FILE
    VALIDATE $? "Loading cities"
else
    SKIP "Cities already loaded"
fi

mysql -h $MYSQL_HOST -uroot -pRoboShop@1 < /app/db/app-user.sql &>> $LOGS_FILE
VALIDATE $? "Creating shipping database user"

SETUP_SERVICE shipping

echo "---- Checks ----"
echo "Waiting for Spring Boot to start..."
WAIT_FOR_URL http://localhost:8080/health 90
CHECK_SERVICE shipping
CHECK_PORT 8080
CHECK_CONNECT $MYSQL_HOST 3306
CHECK_CONNECT cart.$DOMAIN_NAME 8080
CHECK_URL http://localhost:8080/actuator/health 200
CHECK_URL http://localhost:8080/codes 200
CHECK_SUMMARY
