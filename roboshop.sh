#!/bin/bash

# Creates the RoboShop servers in AWS, run it where the AWS CLI is configured.
#   ./roboshop.sh create all
#   ./roboshop.sh create mongodb catalogue
#   ./roboshop.sh delete all
#
# For every component it makes sure that:
#   1. security group roboshop-<component> exists, with the right rules
#   2. instance roboshop-<component> exists and is running
#   3. Route53 record <component>.<domain> points to the private IP
#      (frontend: <domain> points to the public IP)
# Anything that already exists is left as it is, so it is safe to run again.

AMI_ID="ami-0220d79f3f480ecf5"     # RHEL 9 practice AMI
INSTANCE_TYPE="t3.micro"
DOMAIN_NAME="daws92s.store"       # replace with your domain name
SSH_CIDR="0.0.0.0/0"               # replace with <your-ip>/32 to allow SSH only from your laptop

R="\e[31m"
G="\e[32m"
Y="\e[33m"
N="\e[0m"

# setup order: databases, backend, frontend
ALL_COMPONENTS="mongodb redis mysql rabbitmq catalogue user cart shipping payment dispatch frontend"

# inbound rules: <component> <port> <source>
# source is another component (its security group) or an IP range
RULES="
mongodb   22    $SSH_CIDR
mongodb   27017 catalogue
mongodb   27017 user
redis     22    $SSH_CIDR
redis     6379  user
redis     6379  cart
mysql     22    $SSH_CIDR
mysql     3306  shipping
rabbitmq  22    $SSH_CIDR
rabbitmq  5672  payment
rabbitmq  5672  dispatch
catalogue 22    $SSH_CIDR
catalogue 8080  frontend
catalogue 8080  cart
user      22    $SSH_CIDR
user      8080  frontend
user      8080  payment
cart      22    $SSH_CIDR
cart      8080  frontend
cart      8080  shipping
cart      8080  payment
shipping  22    $SSH_CIDR
shipping  8080  frontend
payment   22    $SSH_CIDR
payment   8080  frontend
dispatch  22    $SSH_CIDR
frontend  22    $SSH_CIDR
frontend  80    0.0.0.0/0
"

USAGE(){
    echo "USAGE: $0 [create/delete] [all] or [component1] [component2...]"
    echo "components: $ALL_COMPONENTS"
    exit 1
}

