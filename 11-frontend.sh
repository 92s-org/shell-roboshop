#!/bin/bash

source ./common.sh

dnf module disable nginx -y &>> $LOGS_FILE
dnf module enable nginx:1.26 -y &>> $LOGS_FILE
VALIDATE $? "Enabling Nginx 1.26"

dnf install nginx -y &>> $LOGS_FILE
VALIDATE $? "Installing Nginx"

rm -rf /usr/share/nginx/html/* /tmp/frontend.zip
VALIDATE $? "Removing default content"

curl -L -o /tmp/frontend.zip https://raw.githubusercontent.com/daws-92s/roboshop-documentation/refs/heads/main/artifacts/frontend-v4.zip &>> $LOGS_FILE
VALIDATE $? "Downloading frontend code"

cd /usr/share/nginx/html
unzip /tmp/frontend.zip &>> $LOGS_FILE
VALIDATE $? "Extracting frontend code"

# main nginx.conf is not touched, its default server loads /etc/nginx/default.d/*.conf
cp $SCRIPT_DIR/roboshop.conf /etc/nginx/default.d/roboshop.conf
VALIDATE $? "Copying roboshop nginx conf"

# with SELinux on, nginx is not allowed to connect to the backend servers
if [ "$(getenforce 2>/dev/null)" == "Enforcing" ]; then
    setsebool -P httpd_can_network_connect 1
    VALIDATE $? "Allowing nginx network connections in SELinux"
fi

nginx -t &>> $LOGS_FILE
VALIDATE $? "Checking nginx configuration"

systemctl enable nginx &>> $LOGS_FILE
systemctl restart nginx
VALIDATE $? "Starting Nginx"

echo "---- Checks ----"
CHECK_SERVICE nginx
CHECK_PORT 80
CHECK_URL http://localhost/ 200
CHECK_URL http://localhost/health 200
for service in catalogue user cart shipping payment
do
    CHECK_CONNECT $service.$DOMAIN_NAME 8080
    CHECK_URL http://localhost/api/$service/health 200
done
CHECK_SUMMARY
