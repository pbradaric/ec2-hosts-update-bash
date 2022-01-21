#!/bin/bash
################################################################################
# EC2 Instances hosts Update Script
################################################################################
#
# This script gets a list of all running EC2 instances and updates local hosts
# file with new IP addresses.
# The list contains the Name tag and IP address for each running EC2 instance.
# 
# Prerequisites
# -------------
# This script requires AWS CLI v2 to be installed on the system 
# (https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html).
# This script expects MFA to be enabled for current IAM account.
# This script also requires user to setup new AWS CLI profile named "mfa"
# (https://docs.aws.amazon.com/cli/latest/userguide/cli-configure-profiles.html).
#
# Dependencies
# ------------
#   - AWS CLI v2
#
# Optional dependencies
# --------------------- 
#   - oathtool
#
# Author: Predrag Bradaric
#
################################################################################

#
# Config
# ------------------------------------------------------------------------------
AWS_CLI_CREDENTIALS_PATH=~/.aws/credentials
HOSTS_FILE_PATH=/etc/hosts
KNOWN_HOSTS_FILE_PATH=~/.ssh/known_hosts

#
# Helper variables
# ------------------------------------------------------------------------------
NC='\033[0m' # No Color
BLACK='\033[0;30m'
DARK_GRAY='\033[1;30m'
RED='\033[0;31m'
LIGHT_RED='\033[1;31m'
GREEN='\033[0;32m'
LIGHT_GREEN='\033[1;32m'
BROWN_ORANGE='\033[0;33m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
LIGHT_BLUE='\033[1;34m'
PURPLE='\033[0;35m'
LIGHT_PURPLE='\033[1;35m'
CYAN='\033[0;36m'
LIGHT_CYAN='\033[1;36m'
LIGHT_GRAY='\033[0;37m'
WHITE='\033[1;37m'
B_BLACK='\033[0;40m'
B_RED='\033[0;41m'
B_GREEN='\033[0;42m'
B_YELLOW='\033[0;43m'
B_BLUE='\033[0;44m'
B_MAGENTA='\033[0;45m'
B_CYAN='\033[0;46m'
B_WHITE='\033[0;47m'
AWK_ADD_NUMBERS='
BEGIN {
    prev_row="";
    prev_value="";
    cnt=1;
}

NF {
    if (prev_row=="") {
        prev_row = sprintf("%-15s    %s", $1, $2);
        prev_value = $2;
        next;
    }
    if ($2!=prev_value) {
        if (cnt>1) {
            print prev_row"-"cnt;
        } else {
            print prev_row;
        }
        cnt=1;
    } else {
        cnt++;
    }
    if (cnt>1) {
        print prev_row"-"(cnt-1);
    }
    prev_row = sprintf("%-15s    %s", $1, $2);
    prev_value = $2;
}

END {
    if (cnt>1) {
        print prev_row"-"cnt;
    } else {
        print prev_row;
    }
}
'

#
# Helper functions
# ------------------------------------------------------------------------------
print_error_line () {
    printf "${RED}-%.0s${NC}" {1..80}
    printf "\n${RED}ERROR! ${1}${NC}\n"
    printf "${RED}-%.0s${NC}" {1..80}
    printf "\n"
}

print_error () {
    printf "\n${B_RED} ERROR! ${1}${NC}\n\n"
}

print_warning () {
    printf "\n${B_YELLOW} ${1}${NC}\n\n"
}

print_success() {
    printf "\n${B_GREEN} ${1} ${NC}\n\n"
}

print_message() {
    printf "${YELLOW}${1}${NC}"
}

print_text() {
    printf "${LIGHT_GRAY}${1}${NC}\n"
}

#
# Start
# ------------------------------------------------------------------------------

#
# Check if AWS CLI is installed, exit if not installed
#
command=$(command -v aws)
if [ -z "${command}" ]; then
    print_error " AWS CLI is not installed! "
    print_message "This script requires AWS CLI v2 to be installed.\n"
    print_message "Please read more on how to install AWS CLI on your system here: https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html\n\n"
    exit 1
