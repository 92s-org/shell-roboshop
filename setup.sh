#!/bin/bash

# Sets up all the RoboShop servers from one place, run it after: ./roboshop.sh create all
#   ./setup.sh all
#   ./setup.sh shipping payment
#
# Run it on a server in the same VPC (your workstation), because the servers are
# reached by their private IPs through <component>.<domain>.
#
# For every component, in the right order, it:
#   1. waits until SSH is ready on that server
#   2. logs in, clones (or pulls) this repo and runs the component script as root
#   3. stops when a script fails, because the next components need this one

DOMAIN_NAME="daws92s.store"                              # replace with your domain name
REPO_URL="https://github.com/92s-org/shell-roboshop.git" # replace with your repo
SSH_USER="ec2-user"
export SSHPASS="DevOps321"                               # password of the practice AMI, sshpass reads it from here

R="\e[31m"
G="\e[32m"
Y="\e[33m"
N="\e[0m"

# setup order: databases, backend, frontend
ALL_COMPONENTS="mongodb redis mysql rabbitmq catalogue user cart shipping payment dispatch frontend"
REPO_DIR=$(basename $REPO_URL .git)
LOGS_FOLDER="./logs"

USAGE(){
    echo "USAGE: $0 [all] or [component1] [component2...]"
    echo "components: $ALL_COMPONENTS"
    exit 1
}

### Validation ###
if [ $# -lt 1 ]; then
    echo -e "$R ERROR:: At least 1 argument required $N"
    USAGE
fi

if [ "$1" == "all" ]; then
    COMPONENTS=$ALL_COMPONENTS
else
    # keep the setup order, even when the components are given in another order
    COMPONENTS=""
    for component in $ALL_COMPONENTS
    do
        echo " $* " | grep -q " $component " && COMPONENTS="$COMPONENTS $component"
    done
    for component in "$@"
    do
        if ! echo " $ALL_COMPONENTS " | grep -q " $component "; then
            echo -e "$R ERROR:: Unknown component: $component $N"
            USAGE
        fi
    done
fi

if ! command -v sshpass &>/dev/null; then
    echo -e "$R ERROR:: sshpass is not installed. Install it with: $N"
    echo "  sudo dnf install https://dl.fedoraproject.org/pub/epel/epel-release-latest-9.noarch.rpm -y"
    echo "  sudo dnf install sshpass -y"
    exit 1
fi

mkdir -p $LOGS_FOLDER

# usage: script_name mongodb -> 01-mongodb.sh
script_name(){
    NUMBER=1
    for component in $ALL_COMPONENTS
    do
        if [ "$component" == "$1" ]; then
            printf "%02d-%s.sh" $NUMBER $1
            return
        fi
        NUMBER=$((NUMBER + 1))
    done
}

# frontend has the main domain, the others have <component>.<domain>
host_name(){
    if [ "$1" == "frontend" ]; then
        echo "$DOMAIN_NAME"
    else
        echo "$1.$DOMAIN_NAME"
    fi
}

# new servers need a minute to boot, wait until port 22 answers
wait_for_ssh(){
    for i in $(seq 1 30); do
        timeout 5 bash -c "</dev/tcp/$1/22" &>/dev/null && return 0
        sleep 5
    done
    return 1
}

# usage: run_setup mongodb
run_setup(){
    HOST=$(host_name $1)
    SCRIPT=$(script_name $1)
    LOG_FILE="$LOGS_FOLDER/$1.log"

    echo -e "\n$Y======== $1 ($HOST) : $SCRIPT ========$N"

    if ! wait_for_ssh $HOST; then
        echo -e "$R ERROR:: cannot reach $HOST on port 22 (is the server running? check the DNS record and the security group) $N"
        return 1
    fi

    # the IPs change when servers are created again, so do not save or check host keys
    # sudo bash: the component scripts need root
    sshpass -e ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR \
        $SSH_USER@$HOST "sudo bash -c '
            dnf install git -y &>/dev/null
            cd /root
            if [ -d $REPO_DIR ]; then
                git -C $REPO_DIR pull -q
            else
                git clone -q $REPO_URL
            fi
            cd $REPO_DIR && bash $SCRIPT
        '" 2>&1 | tee $LOG_FILE

    # exit code of ssh, not of tee
    return ${PIPESTATUS[0]}
}

START=$(date +%s)
DONE=""
for component in $COMPONENTS
do
    run_setup $component
    if [ $? -ne 0 ]; then
        # this component and everything after it
        REMAINING=$(echo $COMPONENTS | sed "s/.*\b$component\b/$component/")
        echo -e "\n$R ======== $component FAILED ======== $N"
        echo "Output saved in: $LOGS_FOLDER/$component.log"
        echo "Full log on the server: /var/log/roboshop/$(basename $(script_name $component) .sh).log"
        [ -n "$DONE" ] && echo -e "Completed:$G$DONE $N"
        echo "Fix the problem, then continue with: $0 $REMAINING"
        exit 1
    fi
    DONE="$DONE $component"
done

echo -e "\n$G ======== All done in $(( ($(date +%s) - START) / 60 )) minutes ======== $N"
echo -e "Completed:$G$DONE $N"
echo "Open the application: http://$DOMAIN_NAME"
