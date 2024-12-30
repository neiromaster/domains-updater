#!/bin/bash

# Check for the existence of the .env file
if [ ! -f .env ]; then
  echo "Error: .env file not found"
  exit 1
fi

# Load environment variables from the .env file
source .env

# Temporary files
remote_domains_temp="remote_domains.txt"
all_domains_temp="all_domains.txt"
filtered_domains_temp="filtered_domains.txt"

# Read the domain list from the router via SSH
ssh -i "$SSH_KEY_PATH" "$ROUTER_USER@$ROUTER_HOST" "cat $DOMAINS_FILE_PATH" > "$remote_domains_temp"

# Merge domain lists and remove empty lines and lines starting with #
cat "$remote_domains_temp" | tr -d '\r' > "$remote_domains_temp.norm"
cat "$LOCAL_DOMAINS_FILE" | tr -d '\r' > "$LOCAL_DOMAINS_FILE.norm"

cat "$remote_domains_temp.norm" "$LOCAL_DOMAINS_FILE.norm" | grep -v '^$' | grep -v '^#' | sort -u > "$all_domains_temp"

# Remove domains listed in the local file with #
grep -vxf <(grep '^#' "$LOCAL_DOMAINS_FILE.norm" | sed 's/^#//') "$all_domains_temp" > "$filtered_domains_temp"

# Read the updated domain list into a variable
updated_domains=$(cat "$filtered_domains_temp")

# Send the updated domain list back to the router via SSH using echo
ssh -i "$SSH_KEY_PATH" "$ROUTER_USER@$ROUTER_HOST" "echo \"$updated_domains\" > $DOMAINS_FILE_PATH"

# Save the updated domain list to the local file
mv "$filtered_domains_temp" "$LOCAL_DOMAINS_FILE"

# Execute the command to reload the homeproxy service
ssh -i "$SSH_KEY_PATH" "$ROUTER_USER@$ROUTER_HOST" "/etc/init.d/homeproxy reload"

# Remove temporary files
rm "$remote_domains_temp" "$remote_domains_temp.norm" "$LOCAL_DOMAINS_FILE.norm" "$all_domains_temp"
