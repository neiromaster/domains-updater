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

# Verify if all environment variables are set and collect errors
errors=""

if [ -z "$ROUTER_HOST" ]; then
  errors+="Error: ROUTER_HOST variable is not set\n"
fi

if [ -z "$ROUTER_USER" ]; then
  errors+="Error: ROUTER_USER variable is not set\n"
fi

if [ -z "$SSH_KEY_PATH" ]; then
  errors+="Error: SSH_KEY_PATH variable is not set\n"
fi

if [ -z "$DOMAINS_FILE_PATH" ]; then
  errors+="Error: DOMAINS_FILE_PATH variable is not set\n"
fi

if [ -z "$LOCAL_DOMAINS_FILE" ]; then
  errors+="Error: LOCAL_DOMAINS_FILE variable is not set\n"
fi

if [ -z "$RELOAD_COMMAND" ]; then
  errors+="Error: RELOAD_COMMAND variable is not set\n"
fi

# Output all errors and exit if any error is collected
if [ -n "$errors" ]; then
  echo -e "$errors"
  exit 1
fi

# Assign variables
routerHost=$ROUTER_HOST
routerUser=$ROUTER_USER
sshKeyPath=$SSH_KEY_PATH
domainsFilePath=$DOMAINS_FILE_PATH
localDomainsFile=$LOCAL_DOMAINS_FILE
reloadCommand=$RELOAD_COMMAND

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

# Read the domain list from the router via SSH and check for success
if ! ssh -i "$sshKeyPath" "$routerUser@$routerHost" "cat $domainsFilePath" > "$tempRemoteDomains"; then
  echo "Error: Failed to read domains from the router"
  rm -rf "$tempDir"
  exit 1
fi

# Merge domain lists and remove empty lines and lines starting with #
< "$tempRemoteDomains" tr -d '\r' > "$tempNormalizedRemoteDomains"
< "$localDomainsFile" tr -d '\r' > "$tempNormalizedLocalDomains"

cat "$tempNormalizedRemoteDomains" "$tempNormalizedLocalDomains" | grep -v '^$' | grep -v '^#' | sort -u > "$tempAllDomains"

# Remove domains listed in the local file with #
grep -vxf <(grep '^#' "$tempNormalizedLocalDomains" | sed 's/^#//') "$tempAllDomains" > "$tempFilteredDomains"

# Read the updated domain list into a variable
updatedDomains=$(cat "$tempFilteredDomains")

# Send the updated domain list back to the router via SSH using echo and check for success
if ! ssh -i "$sshKeyPath" "$routerUser@$routerHost" "echo \"$updatedDomains\" > $domainsFilePath"; then
  echo "Error: Failed to update domains on the router"
  rm -rf "$tempDir"
  exit 1
fi

# Save the updated domain list to the local file
mv "$tempFilteredDomains" "$localDomainsFile"

# Remove the temporary directory and its contents
rm -rf "$tempDir"

# Execute the reload command and check for success
if ! ssh -i "$sshKeyPath" "$routerUser@$routerHost" "$reloadCommand"; then
  echo "Error: Failed to execute reload command"
  rm -rf "$tempDir"
  exit 1
fi
