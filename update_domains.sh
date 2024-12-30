#!/bin/bash

# Check for the existence of the .env file
if [ ! -f .env ]; then
  echo "Error: .env file not found"
  exit 1
fi

# Load environment variables from the .env file
source .env

# Temporary files
tempRemoteDomains="temp_remote_domains.txt"
tempNormalizedRemoteDomains="temp_normalized_remote_domains.txt"
tempNormalizedLocalDomains="temp_normalized_local_domains.txt"
tempAllDomains="temp_all_domains.txt"
tempFilteredDomains="temp_filtered_domains.txt"

# Read the domain list from the router via SSH
ssh -i "$sshKeyPath" "$routerUser@$routerHost" "cat $domainsFilePath" > "$tempRemoteDomains"

# Merge domain lists and remove empty lines and lines starting with #
cat "$tempRemoteDomains" | tr -d '\r' > "$tempNormalizedRemoteDomains"
cat "$localDomainsFile" | tr -d '\r' > "$tempNormalizedLocalDomains"

cat "$tempNormalizedRemoteDomains" "$tempNormalizedLocalDomains" | grep -v '^$' | grep -v '^#' | sort -u > "$tempAllDomains"

# Remove domains listed in the local file with #
grep -vxf <(grep '^#' "$tempNormalizedLocalDomains" | sed 's/^#//') "$tempAllDomains" > "$tempFilteredDomains"

# Read the updated domain list into a variable
updatedDomains=$(cat "$tempFilteredDomains")

# Send the updated domain list back to the router via SSH using echo
ssh -i "$sshKeyPath" "$routerUser@$routerHost" "echo \"$updatedDomains\" > $domainsFilePath"

# Save the updated domain list to the local file
mv "$tempFilteredDomains" "$localDomainsFile"

# Execute the command to reload the homeproxy service
ssh -i "$sshKeyPath" "$routerUser@$routerHost" "/etc/init.d/homeproxy reload"

# Remove temporary files
rm "$tempRemoteDomains" "$tempNormalizedRemoteDomains" "$tempNormalizedLocalDomains" "$tempAllDomains"
