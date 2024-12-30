#!/bin/bash

# Check for the existence of the .env file
if [ ! -f .env ]; then
  echo "Error: .env file not found"
  exit 1
fi

# Load environment variables from the .env file
set -a
source .env
set +a

# Assign variables
routerHost=$ROUTER_HOST
routerUser=$ROUTER_USER
sshKeyPath=$SSH_KEY_PATH
domainsFilePath=$DOMAINS_FILE_PATH
localDomainsFile=$LOCAL_DOMAINS_FILE
reloadCommand=$RELOAD_COMMAND

# Verify if all environment variables are set
if [ -z "$routerHost" ] || [ -z "$routerUser" ] || [ -z "$sshKeyPath" ] || [ -z "$domainsFilePath" ] || [ -z "$localDomainsFile" ] || [ -z "$reloadCommand" ]; then
  echo "Error: One or more environment variables are not set"
  exit 1
fi

# Temporary directory
tempDir="tmp"

# Ensure the tmp directory exists
mkdir -p "$tempDir"

# Temporary files
tempRemoteDomains="$tempDir/temp_remote_domains.txt"
tempNormalizedRemoteDomains="$tempDir/temp_normalized_remote_domains.txt"
tempNormalizedLocalDomains="$tempDir/temp_normalized_local_domains.txt"
tempAllDomains="$tempDir/temp_all_domains.txt"
tempFilteredDomains="$tempDir/temp_filtered_domains.txt"

# Read the domain list from the router via SSH
ssh -i "$sshKeyPath" "$routerUser@$routerHost" "cat $domainsFilePath" > "$tempRemoteDomains"

# Merge domain lists and remove empty lines and lines starting with #
< "$tempRemoteDomains" tr -d '\r' > "$tempNormalizedRemoteDomains"
< "$localDomainsFile" tr -d '\r' > "$tempNormalizedLocalDomains"

cat "$tempNormalizedRemoteDomains" "$tempNormalizedLocalDomains" | grep -v '^$' | grep -v '^#' | sort -u > "$tempAllDomains"

# Remove domains listed in the local file with #
grep -vxf <(grep '^#' "$tempNormalizedLocalDomains" | sed 's/^#//') "$tempAllDomains" > "$tempFilteredDomains"

# Read the updated domain list into a variable
updatedDomains=$(cat "$tempFilteredDomains")

# Send the updated domain list back to the router via SSH using echo
ssh -i "$sshKeyPath" "$routerUser@$routerHost" "echo \"$updatedDomains\" > $domainsFilePath"

# Save the updated domain list to the local file
mv "$tempFilteredDomains" "$localDomainsFile"

# Remove the temporary directory and its contents
rm -rf "$tempDir"

# Execute the reload command
ssh -i "$sshKeyPath" "$routerUser@$routerHost" "$reloadCommand"