### Validation ###
if [ $# -lt 2 ]; then
    echo -e "$R ERROR:: At least 2 arguments required $N"
    USAGE
fi

ACTION=$1
shift # first argument is removed, the rest are components

if [ "$ACTION" != "create" ] && [ "$ACTION" != "delete" ]; then
    echo -e "$R ERROR:: First argument must be either create or delete $N"
    USAGE
fi

if [ "$1" == "all" ]; then
    COMPONENTS=$ALL_COMPONENTS
else
    COMPONENTS="$@"
fi

for component in $COMPONENTS
do
    if ! echo " $ALL_COMPONENTS " | grep -q " $component "; then
        echo -e "$R ERROR:: Unknown component: $component $N"
        USAGE
    fi
done

############ Security Groups ############

VPC_ID=$(aws ec2 describe-vpcs --filters "Name=is-default,Values=true" --query "Vpcs[0].VpcId" --output text)
if [ "$VPC_ID" == "None" ] || [ -z "$VPC_ID" ]; then
    echo -e "$R ERROR:: No default VPC found, or the AWS CLI is not configured $N"
    exit 1
fi

# prints the security group id, or None when it does not exist
get_sg_id(){
    aws ec2 describe-security-groups \
        --filters "Name=group-name,Values=$1" "Name=vpc-id,Values=$VPC_ID" \
        --query "SecurityGroups[0].GroupId" --output text
}

create_sg(){
    SG_NAME="roboshop-$1"
    SG_ID=$(get_sg_id $SG_NAME)
    if [ "$SG_ID" == "None" ]; then
        SG_ID=$(aws ec2 create-security-group \
            --group-name $SG_NAME \
            --description "RoboShop $1" \
            --vpc-id $VPC_ID \
            --tag-specifications "ResourceType=security-group,Tags=[{Key=Name,Value=$SG_NAME}]" \
            --query "GroupId" --output text)
        echo -e "Security group $SG_NAME ... $G CREATED $N $SG_ID"
    else
        echo -e "Security group $SG_NAME ... $Y EXISTS $N $SG_ID"
    fi
}

# usage: add_rule <component> <port> <source>
add_rule(){
    SG_ID=$(get_sg_id roboshop-$1)
    PORT=$2

    if [[ $3 =~ ^[0-9] ]]; then
        # source is an IP range like 0.0.0.0/0
        SOURCE_TEXT=$3
        SOURCE_OPTION="--cidr $3"
        MATCH="CidrIpv4=='$3'"
    else
        # source is another component, allow its security group
        SOURCE_ID=$(get_sg_id roboshop-$3)
        SOURCE_TEXT=roboshop-$3
        SOURCE_OPTION="--source-group $SOURCE_ID"
        MATCH="ReferencedGroupInfo.GroupId=='$SOURCE_ID'"
    fi

    RULE_ID=$(aws ec2 describe-security-group-rules \
        --filters "Name=group-id,Values=$SG_ID" \
        --query "SecurityGroupRules[?IsEgress==\`false\` && FromPort==\`$PORT\` && $MATCH].SecurityGroupRuleId" \
        --output text)

    if [ -z "$RULE_ID" ]; then
        aws ec2 authorize-security-group-ingress --group-id $SG_ID --protocol tcp --port $PORT $SOURCE_OPTION > /dev/null
        echo -e "  roboshop-$1 port $PORT from $SOURCE_TEXT ... $G ADDED $N"
    else
        echo -e "  roboshop-$1 port $PORT from $SOURCE_TEXT ... $Y EXISTS $N"
    fi
}

if [ "$ACTION" == "create" ]; then
    # rules point to other security groups, so all of them are created first
    echo "---- Security groups ----"
    for component in $ALL_COMPONENTS
    do
        create_sg $component
    done

    echo "---- Security group rules ----"
    echo "$RULES" | while read component port from
    do
        [ -z "$component" ] && continue # skip empty lines
        add_rule $component $port $from
    done
fi

############ Instances ############

# prints "<instance-id> <state>", or None when it does not exist
get_instance(){
    aws ec2 describe-instances \
        --filters "Name=tag:Name,Values=roboshop-$1" "Name=instance-state-name,Values=pending,running,stopping,stopped" \
        --query "Reservations[0].Instances[0].[InstanceId,State.Name]" --output text
}

update_record(){
    INSTANCE_ID=$1
    if [ $2 == "frontend" ]; then
        IP=$(aws ec2 describe-instances --instance-ids $INSTANCE_ID --query "Reservations[0].Instances[0].PublicIpAddress" --output text)
        RECORD_NAME="$DOMAIN_NAME"
    else
        IP=$(aws ec2 describe-instances --instance-ids $INSTANCE_ID --query "Reservations[0].Instances[0].PrivateIpAddress" --output text)
        RECORD_NAME="$2.$DOMAIN_NAME"
    fi

    aws route53 change-resource-record-sets \
    --hosted-zone-id $ZONE_ID \
    --change-batch '
        {
            "Comment": "Update A record to new IP",
            "Changes": [
                {
                    "Action": "UPSERT",
                    "ResourceRecordSet": {
                        "Name": "'$RECORD_NAME'",
                        "Type": "A",
                        "TTL": 1,
                        "ResourceRecords": [
                            {
                                "Value": "'$IP'"
                            }
                        ]
                    }
                }
            ]
        }
    ' > /dev/null
    echo -e "Record $RECORD_NAME -> $IP ... $G UPDATED $N"
}

if [ "$ACTION" == "create" ]; then
    ZONE_ID=$(aws route53 list-hosted-zones-by-name --dns-name $DOMAIN_NAME \
        --query "HostedZones[?Name=='$DOMAIN_NAME.'].Id | [0]" --output text)
    if [ "$ZONE_ID" == "None" ] || [ -z "$ZONE_ID" ]; then
        echo -e "$R ERROR:: No Route53 hosted zone found for $DOMAIN_NAME $N"
        exit 1
    fi

    echo "---- Instances ----"
    INSTANCE_IDS=""
    for component in $COMPONENTS
    do
        read INSTANCE_ID STATE <<< "$(get_instance $component)"

        if [ "$INSTANCE_ID" == "None" ]; then
            INSTANCE_ID=$(aws ec2 run-instances \
                --image-id $AMI_ID \
                --instance-type $INSTANCE_TYPE \
                --security-group-ids $(get_sg_id roboshop-$component) \
                --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=roboshop-$component}]" \
                --query "Instances[0].InstanceId" --output text)
            echo -e "Instance roboshop-$component ... $G CREATED $N $INSTANCE_ID"
        elif [ "$STATE" == "stopped" ]; then
            aws ec2 start-instances --instance-ids $INSTANCE_ID > /dev/null
            echo -e "Instance roboshop-$component was stopped ... $G STARTED $N $INSTANCE_ID"
        elif [ "$STATE" == "stopping" ]; then
            echo -e "Instance roboshop-$component is stopping ... $Y run this script again in a minute $N"
            continue
        else
            echo -e "Instance roboshop-$component ... $Y EXISTS $N $INSTANCE_ID ($STATE)"
        fi
        INSTANCE_IDS="$INSTANCE_IDS $INSTANCE_ID"
    done

    # the public IP is given only when the instance is running
    if [ -n "$INSTANCE_IDS" ]; then
        echo "Waiting for the instances to be running..."
        aws ec2 wait instance-running --instance-ids $INSTANCE_IDS
    fi

    echo "---- Route53 records ----"
    for component in $COMPONENTS
    do
        read INSTANCE_ID STATE <<< "$(get_instance $component)"
        [ "$STATE" == "running" ] && update_record $INSTANCE_ID $component
    done

    echo "---- RoboShop instances ----"
    aws ec2 describe-instances \
        --filters "Name=tag:Name,Values=roboshop-*" "Name=instance-state-name,Values=running" \
        --query "Reservations[].Instances[].[Tags[?Key=='Name']|[0].Value,PrivateIpAddress,PublicIpAddress]" \
        --output table
else
    # delete removes only the instances, the security groups stay for next time
    for component in $COMPONENTS
    do
        read INSTANCE_ID STATE <<< "$(get_instance $component)"
        if [ "$INSTANCE_ID" == "None" ]; then
            echo -e "Instance roboshop-$component ... $Y already deleted $N"
        else
            aws ec2 terminate-instances --instance-ids $INSTANCE_ID > /dev/null
            echo -e "Instance roboshop-$component ... $G TERMINATING $N $INSTANCE_ID"
        fi
    done
fi
