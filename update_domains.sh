#!/bin/bash

# Function to format date and time
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
necessary_tools=("ssh" "grep" "sort")
missing_tools=()

for tool in "${necessary_tools[@]}"; do
  if ! command -v "$tool" &>/dev/null; then
    missing_tools+=("$tool")
  fi
done

# If there are missing tools, log error and exit
if [ ${#missing_tools[@]} -ne 0 ]; then
  for tool in "${missing_tools[@]}"; do
    log_message "Error: Required tool '$tool' is not installed"
  done
  log_error_and_exit "One or more required tools are missing: ${missing_tools[*]}"
fi

# Load environment variables from the .env file if it exists
if [ -f .env ]; then
  set -a
  source .env
  set +a
fi

# Check environment variables
required_env_vars=("ROUTER_HOST" "ROUTER_USER" "SSH_KEY_PATH" "DOMAINS_FILE_PATH" "LOCAL_DOMAINS_FILE" "RELOAD_COMMAND")
errors=""

for var in "${required_env_vars[@]}"; do
  if [ -z "${!var}" ]; then
    errors+="Error: $var variable is not set\n"
  fi
done

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
    local remoteDomains="$1"
    local localDomains="$2"

    # Normalize line endings to \n
    local normalizedRemoteDomains normalizedLocalDomains
    normalizedRemoteDomains=$(echo "$remoteDomains" | tr -d '\r')
    normalizedLocalDomains=$(echo "$localDomains" | tr -d '\r')

    # Merge domain lists and remove empty lines and lines starting with #
    local allDomains
    allDomains=$(echo -e "$normalizedRemoteDomains\n$normalizedLocalDomains" | grep -v '^$' | grep -v '^#' | sort -u)

    # Remove domains listed in the local file with #
    local deleteDomains filteredDomains
    deleteDomains=$(echo "$normalizedLocalDomains" | grep '^#' | sed 's/^#//')
    filteredDomains=$(echo "$allDomains" | grep -vxf <(echo "$deleteDomains"))

    # Log added and removed domains
    local addedDomains removedDomains
    addedDomains=$(comm -13 <(echo "$normalizedRemoteDomains" | sort) <(echo "$filteredDomains" | sort))
    removedDomains=$(comm -23 <(echo "$normalizedRemoteDomains" | sort) <(echo "$filteredDomains" | sort))

    if [ -n "$addedDomains" ]; then
      log_message "Added domains: $(echo "$addedDomains" | tr '\n' ',' | sed 's/,$//; s/,/, /g')"
    fi

    if [ -n "$removedDomains" ]; then
      log_message "Removed domains: $(echo "$removedDomains" | tr '\n' ',' | sed 's/,$//; s/,/, /g')"
    fi

    # Return the filtered domains as a string
    echo "$filteredDomains"
}

# Read the domain list from the router via SSH, handle if the file does not exist
remoteDomains=$(ssh -i "$sshKeyPath" "$routerUser@$routerHost" "[ -f $domainsFilePath ] && cat $domainsFilePath || echo ''")
if [ $? -ne 0 ]; then
  log_error_and_exit "Error: Failed to read domains from the router"
fi

# Process main domain files
updatedDomains=$(process_domain_files "$remoteDomains" "$(cat "$localDomainsFile")")

# Send the updated domain list back to the router via SSH using echo and check for success
if ! ssh -i "$sshKeyPath" "$routerUser@$routerHost" "echo \"$updatedDomains\" > $domainsFilePath"; then
  log_error_and_exit "Error: Failed to update domains on the router"
fi

# Save the updated domain list to the local file
echo "$updatedDomains" >"$localDomainsFile"

# Process remove domain files if they exist
if [ -n "$removeDomainsFilePath" ] && [ -n "$localRemoveDomainsFile" ] && [ -f "$localRemoveDomainsFile" ]; then
    # Read the remove domain list from the router, handle if the file does not exist
    remoteRemoveDomains=$(ssh -i "$sshKeyPath" "$routerUser@$routerHost" "[ -f $removeDomainsFilePath ] && cat $removeDomainsFilePath || echo ''")
    if [ $? -ne 0 ]; then
        log_error_and_exit "Error: Failed to read remove domains from the router"
    fi

    localRemoveDomains=$(cat "$localRemoveDomainsFile")

    # Process remove domain files
    updatedRemoveDomains=$(process_domain_files "$remoteRemoveDomains" "$localRemoveDomains")

    # Send the updated remove domain list back to the router
    if ! ssh -i "$sshKeyPath" "$routerUser@$routerHost" "echo \"$updatedRemoveDomains\" > $removeDomainsFilePath"; then
        log_error_and_exit "Error: Failed to update remove domains on the router"
    fi

    # Save the updated remove domain list to the local file
    echo "$updatedRemoveDomains" > "$localRemoveDomainsFile"
    log_message "Remove domains file processed and updated successfully"
fi

# Execute the reload command and check for success
if ! ssh -i "$sshKeyPath" "$routerUser@$routerHost" "$reloadCommand"; then
  log_error_and_exit "Error: Failed to execute reload command"
fi

log_message "Script executed successfully"
