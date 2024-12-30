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
$remoteDomainsTemp = "remote_domains.txt"
$allDomainsTemp = "all_domains.txt"
$filteredDomainsTemp = "filtered_domains.txt"

# Read the domain list from the router
ssh -i $sshKeyPath "$routerUser@$routerHost" "cat $domainsFilePath" | Out-File $remoteDomainsTemp -Encoding utf8

# Normalize line endings to \n
Get-Content $remoteDomainsTemp | ForEach-Object {$_ -replace "`r", ""} | Set-Content $remoteDomainsTemp
Get-Content $localDomainsFile | ForEach-Object {$_ -replace "`r", ""} | Set-Content $localDomainsFile

# Merge domain lists and remove duplicates and empty lines
Get-Content $remoteDomainsTemp, $localDomainsFile | Where-Object {$_ -ne "" -and $_ -notmatch '^#'} | Sort-Object | Get-Unique | Out-File $allDomainsTemp -Encoding utf8

# Remove domains listed in the local file with #
$deleteDomains = Get-Content $localDomainsFile | Where-Object {$_ -match '^#'} | ForEach-Object {$_ -replace '^#'}
Get-Content $allDomainsTemp | Where-Object {$_ -notin $deleteDomains} | Out-File $filteredDomainsTemp -Encoding utf8

# Read the updated domain list into a variable
$updatedDomains = Get-Content $filteredDomainsTemp -Raw

# Send the updated domain list back to the router via SSH using echo
ssh -i $sshKeyPath "$routerUser@$routerHost" "echo `"$updatedDomains`" > $domainsFilePath"

# Save the updated domain list to the local file
Copy-Item $filteredDomainsTemp $localDomainsFile

# Execute the command to reload the homeproxy service
ssh -i $sshKeyPath "$routerUser@$routerHost" "/etc/init.d/homeproxy reload"

# Remove temporary files
Remove-Item $remoteDomainsTemp, $allDomainsTemp, $filteredDomainsTemp
