#!/bin/bash

# Функция для форматирования даты и времени
format_date() {
  date +"%Y/%m/%d-%H:%M:%S"
}

# Log file
LOG_FILE="update_domains.log"

# Function to log messages with timestamp
log_message() {
  echo "$(format_date) - $1" >>"$LOG_FILE"
}

# Function to log errors and exit
log_error_and_exit() {
  log_message "$1"
  exit 1
}

# Log script start
log_message "Script started"

# Check for necessary tools
if ! command -v ssh &>/dev/null || ! command -v grep &>/dev/null || ! command -v sort &>/dev/null; then
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
removeDomainsFilePath=$REMOVE_DOMAINS_FILE_PATH
localRemoveDomainsFile=$LOCAL_REMOVE_DOMAINS_FILE
reloadCommand=$RELOAD_COMMAND

process_domain_files() {
    local remoteDomainsFile="$1"
    local localDomainsFile="$2"

    # Normalize line endings to \n
    local normalizedRemoteDomains=$(<"$remoteDomainsFile" tr -d '\r')
    local normalizedLocalDomains=$(<"$localDomainsFile" tr -d '\r')

    # Merge domain lists and remove empty lines and lines starting with #
    local allDomains=$(echo "$normalizedRemoteDomains" "$normalizedLocalDomains" | grep -v '^$' | grep -v '^#' | sort -u)

    # Remove domains listed in the local file with #
    local deleteDomains=$(echo "$normalizedLocalDomains" | grep '^#' | sed 's/^#//')
    local filteredDomains=$(echo "$allDomains" | grep -vxf <(echo "$deleteDomains"))

    # Log added and removed domains
    local addedDomains=$(comm -13 <(echo "$normalizedRemoteDomains" | sort) <(echo "$filteredDomains" | sort))
    local removedDomains=$(comm -23 <(echo "$normalizedRemoteDomains" | sort) <(echo "$filteredDomains" | sort))

    if [ -n "$addedDomains" ]; then
      log_message "Added domains: $(echo "$addedDomains" | tr '\n' ',' | sed 's/,$//; s/,/, /g')"
    fi

    if [ -n "$removedDomains" ]; then
      log_message "Removed domains: $(echo "$removedDomains" | tr '\n' ',' | sed 's/,$//; s/,/, /g')"
    fi

    # Return the filtered domains as a string
    echo "$filteredDomains"
}

# Read the domain list from the router via SSH and check for success
read -r -d '' remoteDomains < <(ssh -i "$sshKeyPath" "$routerUser@$routerHost" "cat $domainsFilePath")
if [ $? -ne 0 ]; then
  log_error_and_exit "Error: Failed to read domains from the router"
fi

# Process main domain files
filteredDomains=$(process_domain_files "$remoteDomains" "$localDomainsFile")

# Process remove domain files if they exist
if [ -n "$removeDomainsFilePath" ] && [ -n "$localRemoveDomainsFile" ] && [ -f "$localRemoveDomainsFile" ]; then
    read -r -d '' removeDomains < <(cat "$removeDomainsFilePath")
    filteredRemoveDomains=$(process_domain_files "$removeDomains" "$localRemoveDomainsFile")
    if ! ssh -i "$sshKeyPath" "$routerUser@$routerHost" "cat > $removeDomainsFilePath" < "$localRemoveDomainsFile"; then
        log_error_and_exit "Error: Failed to copy remove domains file to the router"
    else
        log_message "Remove domains file copied to the router successfully"
    fi
fi

# Read the updated domain list into a variable
updatedDomains="$filteredDomains"

# Send the updated domain list back to the router via SSH using echo and check for success
if ! ssh -i "$sshKeyPath" "$routerUser@$routerHost" "echo \"$updatedDomains\" > $domainsFilePath"; then
  log_error_and_exit "Error: Failed to update domains on the router"
fi

# Save the updated domain list to the local file
echo "$filteredDomains" >"$localDomainsFile"

# Execute the reload command and check for success
if ! ssh -i "$sshKeyPath" "$routerUser@$routerHost" "$reloadCommand"; then
  log_error_and_exit "Error: Failed to execute reload command"
fi

echo "$(format_date) - Script executed successfully" >>"$LOG_FILE"
