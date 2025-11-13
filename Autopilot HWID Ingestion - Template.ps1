function Get-WindowsAutoPilotInfo
{
    [CmdletBinding(DefaultParameterSetName = 'Default')]
    param (
        [Parameter(Mandatory = $False, ValueFromPipeline = $True, ValueFromPipelineByPropertyName = $True, Position = 0)]
        [alias("DNSHostName", "ComputerName", "Computer")]
        [String[]]$Name = @("localhost"),
        [Parameter(Mandatory = $False)]
        [String]$OutputFile = "",
        [Parameter(Mandatory = $False)]
        [String]$GroupTag = "",
        [Parameter(Mandatory = $False)]
        [String]$AssignedUser = "",
        [Parameter(Mandatory = $False)]
        [Switch]$Append = $false,
        [Parameter(Mandatory = $False)]
        [System.Management.Automation.PSCredential]$Credential = $null,
        [Parameter(Mandatory = $False)]
        [Switch]$Partner = $false,
        [Parameter(Mandatory = $False)]
        [Switch]$Force = $false,
        [Parameter(Mandatory = $True, ParameterSetName = 'Online')]
        [Switch]$Online = $false,
        [Parameter(Mandatory = $False, ParameterSetName = 'Online')]
        [String]$TenantId = "",
        [Parameter(Mandatory = $False, ParameterSetName = 'Online')]
        [String]$AppId = "",
        [Parameter(Mandatory = $False, ParameterSetName = 'Online')]
        [String]$AppSecret = "",
        [Parameter(Mandatory = $False, ParameterSetName = 'Online')]
        [String]$AddToGroup = "",
        [Parameter(Mandatory = $False, ParameterSetName = 'Online')]
        [String]$AssignedComputerName = "",
        [Parameter(Mandatory = $False, ParameterSetName = 'Online')]
        [Switch]$Assign = $false,
        [Parameter(Mandatory = $False, ParameterSetName = 'Online')]
        [Switch]$Reboot = $false
    )
    
    Begin
    {
        # Initialize empty list
        $computers = @()
        
        # If online, make sure we are able to authenticate
        if ($Online)
        {
            
            # Get NuGet
            $provider = Get-PackageProvider NuGet -ErrorAction Ignore
            if (-not $provider)
            {
                Write-Host "Installing provider NuGet"
                Find-PackageProvider -Name NuGet -ForceBootstrap -IncludeDependencies
            }
            
            # Get WindowsAutopilotIntune module (and dependencies)
            $module = Import-Module WindowsAutopilotIntune -PassThru -ErrorAction Ignore
            if (-not $module)
            {
                Write-Host "Installing module WindowsAutopilotIntune"
                Install-Module WindowsAutopilotIntune -Force
            }
            Import-Module WindowsAutopilotIntune -Scope Global
            
            # Connect to Intune
            if ($AppId -ne "")
            {
                $graph = Connect-MSGraphApp -Tenant $TenantId -AppId $AppId -AppSecret $AppSecret
                Write-Host "Connected to Intune tenant $TenantId using app-based authentication (Azure AD authentication not supported)"
            }
            else
            {
                $graph = Connect-MSGraph
                Write-Host "Connected to Intune tenant $($graph.TenantId)"
            }
            
            # Force the output to a file
            if ($OutputFile -eq "")
            {
                $OutputFile = "$($env:TEMP)\autopilot.csv"
            }
        }
    }
    
    Process
    {
        foreach ($comp in $Name)
        {
            $bad = $false
            
            # Get a CIM session
            if ($comp -eq "localhost")
            {
                $session = New-CimSession
            }
            else
            {
                $session = New-CimSession -ComputerName $comp -Credential $Credential
            }
            
            # Get the common properties.
            Write-Verbose "Checking $comp"
            $serial = (Get-CimInstance -CimSession $session -Class Win32_BIOS).SerialNumber
            
            # Get the hash (if available)
            $devDetail = (Get-CimInstance -CimSession $session -Namespace root/cimv2/mdm/dmmap -Class MDM_DevDetail_Ext01 -Filter "InstanceID='Ext' AND ParentID='./DevDetail'")
            if ($devDetail -and (-not $Force))
            {
                $hash = $devDetail.DeviceHardwareData
            }
            else
            {
                $bad = $true
                $hash = ""
            }
            
            # If the hash isn't available, get the make and model
            if ($bad -or $Force)
            {
                $cs = Get-CimInstance -CimSession $session -Class Win32_ComputerSystem
                $make = $cs.Manufacturer.Trim()
                $model = $cs.Model.Trim()
                if ($Partner)
                {
                    $bad = $false
                }
            }
            else
            {
                $make = ""
                $model = ""
            }
            
            # Getting the PKID is generally problematic for anyone other than OEMs, so let's skip it here
            $product = ""
            
            # Depending on the format requested, create the necessary object
            if ($Partner)
            {
                # Create a pipeline object
                $c = New-Object psobject -Property @{
                    "Device Serial Number" = $serial
                    "Windows Product ID"   = $product
                    "Hardware Hash"	       = $hash
                    "Manufacturer name"    = $make
                    "Device model"		   = $model
                }
                # From spec:
                # "Manufacturer Name" = $make
                # "Device Name" = $model
                
            }
            else
            {
                # Create a pipeline object
                $c = New-Object psobject -Property @{
                    "Device Serial Number" = $serial
                    "Windows Product ID"   = $product
                    "Hardware Hash"	       = $hash
                }
                
                if ($GroupTag -ne "")
                {
                    Add-Member -InputObject $c -NotePropertyName "Group Tag" -NotePropertyValue $GroupTag
                }
                if ($AssignedUser -ne "")
                {
                    Add-Member -InputObject $c -NotePropertyName "Assigned User" -NotePropertyValue $AssignedUser
                }
            }
            
            # Write the object to the pipeline or array
            if ($bad)
            {
                # Report an error when the hash isn't available
                Write-Error -Message "Unable to retrieve device hardware data (hash) from computer $comp" -Category DeviceError
            }
            elseif ($OutputFile -eq "")
            {
                $c
            }
            else
            {
                $computers += $c
                Write-Host "Gathered details for device with serial number: $serial"
            }
            
            Remove-CimSession $session
        }
    }
    
    End
    {
        if ($OutputFile -ne "")
        {
            if ($Append)
            {
                if (Test-Path $OutputFile)
                {
                    $computers += Import-CSV -Path $OutputFile
                }
            }
            if ($Partner)
            {
                $computers | Select "Device Serial Number", "Windows Product ID", "Hardware Hash", "Manufacturer name", "Device model" | ConvertTo-CSV -NoTypeInformation | % { $_ -replace '"', '' } | Out-File $OutputFile
            }
            elseif ($AssignedUser -ne "")
            {
                $computers | Select "Device Serial Number", "Windows Product ID", "Hardware Hash", "Group Tag", "Assigned User" | ConvertTo-CSV -NoTypeInformation | % { $_ -replace '"', '' } | Out-File $OutputFile
            }
            elseif ($GroupTag -ne "")
            {
                $computers | Select "Device Serial Number", "Windows Product ID", "Hardware Hash", "Group Tag" | ConvertTo-CSV -NoTypeInformation | % { $_ -replace '"', '' } | Out-File $OutputFile
            }
            else
            {
                $computers | Select "Device Serial Number", "Windows Product ID", "Hardware Hash" | ConvertTo-CSV -NoTypeInformation | % { $_ -replace '"', '' } | Out-File $OutputFile
            }
        }
        if ($Online)
        {
            # Add the devices
            $importStart = Get-Date
            $imported = @()
            $computers | % {
                $imported += Add-AutopilotImportedDevice -serialNumber $_.'Device Serial Number' -hardwareIdentifier $_.'Hardware Hash' -groupTag $_.'Group Tag' -assignedUser $_.'Assigned User'
            }
            
            # Wait until the devices have been imported
            $processingCount = 1
            while ($processingCount -gt 0)
            {
                $current = @()
                $processingCount = 0
                $imported | % {
                    $device = Get-AutopilotImportedDevice -id $_.id
                    if ($device.state.deviceImportStatus -eq "unknown")
                    {
                        $processingCount = $processingCount + 1
                    }
                    $current += $device
                }
                $deviceCount = $imported.Length
                Write-Host "Waiting for $processingCount of $deviceCount to be imported"
                if ($processingCount -gt 0)
                {
                    Start-Sleep 30
                }
            }
            $importDuration = (Get-Date) - $importStart
            $importSeconds = [Math]::Ceiling($importDuration.TotalSeconds)
            $successCount = 0
            $current | % {
                Write-Host "$($device.serialNumber): $($device.state.deviceImportStatus) $($device.state.deviceErrorCode) $($device.state.deviceErrorName)"
                if ($device.state.deviceImportStatus -eq "complete")
                {
                    $successCount = $successCount + 1
                }
            }
            Write-Host "$successCount devices imported successfully. Elapsed time to complete import: $importSeconds seconds"
            
            # Wait until the devices can be found in Intune (should sync automatically)
            $syncStart = Get-Date
            $processingCount = 1
            while ($processingCount -gt 0)
            {
                $autopilotDevices = @()
                $processingCount = 0
                $current | % {
                    if ($device.state.deviceImportStatus -eq "complete")
                    {
                        $device = Get-AutopilotDevice -id $_.state.deviceRegistrationId
                        if (-not $device)
                        {
                            $processingCount = $processingCount + 1
                        }
                        $autopilotDevices += $device
                    }
                }
                $deviceCount = $autopilotDevices.Length
                Write-Host "Waiting for $processingCount of $deviceCount to be synced"
                if ($processingCount -gt 0)
                {
                    Start-Sleep 30
                }
            }
            $syncDuration = (Get-Date) - $syncStart
            $syncSeconds = [Math]::Ceiling($syncDuration.TotalSeconds)
            Write-Host "All devices synced. Elapsed time to complete sync: $syncSeconds seconds"
            
            # Assign the computer name
            if ($AssignedComputerName -ne "")
            {
                $autopilotDevices | % {
                    Set-AutopilotDevice -Id $_.Id -displayName $AssignedComputerName
                }
            }
            
            # Wait for assignment (if specified)
            if ($Assign)
            {
                $assignStart = Get-Date
                $processingCount = 1
                while ($processingCount -gt 0)
                {
                    $processingCount = 0
                    $autopilotDevices | % {
                        $device = Get-AutopilotDevice -id $_.id -Expand
                        if (-not ($device.deploymentProfileAssignmentStatus.StartsWith("assigned")))
                        {
                            $processingCount = $processingCount + 1
                        }
                    }
                    $deviceCount = $autopilotDevices.Length
                    Write-Host "Waiting for $processingCount of $deviceCount to be assigned"
                    if ($processingCount -gt 0)
                    {
                        Start-Sleep 30
                    }
                }
                $assignDuration = (Get-Date) - $assignStart
                $assignSeconds = [Math]::Ceiling($assignDuration.TotalSeconds)
                Write-Host "Profiles assigned to all devices. Elapsed time to complete assignment: $assignSeconds seconds"
                if ($Reboot)
                {
                    Restart-Computer -Force
                }
            }
        }
    }
}


If (-not (Get-InstalledModule PowerShellGet -ErrorAction silentlycontinue))
{
    Try
    {
        Install-PackageProvider NuGet -Force | Out-Null
        Set-PSRepository PSGallery -InstallationPolicy Trusted
        Install-Module PowerShellGet -Force
    }
    Catch
    {
        Write-Host "There was an error installing NuGet or PowerShellGet."
        Exit 1
    }
}
    
Set-ExecutionPolicy -Scope Process -ExecutionPolicy RemoteSigned -Force
#Edit Me!    
$TenantId = "UpdateMe"
$AppId = "UpdateMe"
$AppSecret = "UpdateMe"
    
try
{
    Get-WindowsAutoPilotInfo -Online -GroupTag "Autopilot Devices" -TenantId $TenantId -AppId $AppId -AppSecret $AppSecret
}
catch
{
    $StartError = $_.Exception.Message
    Write-Host "Failed to Import to Autopilot: $StartError"
}
