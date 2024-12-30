# Check for the existence of the .env file
if (-Not (Test-Path .env)) {
    Write-Error "Error: .env file not found"
    exit 1
}

# Load environment variables from the .env file
$envVars = Get-Content .env | ForEach-Object {
    $name, $value = $_ -split '='
    [System.Environment]::SetEnvironmentVariable($name, $value)
}

# Data for connecting to the router
$routerHost = $env:ROUTER_HOST
$routerUser = $env:ROUTER_USER
$sshKeyPath = $env:SSH_KEY_PATH
$domainsFilePath = $env:DOMAINS_FILE_PATH
$localDomainsFile = $env:LOCAL_DOMAINS_FILE

# Temporary files
$tempRemoteDomains = "temp_remote_domains.txt"
$tempNormalizedRemoteDomains = "temp_normalized_remote_domains.txt"
$tempNormalizedLocalDomains = "temp_normalized_local_domains.txt"
$tempAllDomains = "temp_all_domains.txt"
$tempFilteredDomains = "temp_filtered_domains.txt"

# Read the domain list from the router
ssh -i $sshKeyPath "$routerUser@$routerHost" "cat $domainsFilePath" | Out-File $tempRemoteDomains -Encoding utf8

# Normalize line endings to \n and write to new temporary files
Get-Content $tempRemoteDomains | ForEach-Object {$_ -replace "`r", ""} | Set-Content $tempNormalizedRemoteDomains
Get-Content $localDomainsFile | ForEach-Object {$_ -replace "`r", ""} | Set-Content $tempNormalizedLocalDomains

# Merge domain lists and remove duplicates and empty lines
Get-Content $tempNormalizedRemoteDomains, $tempNormalizedLocalDomains | Where-Object {$_ -ne "" -and $_ -notmatch '^#'} | Sort-Object | Get-Unique | Out-File $tempAllDomains -Encoding utf8

# Remove domains listed in the local file with #
$deleteDomains = Get-Content $tempNormalizedLocalDomains | Where-Object {$_ -match '^#'} | ForEach-Object {$_ -replace '^#'}
Get-Content $tempAllDomains | Where-Object {$_ -notin $deleteDomains} | Out-File $tempFilteredDomains -Encoding utf8

# Read the updated domain list into a variable
$updatedDomains = Get-Content $tempFilteredDomains -Raw

# Send the updated domain list back to the router via SSH using echo
ssh -i $sshKeyPath "$routerUser@$routerHost" "echo `"$updatedDomains`" > $domainsFilePath"

# Save the updated domain list to the local file
Copy-Item $tempFilteredDomains $localDomainsFile

# Execute the command to reload the homeproxy service
ssh -i $sshKeyPath "$routerUser@$routerHost" "/etc/init.d/homeproxy reload"

# Remove temporary files
Remove-Item $tempRemoteDomains, $tempNormalizedRemoteDomains, $tempNormalizedLocalDomains, $tempAllDomains, $tempFilteredDomains