fi

reconfigure=0
reset=0

#
# Check if AWS_MFA_ARN environment variable is set
#
if [ -z "${AWS_MFA_ARN}" ]; then
    reconfigure=1;
    reset=1;
fi

#
# Check if oathtool is installed (used to generate MFA token code automatically,
# based on MFA secret key).
# This one is optional so we won't exit.
#
can_generate_mfa_token=0
command=$(command -v oathtool)
if [ ! -z "${command}" ]; then
    can_generate_mfa_token=1
    #
    # In this case also check if AWS_MFA_ARN environment variable is set
    #
    if [ -z "${AWS_MFA_SECRET_KEY}" ]; then
        reconfigure=1;
        reset=1;
    fi
fi

#
# Check if --reconfigure flag is supplied
#
if [ "$1" == "--reconfigure" ]; then
    reconfigure=1;
    reset=1;
fi
#
# Check if --reset flag is supplied
#
if [ "$1" == "--reset" ]; then
    reset=1;
fi

if [ "${reconfigure}" -eq 1 ]; then
    #
    # Get AWS user ARN
    #
    print_message "Please enter your MFA ARN (found on the IAM page for your user account in 'Security credentials' tab under 'Assigned MFA device', https://console.aws.amazon.com/iamv2/home#/users):\n"
    read AWS_MFA_ARN
    print_message "Adding supplied ARN to ~/.bashrc as AWS_MFA_ARN environment variable...\n"
    sed -ri "/AWS_MFA_ARN/d" ~/.bashrc
    echo "export AWS_MFA_ARN=${AWS_MFA_ARN}" >> ~/.bashrc

    if [ "${can_generate_mfa_token}" -eq 1 ]; then
        #
        # Get AWS user MFA secret key
        #
        print_message "Please enter your MFA secret key (found on the IAM page for your user account in 'Security credentials' tab under 'Assigned MFA device', https://console.aws.amazon.com/iamv2/home#/users):\n"
        read AWS_MFA_SECRET_KEY
        print_message "Adding supplied MFA secret key to ~/.bashrc as AWS_MFA_SECRET_KEY environment variable...\n"
        sed -ri "/AWS_MFA_SECRET_KEY/d" ~/.bashrc
        echo "export AWS_MFA_SECRET_KEY=${AWS_MFA_SECRET_KEY}" >> ~/.bashrc
    fi

    print_message "You can reconfigure MFA ARN (and MFA secret key) in the future by supplying --reconfigure flag when executing this script.\n\n"
fi

session_expired=""
ec2_instances_data=""
if [ "${reset}" -eq 0 ]; then
    print_message "Checking if session has expired...\n"
    ec2_instances_data=$(aws ec2 describe-instances --filters "Name=instance-state-name,Values=running" --query 'Reservations[*].Instances[*].[PublicIpAddress, Tags[?Key==`Name`][Value]]' --output text --profile mfa 2>&1)
    #
    # Check if session has expired - if so, we need to update AWS session data
    # Handles "An error occurred (RequestExpired) when calling the DescribeInstances operation: Request has expired." response!
    #
    session_expired=$(grep -Eio 'RequestExpired' /dev/stdin <<< "${ec2_instances_data}" )
fi

