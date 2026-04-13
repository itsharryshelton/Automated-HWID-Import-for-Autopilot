<#
    Creates an Entra ID Registration with the necessary Microsoft Graph 
    API permissions to support the Automated Autopilot HWID Ingestion scripts.
    Generates a client secret and exports the details to a local CSV.

    This script is NOT for deploying to Endpoints; it is a one-time setup from the Admin's Machine to quickly deploy the required API. The "Autopilot HWID Ingestion - Template.ps1" is the one for Endpoints.

    Script: HWID API Creation Tool - V2.0
    Date: April 2026
    Version: 2.0
    Author: Harry Shelton
#>

# ==============================================================================
# === Pre-Req Checks to ensure Graph.Applications installed correctly ===
# ==============================================================================
Write-Host "Starting HWID API Creation Tool V2..." -ForegroundColor Cyan

# Check if Graph Module is installed
if (-not (Get-Module -ListAvailable -Name Microsoft.Graph.Applications)) {
    Write-Host "[ERROR] Microsoft.Graph module is missing." -ForegroundColor Red
    Write-Host "Please run PowerShell as Administrator and execute:" -ForegroundColor Yellow
    Write-Host "Install-Module Microsoft.Graph -Scope CurrentUser" -ForegroundColor Yellow
    exit 1
}

# ==============================================================================
# === MAIN SCRIPT ===
# ==============================================================================

try {
    #Connect to Microsoft Graph
    Write-Host "`n[1/5] Connecting to Microsoft Graph..." -ForegroundColor Cyan
    Connect-MgGraph -Scopes "Application.ReadWrite.All", "Directory.ReadWrite.All" -NoWelcome
    Write-Host "Successfully connected to Graph." -ForegroundColor Green

    #Create the App Reg
    Write-Host "`n[2/5] Creating App Registration..." -ForegroundColor Cyan
    $displayName = "Autopilot HWID Ingestion"
    $app = New-MgApplication -DisplayName $displayName
    Write-Host "App Registration '$displayName' created successfully. (App ID: $($app.AppId))" -ForegroundColor Green

    #Configure API Permissions - do not adjust, unless Microsoft updates requirements.
    Write-Host "`n[3/5] Assigning API Permissions..." -ForegroundColor Cyan
    $resourceAppId = "00000003-0000-0000-c000-000000000000" # Microsoft Graph API

    $requiredPermissions = @(
        @{ Type = "Scope"; Id = "e1fe6dd8-ba31-4d61-89e7-88639da4683d" }, # Delegated: DeviceManagementManagedDevices.ReadWrite.All
        @{ Type = "Role"; Id = "d07a8cc0-3d51-4b77-b3b0-32704d1f69fa" }, # Application: DeviceManagementManagedDevices.ReadWrite.All
        @{ Type = "Role"; Id = "b0afded3-3588-46d8-8b3d-9842eff778da" }, # Application: DeviceManagementServiceConfig.ReadWrite.All
        @{ Type = "Role"; Id = "7438b122-aefc-4978-80ed-43db9fcc7715" }, # Application: Group.ReadWrite.All
        @{ Type = "Role"; Id = "243333ab-4d21-40cb-a475-36241daa0842" }, # Application: GroupMember.ReadWrite.All
        @{ Type = "Role"; Id = "5ac13192-7ace-4fcf-b828-1a26f28068ee" }, # Application: Policy.ReadWrite.DeviceConfiguration
        @{ Type = "Role"; Id = "dbaae8cf-10b5-4b86-a4a1-f871c94c6695" }, # Application: Directory.ReadWrite.All
        @{ Type = "Role"; Id = "9241abd9-d0e6-425a-bd4f-47ba86e767a4" }, # Application: DeviceManagementConfiguration.ReadWrite.All
        @{ Type = "Role"; Id = "e330c4f0-4170-414e-a55a-2f022ec2b57b" }, # Application: DeviceManagementRBAC.ReadWrite.All
        @{ Type = "Role"; Id = "9255e99d-faf5-445e-bbf7-cb71482737c4" }, # Application: DeviceManagementScripts.ReadWrite.All
        @{ Type = "Role"; Id = "5b07b0dd-2377-4e44-a38d-703f09a0dc3c" }, # Application: DeviceManagementManagedDevices.PrivilegedOperations.All
        @{ Type = "Role"; Id = "78145de6-330d-4800-a6ce-494ff2d33d07" }, # Application: DeviceManagementApps.ReadWrite.All
        @{ Type = "Role"; Id = "df021288-bdef-4463-88db-98f22de89214" }  # Application: User.Read.All
    )

    $resourceAccessObjects = @()
    foreach ($permission in $requiredPermissions) {
        $resourceAccess = New-Object Microsoft.Graph.PowerShell.Models.MicrosoftGraphResourceAccess
        $resourceAccess.Id = $permission.Id
        $resourceAccess.Type = $permission.Type
        $resourceAccessObjects += $resourceAccess
    }

    $requiredResourceAccess = New-Object Microsoft.Graph.PowerShell.Models.MicrosoftGraphRequiredResourceAccess
    $requiredResourceAccess.ResourceAppId = $resourceAppId
    $requiredResourceAccess.ResourceAccess = $resourceAccessObjects

    Update-MgApplication -ApplicationId $app.Id -RequiredResourceAccess @($requiredResourceAccess)
    Write-Host "Permissions assigned. (Note: Admin consent must still be granted in the Entra Portal)" -ForegroundColor Yellow

    #Create a Client Secret
    Write-Host "`n[4/5] Generating Client Secret..." -ForegroundColor Cyan
    $secretDescription = "HWID Secret"
    $secretExpiry = (Get-Date).AddYears(2)
    
    $passwordCredential = @{
        DisplayName = $secretDescription
        EndDateTime = $secretExpiry
    }

    $clientSecret = Add-MgApplicationPassword -ApplicationId $app.Id -PasswordCredential $passwordCredential
    Write-Host "Client secret generated successfully." -ForegroundColor Green

    #Export Data to CSV
    Write-Host "`n[5/5] Exporting Secret Details..." -ForegroundColor Cyan
    
    $exportDir = "C:\temp"
    if (-not (Test-Path $exportDir)) {
        New-Item -ItemType Directory -Path $exportDir -Force | Out-Null
    }

    $csvPath = "$exportDir\AppRegistration_Secrets.csv"
    
    $secretData = [PSCustomObject]@{
        "App Name"           = $displayName
        "Application ID"     = $app.AppId
        "Secret Description" = $secretDescription
        "Secret ID"          = $clientSecret.KeyId
        "Secret Value"       = $clientSecret.SecretText
        "Expiry Date"        = $secretExpiry.ToString("yyyy-MM-dd HH:mm:ss")
    }

    $secretData | Export-Csv -Path $csvPath -NoTypeInformation
    
    Write-Host "`n==================================================" -ForegroundColor Green
    Write-Host "SUCCESS! App Registration Setup Complete." -ForegroundColor Green
    Write-Host "==================================================" -ForegroundColor Green
    Write-Host "Your Tenant App ID and Secret have been exported to: $csvPath" -ForegroundColor White
    Write-Host "Please store the 'Secret Value' securely, as it cannot be retrieved again." -ForegroundColor Yellow
    
}
catch {
    Write-Host "`n[ERROR] An unexpected error occurred: $($_.Exception.Message)" -ForegroundColor Red
}
finally {
    #Ensure disconnect cleanly
    if (Get-MgContext) {
        Disconnect-MgGraph | Out-Null
        Write-Host "`nDisconnected from Microsoft Graph." -ForegroundColor Gray
    }
}