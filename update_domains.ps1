# Set error handling preference
$ErrorActionPreference = "Stop"

# Function to format date and time
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
function Check-Tools {
    param (
        [string[]]$tools
    )
    $missingTools = @()
    foreach ($tool in $tools) {
        if (-Not (Get-Command $tool -ErrorAction SilentlyContinue)) {
            $missingTools += $tool
        }
    }
    if ($missingTools.Count -gt 0) {
        $missingTools | ForEach-Object { Log-Message "Error: Required tool '$_' is not installed" }
        LogErrorAndExit "One or more required tools are missing: $($missingTools -join ', ')"
    }
}

$tools = @("ssh")
Check-Tools -tools $tools

# Load environment variables from the .env file if it exists
function Load-Env-Variables {
    param (
        [string]$envFilePath
    )

    if (Test-Path $envFilePath) {
        Get-Content $envFilePath | ForEach-Object {
            # Skip empty lines and comments (#)
            if (-not ($_ -match "^\s*#") -and ($_ -match "^\s*(\w+)\s*=\s*(.*)\s*$")) {
                $name = $matches[1]
                $value = $matches[2].Trim('"')
                # Set the environment variable
                [System.Environment]::SetEnvironmentVariable($name, $value, [System.EnvironmentVariableTarget]::Process)
            }
        }
    }
}

Load-Env-Variables -envFilePath ".env"

# Check environment variables
function Check-Env-Vars {
    param (
        [string[]]$requiredEnvVars
    )
    $errors = @()
    foreach ($envVar in $requiredEnvVars) {
        if (-Not [System.Environment]::GetEnvironmentVariable($envVar, [System.EnvironmentVariableTarget]::Process)) {
            $errors += "Error: Environment variable $envVar is not set"
        }
    }
    if ($errors.Count -gt 0) {
        $errors | ForEach-Object { LogErrorAndExit $_ }
    }
}

$requiredEnvVars = @("ROUTER_HOST", "ROUTER_USER", "SSH_KEY_PATH", "DOMAINS_FILE_PATH", "LOCAL_DOMAINS_FILE", "RELOAD_COMMAND")
Check-Env-Vars -requiredEnvVars $requiredEnvVars

# Assign variables
$routerHost = $env:ROUTER_HOST
$routerUser = $env:ROUTER_USER
$sshKeyPath = $env:SSH_KEY_PATH
$domainsFilePath = $env:DOMAINS_FILE_PATH
$localDomainsFile = $env:LOCAL_DOMAINS_FILE
$removeDomainsFilePath = $env:REMOVE_DOMAINS_FILE_PATH
$localRemoveDomainsFile = $env:LOCAL_REMOVE_DOMAINS_FILE
$reloadCommand = $env:RELOAD_COMMAND

function Process-Domain-Files {
    param (
        [string[]]$remoteDomains,
        [string[]]$localDomains
    )
   
    # Merge domain lists and remove duplicates and empty lines
    $allDomains = @($remoteDomains + $localDomains) | Where-Object { $_ -ne "" -and $_ -notmatch '^#' } | Sort-Object -Unique

    # Remove domains listed in the local file with #
    $deleteDomains = $localDomains | Where-Object { $_ -match '^#' } | ForEach-Object { $_ -replace '^#' }
    $filteredDomains = $allDomains | Where-Object { $_ -notin $deleteDomains }

    if (-not $remoteDomains) { $remoteDomains = @() }
    if (-not $filteredDomains) { $filteredDomains = @() }

    # Log added and removed domains
    $addedDomains = Compare-Object -ReferenceObject $remoteDomains -DifferenceObject $filteredDomains | Where-Object { $_.SideIndicator -eq "=>" } | Select-Object -ExpandProperty InputObject
    $removedDomains = Compare-Object -ReferenceObject $remoteDomains -DifferenceObject $filteredDomains | Where-Object { $_.SideIndicator -eq "<=" } | Select-Object -ExpandProperty InputObject

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
try {
    $remoteDomains = ssh -i $sshKeyPath "$routerUser@$routerHost" "cat $domainsFilePath"
}
catch {
    LogErrorAndExit "Error: Failed to read domains from the router"
}

# Process main domain files
$filteredDomains = Process-Domain-Files -remoteDomains $remoteDomains -localDomains (Get-Content $localDomainsFile)

# Read the updated domain list into a variable
$updatedDomains = $filteredDomains -join "`n"

# Send the updated domain list back to the router via SSH using echo and check for success
try {
    ssh -i $sshKeyPath "$routerUser@$routerHost" "echo `"$updatedDomains`" > $domainsFilePath"
}
catch {
    LogErrorAndExit "Error: Failed to update domains on the router"
}

# Save the updated domain list to the local file
$filteredDomains | Out-File $localDomainsFile

# Process remove domain files if they exist
if ($removeDomainsFilePath -and $localRemoveDomainsFile -and (Test-Path $localRemoveDomainsFile)) {
    $removeDomains = Get-Content $removeDomainsFilePath
    $filteredRemoveDomains = Process-Domain-Files -remoteDomains $removeDomains -localDomains (Get-Content $localRemoveDomainsFile)
    try {
        ssh -i $sshKeyPath "$routerUser@$routerHost" "echo `"$filteredRemoveDomains`" > $removeDomainsFilePath"
        Log-Message "Remove domains file copied to the router successfully"
    }
    catch {
        LogErrorAndExit "Error: Failed to copy remove domains file to the router"
    }
}

# Execute the reload command and check for success
try {
    ssh -i $sshKeyPath "$routerUser@$routerHost" "$reloadCommand"
}
catch {
    LogErrorAndExit "Error: Failed to execute reload command"
}

Log-Message "Script executed successfully"
