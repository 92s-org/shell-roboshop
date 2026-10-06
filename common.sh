#!/bin/bash

# Common code for all the component scripts.
# Every script loads this file with: source ./common.sh

DOMAIN_NAME="daws92s.store" # replace with your domain name
SCRIPT_DIR=$PWD
LOGS_FOLDER="/var/log/roboshop"
SCRIPT_NAME=$(basename $0 .sh)
LOGS_FILE="$LOGS_FOLDER/$SCRIPT_NAME.log"
FAILED_CHECKS=0

R="\e[31m"
G="\e[32m"
Y="\e[33m"
N="\e[0m"

if [ $(id -u) -ne 0 ]; then
    echo -e "$R ERROR:: Please run this script with root access: sudo bash $0 $N"
    exit 1
fi

mkdir -p $LOGS_FOLDER
echo "===== $(date '+%Y-%m-%d %H:%M:%S') started $0 =====" >> $LOGS_FILE

# usage: VALIDATE $? "message"
# stops the script when the previous command failed
VALIDATE(){
    if [ $1 -ne 0 ]; then
        echo -e "$(date '+%H:%M:%S') $2 ... $R FAILURE $N, check the log: $LOGS_FILE"
        exit 1
    else
        echo -e "$(date '+%H:%M:%S') $2 ... $G SUCCESS $N"
    fi
}

SKIP(){
    echo -e "$(date '+%H:%M:%S') $1 ... $Y SKIPPING $N"
}

# roboshop system user, used by all the applications
CREATE_APP_USER(){
    id roboshop &>> $LOGS_FILE
    if [ $? -ne 0 ]; then
        useradd --system --home /app --shell /sbin/nologin --comment "roboshop system user" roboshop &>> $LOGS_FILE
        VALIDATE $? "Creating roboshop system user"
    else
        SKIP "roboshop system user already exists"
    fi
}

# usage: DOWNLOAD_APP catalogue
# removes the old code and downloads the latest one into /app
DOWNLOAD_APP(){
    rm -rf /app /tmp/$1.zip
    mkdir -p /app
    curl -L -o /tmp/$1.zip https://raw.githubusercontent.com/daws-92s/roboshop-documentation/refs/heads/main/artifacts/$1-v4.zip &>> $LOGS_FILE
    VALIDATE $? "Downloading $1 code"

    cd /app
    unzip /tmp/$1.zip &>> $LOGS_FILE
    VALIDATE $? "Extracting $1 code"
}

# usage: SETUP_SERVICE catalogue
# copies the service file from this repo and (re)starts it
SETUP_SERVICE(){
    cp $SCRIPT_DIR/$1.service /etc/systemd/system/$1.service
    VALIDATE $? "Copying $1 service file"

    systemctl daemon-reload
    systemctl enable $1 &>> $LOGS_FILE
    systemctl restart $1
    VALIDATE $? "Starting $1"
}

######## checks ########
# checks never stop the script, they only print PASS or FAIL

PASS(){
    echo -e "  $G PASS $N $1"
}

FAIL(){
    echo -e "  $R FAIL $N $1"
    FAILED_CHECKS=$((FAILED_CHECKS + 1))
}

# usage: CHECK_SERVICE mongod
CHECK_SERVICE(){
    if systemctl is-active $1 &>/dev/null; then
        PASS "service $1 is running"
    else
        FAIL "service $1 is not running, check: journalctl -u $1"
    fi
}

# usage: CHECK_PORT 27017
CHECK_PORT(){
    if ss -lnt | grep -q ":$1 "; then
        PASS "port $1 is open"
    else
        FAIL "nothing is listening on port $1"
    fi
}

# usage: CHECK_CONNECT mongodb.daws92s.store 27017
# can this server reach another server on that port?
CHECK_CONNECT(){
    if timeout 5 bash -c "</dev/tcp/$1/$2" &>/dev/null; then
        PASS "can connect to $1:$2"
    else
        FAIL "cannot connect to $1:$2 (is that server running? check the DNS record and the security group)"
    fi
}

# usage: CHECK_URL http://localhost:8080/health 200
CHECK_URL(){
    CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 $1)
    if [ "$CODE" == "$2" ]; then
        PASS "$1 returned $CODE"
    else
        FAIL "$1 returned $CODE, expected $2"
    fi
}

# usage: WAIT_FOR_URL http://localhost:8080/health 60
# some applications need a few seconds to start, wait for them
WAIT_FOR_URL(){
    for i in $(seq 1 $2); do
        curl -s -o /dev/null --max-time 2 $1 && return 0
        sleep 1
    done
}

CHECK_SUMMARY(){
    echo
    if [ $FAILED_CHECKS -eq 0 ]; then
        echo -e "$G All checks passed $N"
    else
        echo -e "$R $FAILED_CHECKS check(s) failed $N, see above. Full log: $LOGS_FILE"
        exit 1
    fi
}
