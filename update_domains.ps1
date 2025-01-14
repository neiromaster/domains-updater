# Функция для форматирования даты и времени
function Format-Date {
    Get-Date -Format "yyyy/MM/dd-HH:mm:ss"
}

# Log file
$logFile = "update_domains.log"

# Function to log messages with timestamp
function Log-Message {
    param (
        [string]$message
    )
    "$(Format-Date) - $message" | Out-File -FilePath $logFile -Append
}

# Function to log errors and exit
function LogErrorAndExit {
    param (
        [string]$message
    )
    Log-Message "$message"
    Write-Error $message
    exit 1
}

# Log script start
Log-Message "Script started"

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
$removeDomainsFilePath = $env:REMOVE_DOMAINS_FILE_PATH
$localRemoveDomainsFile = $env:LOCAL_REMOVE_DOMAINS_FILE
$reloadCommand = $env:RELOAD_COMMAND

function process_domain_files {
    param (
        [string]$remoteDomains,
        [string]$localDomains
    )

    # Normalize line endings to \n
    $normalizedRemoteDomains = $remoteDomains -replace "`r", "`n" -split "`n" | Where-Object { $_ }
    $normalizedLocalDomains = $localDomains -replace "`r", "`n" -split "`n" | Where-Object { $_ }

    # Merge domain lists and remove duplicates and empty lines
    $allDomains = ($normalizedRemoteDomains + $normalizedLocalDomains) | Where-Object { $_ -ne "" -and $_ -notmatch '^#' } | Sort-Object | Get-Unique

    # Remove domains listed in the local file with #
    $deleteDomains = $normalizedLocalDomains | Where-Object { $_ -match '^#' } | ForEach-Object { $_ -replace '^#' }
    $filteredDomains = $allDomains | Where-Object { $_ -notin $deleteDomains }

    # Log added and removed domains
    $addedDomains = Compare-Object -ReferenceObject $normalizedRemoteDomains -DifferenceObject $filteredDomains | Where-Object { $_.SideIndicator -eq "=>" } | Select-Object -ExpandProperty InputObject
    $removedDomains = Compare-Object -ReferenceObject $normalizedRemoteDomains -DifferenceObject $filteredDomains | Where-Object { $_.SideIndicator -eq "<=" } | Select-Object -ExpandProperty InputObject

    if ($addedDomains.Count -gt 0) {
        Log-Message "Added domains: $($addedDomains -join ', ')"
    }

    if ($removedDomains.Count -gt 0) {
        Log-Message "Removed domains: $($removedDomains -join ', ')"
    }

    # Return the filtered domains as an array
    return $filteredDomains
}

# Read the domain list from the router and check for success
$remoteDomains = ssh -i $sshKeyPath "$routerUser@$routerHost" "cat $domainsFilePath"
if ($LASTEXITCODE -ne 0) {
    LogErrorAndExit "Error: Failed to read domains from the router"
}

# Process main domain files
$filteredDomains = process_domain_files -remoteDomains $remoteDomains -localDomains (Get-Content $localDomainsFile -Raw)

# Process remove domain files if they exist
if ($removeDomainsFilePath -and $localRemoveDomainsFile -and (Test-Path $localRemoveDomainsFile)) {
    $removeDomains = Get-Content $removeDomainsFilePath
    $filteredRemoveDomains = process_domain_files -remoteDomains $removeDomains -localDomains (Get-Content $localRemoveDomainsFile -Raw)
    $scpResult = ssh -i $sshKeyPath "$routerUser@$routerHost" "cat > $removeDomainsFilePath" < $localRemoveDomainsFile
    if ($LASTEXITCODE -ne 0) {
        LogErrorAndExit "Error: Failed to copy remove domains file to the router"
    } else {
        Log-Message "Remove domains file copied to the router successfully"
    }
}

# Read the updated domain list into a variable
$updatedDomains = $filteredDomains -join "`n"

# Send the updated domain list back to the router via SSH using echo and check for success
ssh -i $sshKeyPath "$routerUser@$routerHost" "echo `"$updatedDomains`" > $domainsFilePath"
if ($LASTEXITCODE -ne 0) {
    LogErrorAndExit "Error: Failed to update domains on the router"
}

# Save the updated domain list to the local file
$filteredDomains | Out-File $localDomainsFile

# Execute the reload command and check for success
ssh -i $sshKeyPath "$routerUser@$routerHost" "$reloadCommand"
if ($LASTEXITCODE -ne 0) {
    LogErrorAndExit "Error: Failed to execute reload command"
}

"$(Format-Date) - Script executed successfully" | Out-File -FilePath $logFile -Append
