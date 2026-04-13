<#
    This script natively gathers the Windows Autopilot Hardware Hash using CIM/WMI
    and directly posts it to the Microsoft Intune Graph API using OAuth2 Client Credentials.

    Script should run locally within 5 seconds - it will sit for up to a timeout of 5 minutes waiting Microsoft to refresh the change. Microsoft can take up to 60 minutes to refresh Intune Device list.

    Script: Automated-HWID-Import-for-Autopilot
    Date: April 2026
    Version: 2.0
    Author: Harry Shelton
#>

# ==============================================================================
# === CONFIGURATION - EDIT THIS SECTION ===
# ==============================================================================
#Add your Azure AD App Registration details below:
$TenantId = "UPDATE ME WITH TENANT ID"
$AppId = "UPDATE ME WITH APP ID - SEE HWID API CREATION TOOL FOR HELP"
$AppSecret = "UPDATE ME WITH APP SECRET VALUE - SEE HWID API CREATION TOOL FOR HELPl"

#Set your target Autopilot Group Tag
$GroupTag = "Autopilot Devices"

#Adjust Log settings if needed
$LogFile = "C:\ProgramData\AutopilotIngestion_Log.txt"

#== DO NOT EDIT BELOW HERE ==

# ==============================================================================
# === ELEVATION CHECK - ENSURE YOU RUN THIS AS ADMIN/SYSTEM LEVEL ===
# ==============================================================================
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "[ERROR] This script requires Administrative privileges to extract the Hardware Hash." -ForegroundColor Red
    Write-Host "Please close this window, open PowerShell as Administrator, and run the script again." -ForegroundColor Yellow
    exit 1
}

