EC2 Instances hosts Update Script
=================================



## About

This shell script gets a list of all running EC2 instances and updates local hosts file with new IP addresses.
The list contains the *Name* tag and IP address for each running EC2 instance.



## Prerequisites

This script requires AWS CLI v2 to be installed on the system (https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html).

This script expects MFA to be enabled for current IAM account.

This script also requires user to setup new AWS CLI profile named **mfa** (https://docs.aws.amazon.com/cli/latest/userguide/cli-configure-profiles.html).



## Installation

- Install AWS CLI v2. Follow this guide https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html.
- Create new named profile **mfa**. Follow this guide https://docs.aws.amazon.com/cli/latest/userguide/cli-configure-profiles.html.
- Clone this repo and copy `ec2-hosts-update.sh` to a directory that is included in the PATH (so it can be invoked from anywhere).



## Usage

Run the script and follow the interactive prompt for the first run. All subsequent runs will not have any interactive prompts (unless certain flags are used).