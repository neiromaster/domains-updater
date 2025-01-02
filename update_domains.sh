#!/bin/bash

# Функция для форматирования даты и времени
format_date() {
  date +"%Y/%m/%d-%H:%M:%S"
}

# Log file
LOG_FILE="update_domains.log"

# Function to log messages with timestamp
log_message() {
  echo "$(format_date) - $1" >> "$LOG_FILE"
}

# Function to log errors and exit
log_error_and_exit() {
  log_message "$1"
  rm -rf "$tempDir"
  exit 1
}

# Log script start
log_message "Script started"

# Check for necessary tools
if ! command -v ssh &> /dev/null || ! command -v grep &> /dev/null || ! command -v sort &> /dev/null; then
  log_error_and_exit "Error: Required tools (ssh, grep, sort) are not installed"
fi

# Load environment variables from the .env file if it exists
if [ -f .env ]; then
  set -a
  source .env
  set +a
fi

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
  log_error_and_exit "$errors"
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
  log_error_and_exit "Error: Failed to read domains from the router"
fi

# Merge domain lists and remove empty lines and lines starting with #
< "$tempRemoteDomains" tr -d '\r' > "$tempNormalizedRemoteDomains"
< "$localDomainsFile" tr -d '\r' > "$tempNormalizedLocalDomains"

cat "$tempNormalizedRemoteDomains" "$tempNormalizedLocalDomains" | grep -v '^$' | grep -v '^#' | sort -u > "$tempAllDomains"

# Remove domains listed in the local file with #
grep -vxf <(grep '^#' "$tempNormalizedLocalDomains" | sed 's/^#//') "$tempAllDomains" > "$tempFilteredDomains"

# Read the updated domain list into a variable
updatedDomains=$(cat "$tempFilteredDomains")

# Log added and removed domains
currentDomains=$(cat "$tempNormalizedRemoteDomains")
newDomains=$(cat "$tempFilteredDomains")

addedDomains=$(comm -13 <(echo "$currentDomains" | sort) <(echo "$newDomains" | sort))
removedDomains=$(comm -23 <(echo "$currentDomains" | sort) <(echo "$newDomains" | sort))

if [ -n "$addedDomains" ]; then
  log_message "Added domains: $(echo "$addedDomains" | tr '\n' ', ' | sed 's/, $//')"
fi

if [ -n "$removedDomains" ]; then
  log_message "Removed domains: $(echo "$removedDomains" | tr '\n' ', ' | sed 's/, $//')"
fi

# Send the updated domain list back to the router via SSH using echo and check for success
if ! ssh -i "$sshKeyPath" "$routerUser@$routerHost" "echo \"$updatedDomains\" > $domainsFilePath"; then
  log_error_and_exit "Error: Failed to update domains on the router"
fi

# Save the updated domain list to the local file
mv "$tempFilteredDomains" "$localDomainsFile"

# Remove the temporary directory and its contents
rm -rf "$tempDir"

# Execute the reload command and check for success
if ! ssh -i "$sshKeyPath" "$routerUser@$routerHost" "$reloadCommand"; then
  log_error_and_exit "Error: Failed to execute reload command"
fi

echo "$(format_date) - Script executed successfully" >> "$LOG_FILE"