if [ "${reset}" -eq 1 ] || [ ! -z "${session_expired}" ]; then
    #
    # Update AWS session data
    #

    #
    # Get (or generate) MFA token code
    #
    aws_mfa_token_code=""
    if [ "${can_generate_mfa_token}" -eq 1 ]; then
        # Generate MFA token code automatically (based on MFA secret key)
        aws_mfa_token_code=$(oathtool -b --totp "${AWS_MFA_SECRET_KEY}")
    fi

    if [ -z "${aws_mfa_token_code}" ]; then
        # Get MFA token code via user input
        print_message "Please enter MFA token code: "
        read aws_mfa_token_code
    fi

    #
    # Get AWS session data
    #
    print_message "Getting AWS session data...\n"
    ec2_session_data=$(aws sts get-session-token --serial-number "${AWS_MFA_ARN}" --token-code "${aws_mfa_token_code}")

    aws_access_key_id=$(echo "${ec2_session_data}" | sed -r -n "s/.+AccessKeyId.\:[^\"]+\"([^\"]+)\",$/\1/p")
    aws_secret_access_key=$(echo "${ec2_session_data}" | sed -r -n "s/.+SecretAccessKey.\:[^\"]+\"([^\"]+)\",$/\1/p")
    aws_session_token=$(echo "${ec2_session_data}" | sed -r -n "s/.+SessionToken.\:[^\"]+\"([^\"]+)\",$/\1/p")

    if [ -z "${aws_access_key_id}" ] || [ -z "${aws_secret_access_key}" ] || [ -z "${aws_session_token}" ]; then
        print_error " Error while trying to get AWS session data! "
        printf "\n${ec2_session_data}\n\n"
        exit 1
    fi

    #
    # Update AWS credentials with new session data
    #
    print_message "Updating mfa profile access credentials...\n"
    sed -r -z -i 's/\[mfa\]\naws_access_key_id[^\n]+\naws_secret_access_key[^\n]+\naws_session_token[^\n]+\n//' $AWS_CLI_CREDENTIALS_PATH
    echo "[mfa]" >> $AWS_CLI_CREDENTIALS_PATH
    echo "aws_access_key_id = ${aws_access_key_id}" >> $AWS_CLI_CREDENTIALS_PATH
    echo "aws_secret_access_key = ${aws_secret_access_key}" >> $AWS_CLI_CREDENTIALS_PATH
    echo "aws_session_token = ${aws_session_token}" >> $AWS_CLI_CREDENTIALS_PATH
    print_message "Done updating AWS session data!\n"

    ec2_instances_data=""
fi

#
# Get relevant EC2 instances IPs
#
print_message "Getting relevant EC2 instances data from AWS...\n"
if [ -z "${ec2_instances_data}" ]; then
    ec2_instances_data=$(aws ec2 describe-instances --filters "Name=instance-state-name,Values=running" --query 'Reservations[*].Instances[*].[PublicIpAddress, Tags[?Key==`Name`][Value]]' --output text --profile mfa)
fi
ec2_instances_data=$(sed -r -z 's/([0-9\.]+)\n/\1 /g' /dev/stdin <<< "${ec2_instances_data}" )
ec2_instances_names_list=$(sed -r -z 's/[0-9\.]+ ([^ ]+)\n/\1|/g' /dev/stdin <<< "${ec2_instances_data}" | sed -r 's/\|[ ]*$//g')
ec2_instances_data=$(cat /dev/stdin <<< "${ec2_instances_data}" | sort -k1 | sort -k2 | awk "${AWK_ADD_NUMBERS}")

#
# Update hosts file with new EC2 instances IPs
#
print_message "Updating ${HOSTS_FILE_PATH} with following new EC2 instances records:\n"
print_text "${ec2_instances_data}\n"
print_message "Do you want to continue (type y to continue): "
read to_continue
if [ "${to_continue}" != "y" ]; then
    print_warning "ABORTING!"
    exit 0;
fi

print_message "Updating ${HOSTS_FILE_PATH}\n"
sudo sed -r -i "/(${ec2_instances_names_list})/d" $HOSTS_FILE_PATH
cat /dev/stdin <<< "${ec2_instances_data}" | sudo tee -a $HOSTS_FILE_PATH > /dev/null

#
# Remove hashed hosts keys
#
print_message "Removing hashed hosts SSH keys...\n"
while IFS= read -r line ; do
    host_name=$(sed -r "s/^[0-9\. ]+//g" /dev/stdin <<< "${line}")
    ssh-keygen -q -f "${KNOWN_HOSTS_FILE_PATH}" -R "${host_name}" > /dev/null 2>&1
done <<< "${ec2_instances_data}"

print_success "All done and ready!"