# ==============================================================================
# === LOGGING ===
# ==============================================================================
#Ensure Transcript Logging is handled if needed
function Write-Log {
    param([string]$Message, [string]$Type = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logOutput = "[$timestamp] [$Type] $Message"
    
    # Write to console for RMM capture
    if ($Type -eq "ERROR") {
        Write-Host $logOutput -ForegroundColor Red
    }
    elseif ($Type -eq "WARNING") {
        Write-Host $logOutput -ForegroundColor Yellow
    }
    else {
        Write-Host $logOutput -ForegroundColor Cyan
    }

    # Write to log file if directory path exists or can be created
    try {
        $logDir = Split-Path $LogFile
        if (-not (Test-Path $logDir)) {
            New-Item -ItemType Directory -Path $logDir -Force | Out-Null
        }
        Add-Content -Path $LogFile -Value $logOutput -ErrorAction SilentlyContinue
    }
    catch {
        # Failsafe if we don't have disk write permissions
    }
}

Write-Log "Starting Autopilot HWID Ingestion Script V2"

# ==============================================================================
# === MAIN SCRIPT ===
# ==============================================================================

#Gather Device Info
Write-Log "Gathering Device Information locally via CIM..."
try {
    #Get Serial Number
    $bios = Get-CimInstance -Class Win32_BIOS -ErrorAction Stop
    $serialNumber = $bios.SerialNumber
    
    #Get Hardware Hash
    $devDetail = Get-CimInstance -Namespace root/cimv2/mdm/dmmap -Class MDM_DevDetail_Ext01 -Filter "InstanceID='Ext' AND ParentID='./DevDetail'" -ErrorAction Stop
    $hardwareHash = $devDetail.DeviceHardwareData
    
    if ([string]::IsNullOrWhiteSpace($hardwareHash)) {
        throw "Hardware Hash returned empty from CIM. This device may not support MDM hardware data extraction."
    }

    Write-Log "Successfully retrieved Hardware Hash for Serial Number: $serialNumber"
}
catch {
    Write-Log "Failed to gather device information: $($_.Exception.Message)" "ERROR"
    exit 1
}

#Authenticate to Microsoft Graph
Write-Log "Authenticating to Microsoft Graph..."
try {
    $tokenUrl = "https://login.microsoftonline.com/$TenantId/oauth2/v2.0/token"
    $body = @{
        client_id     = $AppId
        client_secret = $AppSecret
        scope         = "https://graph.microsoft.com/.default"
        grant_type    = "client_credentials"
    }

    $tokenResponse = Invoke-RestMethod -Uri $tokenUrl -Method Post -Body $body -ContentType "application/x-www-form-urlencoded" -ErrorAction Stop
    $accessToken = $tokenResponse.access_token
    Write-Log "Successfully acquired MS Graph Access Token."
}
catch {
    Write-Log "Authentication failed. Check your Tenant ID, App ID, and App Secret. Error: $($_.Exception.Message)" "ERROR"
    exit 1
}

#Import Device to Intune
Write-Log "Importing device to Intune Graph API..."
$headers = @{
    "Authorization" = "Bearer $accessToken"
    "Content-Type"  = "application/json"
}

try {
    $apiUrl = "https://graph.microsoft.com/v1.0/deviceManagement/importedWindowsAutopilotDeviceIdentities"
    
    $deviceBody = @{
        "@odata.type"        = "#microsoft.graph.importedWindowsAutopilotDeviceIdentity"
        "groupTag"           = $GroupTag
        "serialNumber"       = $serialNumber
        "hardwareIdentifier" = $hardwareHash
        "state"              = @{
            "@odata.type"        = "microsoft.graph.importedWindowsAutopilotDeviceIdentityState"
            "deviceImportStatus" = "unknown"
            "deviceErrorCode"    = 0
            "deviceErrorName"    = ""
        }
    } | ConvertTo-Json -Depth 3

    $importResponse = Invoke-RestMethod -Uri $apiUrl -Method Post -Headers $headers -Body $deviceBody -ErrorAction Stop
    
    if ($importResponse.id) {
        Write-Log "Device upload initiated successfully. Device Registration ID: $($importResponse.id)"
    }
    else {
        Write-Log "Unexpected response from Intune Graph API. Processing ID not returned." "WARNING"
    }

}
catch {
    Write-Log "Failed to post device to Intune Graph API: $($_.Exception.Message)" "ERROR"
    if ($_.ErrorDetails) {
        Write-Log "Error Details: $($_.ErrorDetails.Message)" "ERROR"
    }
    exit 1
}

#Wait for Intune Sync Processing
#Intune queues the upload; it takes a few minutes to process the hardware hash.
$maxWaitSeconds = 300
$waited = 0
$isComplete = $false
$importId = $importResponse.id

Write-Log "Waiting for Intune to validate and import the hardware hash (Timeout: 5 mins)..."
while ($waited -lt $maxWaitSeconds) {
    try {
        $statusUrl = "https://graph.microsoft.com/v1.0/deviceManagement/importedWindowsAutopilotDeviceIdentities/$importId"
        $statusResponse = Invoke-RestMethod -Uri $statusUrl -Method Get -Headers $headers -ErrorAction Stop
        
        $status = $statusResponse.state.deviceImportStatus
        
        if ($status -eq "complete") {
            $isComplete = $true
            Write-Log "Device import processed completely by Intune! Device is now ready for Autopilot."
            break
        }
        elseif ($status -eq "error") {
            Write-Log "Intune reported an error processing the device: $($statusResponse.state.deviceErrorCode) - $($statusResponse.state.deviceErrorName)" "ERROR"
            exit 1
        }
        
    }
    catch {
        Write-Log "Failed to check status. Will retry... Error: $($_.Exception.Message)" "WARNING"
    }
    
    Write-Log "Status is currently '$status'. Waiting 15 seconds..."
    Start-Sleep -Seconds 15
    $waited += 15
}

if (-not $isComplete) {
    Write-Log "Timed out waiting for Intune to report 'complete'. The device is in the Intune queue and should sync eventually." "WARNING"
}

Write-Log "Autopilot HWID Ingestion completed successfully."
exit 0
