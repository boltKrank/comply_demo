#!/bin/sh

# This script will help setup alpha Comply based on the documentation and artifacts found at
# https://drive.google.com/drive/u/0/folders/0AOywIQsKa0wIUk9PVA
# In particular, you will need to download comply-stack.tar, image_helper.sh, and the puppetlabs-comply module
# Place them in a directory and modify the "CR_BASE" variable below to point to that directory
# Add module to Puppetfile: mod 'puppetlabs-comply', '0.9.0'

PROJECT=$1

GIT_BRANCH=production

### INSTALL JQ
sudo yum -y install https://dl.fedoraproject.org/pub/epel/epel-release-latest-7.noarch.rpm
sudo yum install jq -y

### COMPLY SERVER WORK
# Install Replicated/Comply on Comply Node
echo "About to install Replicated and Comply Application Stack."
echo "Please be sure to capture the Kotsadm URL (which should be the IP address"
echo "of ${PROJECT}comply0.classroom.puppet.com) and the randomly generated"
echo "password.  You will need the password to log into kotsadm for the next"
echo "step."
ssh -i ~/.ssh/training.pem -oStrictHostKeyChecking=no centos@${PROJECT}comply0.classroom.puppet.com "sudo setenforce 0; curl -sSL https://k8s.kurl.sh/comply-unstable | sudo bash"
read -rsp $"After copying the URL and password, press any key to continue..." -n1 key

# Need to create Puppet Comply classification and add comply node
TOKEN=`curl -s -S -k -X POST -H 'Content-Type: application/json' -d '{"login": "admin", "password": "puppetlabs"}' https://localhost:4433/rbac-api/v1/auth/token |jq -r '.token'`
curl -s -S -k -X POST -H 'Content-Type: application/json' -H "X-Authentication: $TOKEN" https://localhost:4433/classifier-api/v1/update-classes?environment=${GIT_BRANCH}

WINNODES=`curl -k -G -H 'Content-Type: application/json' -H "X-Authentication: $TOKEN" --data-urlencode 'query=["~","certname","win[0-9]"]' https://localhost:8081/pdb/query/v4/nodes |jq .[].certname |tr -d \"`

LINNODES=`curl -k -G -H 'Content-Type: application/json' -H "X-Authentication: $TOKEN" --data-urlencode 'query=["~","certname","nix[0-9]"]' https://localhost:8081/pdb/query/v4/nodes |jq .[].certname |tr -d \"`

# Windows in Hydra is currently broken and needs to have the FQDN fixed
for HOST in $WINNODES
do
	echo "Fixing FQDN on $HOST"
	bolt command run "\$agent_ip = (Get-NetIPAddress -AddressFamily IPv4 -SuffixOrigin DHCP).IpAddress; \$agent_name = (Get-WmiObject win32_computersystem).DNSHostName; \$agent_host_entry = \"\${agent_ip} ${HOST} \${agent_name}\"; \$agent_host_entry | Out-File -FilePath C:\\Windows\\System32\\Drivers\\etc\\hosts -Append -Encoding ascii" -t winrm://${HOST} --user administrator --password 'Puppetlabs!' --no-ssl
        bolt command run "(GWMI win32_networkadapterconfiguration -filter 'IPEnabled=True').setdnsdomain('classroom.puppet.com')" -t winrm://${HOST} --user administrator --password 'Puppetlabs!' --no-ssl
done

# Add comply to classification of any nodes you want to be scanable
curl -s -S -k -X PUT -H 'Content-Type: application/json' -H "X-Authentication: $TOKEN" -d "{ \"name\": \"Puppet Comply Agents\", \"parent\": \"00000000-0000-4000-8000-000000000000\", \"environment\": \"${GIT_BRANCH}\", \"rule\": [\"~\", [\"fact\",\"clientcert\"], \"[win|nix]\"], \"classes\": {\"comply\": {\"linux_manage_unzip\": true} } }" https://localhost:4433/classifier-api/v1/groups/00000000-2112-4000-8000-000000000012
