#!/bin/bash

source ./common.sh
MONGODB_HOST=mongodb.$DOMAIN_NAME

dnf module disable nodejs -y &>> $LOGS_FILE
dnf module enable nodejs:24 -y &>> $LOGS_FILE
VALIDATE $? "Enabling Node.js 24"

dnf install nodejs -y &>> $LOGS_FILE
VALIDATE $? "Installing Node.js"

CREATE_APP_USER
DOWNLOAD_APP catalogue

cd /app
npm install &>> $LOGS_FILE
VALIDATE $? "Installing dependencies"

SETUP_SERVICE catalogue

cp $SCRIPT_DIR/mongo.repo /etc/yum.repos.d/mongo.repo
VALIDATE $? "Adding MongoDB repo"

dnf install mongodb-mongosh -y &>> $LOGS_FILE
VALIDATE $? "Installing MongoDB client"

# load the products only once, loading again adds them twice
COUNT=$(mongosh --host $MONGODB_HOST --quiet --eval 'db.getSiblingDB("catalogue").products.countDocuments()')
VALIDATE $? "Connecting to MongoDB"

if [ "$COUNT" -eq 0 ]; then
    mongosh --host $MONGODB_HOST < /app/db/master-data.js &>> $LOGS_FILE
    VALIDATE $? "Loading products"
else
    SKIP "$COUNT products already loaded"
fi

echo "---- Checks ----"
WAIT_FOR_URL http://localhost:8080/health 30
CHECK_SERVICE catalogue
CHECK_PORT 8080
CHECK_CONNECT $MONGODB_HOST 27017
CHECK_URL http://localhost:8080/health 200
CHECK_URL http://localhost:8080/products 200
CHECK_URL http://localhost:8080/product/RMC 200
CHECK_SUMMARY
