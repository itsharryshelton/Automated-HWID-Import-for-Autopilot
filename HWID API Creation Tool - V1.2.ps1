#Written by Harry Shelton - March 2025
#Script Name: HWID API Creation Tool
#Script Version: V1.2

#\\ If you get any errors on the script, run the below command as an admin to update or reinstall your Graph module //
#Install-Module Microsoft.Graph -Scope CurrentUser

#1 - Connect to Microsoft Graph with necessary permissions
Connect-MgGraph -Scopes "Application.ReadWrite.All", "Directory.ReadWrite.All"

#2 - Set the display name for the new app registration, update if you want this changed. This name appears within Entra.
$displayName = "Autopilot HWID Ingestion"
$app = New-MgApplication -DisplayName $displayName

#3 - Setting the API permissions
$resourceAppId = "00000003-0000-0000-c000-000000000000"

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

#Create the RequiredResourceAccess object for the app
$requiredResourceAccess = New-Object Microsoft.Graph.PowerShell.Models.MicrosoftGraphRequiredResourceAccess
$requiredResourceAccess.ResourceAppId = $resourceAppId
$requiredResourceAccess.ResourceAccess = $resourceAccessObjects

#Updating the application with the required permissions
Update-MgApplication -ApplicationId $app.Id -RequiredResourceAccess @($requiredResourceAccess)

#4 - Create a client secret for the application
$secretDescription = "HWID Secret"
$secretExpiry = (Get-Date).AddYears(2)

# Create the password credential (client secret) for the application
$clientSecret = Add-MgApplicationPassword -ApplicationId $app.Id

#Prepare data for CSV (Secret Value can only be captured here at creation)
$secretData = @(
    [PSCustomObject]@{
        "Secret Description" = $secretDescription
        "Secret ID"          = $clientSecret.KeyId
        "Secret Value"       = $clientSecret.SecretText
        "Expiry Date"        = $secretExpiry
    }
)

#Export secret details to CSV - update the csvPath if you want it different
$csvPath = "C:\temp\AppRegistration_Secrets.csv"
$secretData | Export-Csv -Path $csvPath -NoTypeInformation
Write-Host "Client Secret added and details exported to $csvPath"

#Commenting below so doesn't leak secret by accident etc
Write-Host "Client Secret is set to not output to console by default"
#Write-Host "Client Secret is $clientSecret.SecretText"

Disconnect-MgGraph
