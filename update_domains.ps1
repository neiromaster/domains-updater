# Функция для форматирования даты и времени
function Format-Date {
    Get-Date -Format "yyyy/MM/dd-HH:mm:ss"
}

# Log file
$logFile = "update_domains.log"
"$(Format-Date) - Starting script execution" | Out-File -FilePath $logFile

# Function to log errors and exit
function LogErrorAndExit {
    param (
        [string]$message
    )
    "$(Format-Date) - $message" | Tee-Object -Variable errorMessage | Out-File -FilePath $logFile -Append
    Remove-Item -Recurse -Force $tempDir
    Write-Error $errorMessage
    exit 1
}

# Check for necessary tools
if (-Not (Get-Command ssh -ErrorAction SilentlyContinue)) {
    LogErrorAndExit "Error: Required tool 'ssh' is not installed"
}

# Load environment variables from the .env file if it exists
$envFilePath = ".env"
if (Test-Path $envFilePath) {
    Get-Content $envFilePath | ForEach-Object {
        # Skip empty lines and comments (#)
        if (-not ($_ -match "^\s*#") -and ($_ -match "^\s*(\w+)\s*=\s*(.*)\s*$")) {
            $name = $matches[1]
            $value = $matches[2]

            $value = $value.Trim('"')
            # Set the environment variable
            [System.Environment]::SetEnvironmentVariable($name, $value, [System.EnvironmentVariableTarget]::Process)
        }
    }
}

# Check environment variables
$requiredEnvVars = @("ROUTER_HOST", "ROUTER_USER", "SSH_KEY_PATH", "DOMAINS_FILE_PATH", "LOCAL_DOMAINS_FILE", "RELOAD_COMMAND")
$errors = @()

foreach ($envVar in $requiredEnvVars) {
    if (-Not [System.Environment]::GetEnvironmentVariable($envVar, [System.EnvironmentVariableTarget]::Process)) {
        $errors += "Error: Environment variable $envVar is not set"
    }
}

# Output all errors and exit if any error is collected
if ($errors.Count -gt 0) {
    foreach ($error in $errors) {
        LogErrorAndExit "$error"
    }
}

# Assign variables
$routerHost = $env:ROUTER_HOST
$routerUser = $env:ROUTER_USER
$sshKeyPath = $env:SSH_KEY_PATH
$domainsFilePath = $env:DOMAINS_FILE_PATH
$localDomainsFile = $env:LOCAL_DOMAINS_FILE
$reloadCommand = $env:RELOAD_COMMAND

# Temporary directory
$tempDir = "tmp"

# Ensure the tmp directory exists
if (-Not (Test-Path $tempDir)) {
    New-Item -ItemType Directory -Path $tempDir
}

# Temporary files
$tempRemoteDomains = "$tempDir/temp_remote_domains.txt"
$tempNormalizedRemoteDomains = "$tempDir/temp_normalized_remote_domains.txt"
$tempNormalizedLocalDomains = "$tempDir/temp_normalized_local_domains.txt"
$tempAllDomains = "$tempDir/temp_all_domains.txt"
$tempFilteredDomains = "$tempDir/temp_filtered_domains.txt"

# Read the domain list from the router and check for success
$readDomains = ssh -i $sshKeyPath "$routerUser@$routerHost" "cat $domainsFilePath"
if ($LASTEXITCODE -ne 0) {
    LogErrorAndExit "Error: Failed to read domains from the router"
}
$readDomains | Out-File $tempRemoteDomains -Encoding utf8

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

# Log added and removed domains
$currentDomains = Get-Content $tempNormalizedRemoteDomains
$newDomains = Get-Content $tempFilteredDomains

$addedDomains = Compare-Object -ReferenceObject $currentDomains -DifferenceObject $newDomains | Where-Object { $_.SideIndicator -eq "=>" } | Select-Object -ExpandProperty InputObject
$removedDomains = Compare-Object -ReferenceObject $currentDomains -DifferenceObject $newDomains | Where-Object { $_.SideIndicator -eq "<=" } | Select-Object -ExpandProperty InputObject

if ($addedDomains.Count -gt 0) {
    "$(Format-Date) - Added domains: $($addedDomains -join ', ')" | Out-File -FilePath $logFile -Append
}

if ($removedDomains.Count -gt 0) {
    "$(Format-Date) - Removed domains: $($removedDomains -join ', ')" | Out-File -FilePath $logFile -Append
}

# Send the updated domain list back to the router via SSH using echo and check for success
ssh -i $sshKeyPath "$routerUser@$routerHost" "echo `"$updatedDomains`" > $domainsFilePath"
if ($LASTEXITCODE -ne 0) {
    LogErrorAndExit "Error: Failed to update domains on the router"
}

# Save the updated domain list to the local file
Copy-Item $tempFilteredDomains $localDomainsFile

# Remove the temporary directory and its contents
Remove-Item -Recurse -Force $tempDir

# Execute the reload command and check for success
ssh -i $sshKeyPath "$routerUser@$routerHost" "$reloadCommand"
if ($LASTEXITCODE -ne 0) {
    LogErrorAndExit "Error: Failed to execute reload command"
}

"$(Format-Date) - Script executed successfully" | Out-File -FilePath $logFile -Append
