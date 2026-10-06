#!/bin/bash

source ./common.sh

cp $SCRIPT_DIR/rabbitmq.repo /etc/yum.repos.d/rabbitmq.repo
VALIDATE $? "Adding RabbitMQ repo"

dnf install erlang rabbitmq-server -y &>> $LOGS_FILE
VALIDATE $? "Installing Erlang and RabbitMQ"

systemctl enable rabbitmq-server &>> $LOGS_FILE
systemctl start rabbitmq-server
VALIDATE $? "Starting RabbitMQ"

# guest can connect only from this server, so the application gets its own user
rabbitmqctl list_users | grep -q "^roboshop"
if [ $? -ne 0 ]; then
    rabbitmqctl add_user roboshop roboshop123 &>> $LOGS_FILE
    VALIDATE $? "Creating roboshop user"
else
    SKIP "roboshop user already exists"
fi

rabbitmqctl set_permissions -p / roboshop ".*" ".*" ".*" &>> $LOGS_FILE
VALIDATE $? "Giving permissions to roboshop user"

# optional web UI on port 15672
rabbitmq-plugins enable rabbitmq_management &>> $LOGS_FILE
rabbitmqctl set_user_tags roboshop administrator &>> $LOGS_FILE
VALIDATE $? "Enabling management UI"

echo "---- Checks ----"
CHECK_SERVICE rabbitmq-server
CHECK_PORT 5672
CHECK_PORT 15672
if rabbitmqctl list_users | grep -q "^roboshop"; then
    PASS "roboshop user exists"
else
    FAIL "roboshop user is missing"
fi
CHECK_SUMMARY
