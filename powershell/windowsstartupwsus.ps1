$BUCKET='barry-sandbox-software'
$tempdir = "c:\temp\"
$tempdir = $tempdir.tostring()
$appToMatch = '*puppet*'
$msiFile = "C:\Windows\system32\msiexec.exe"

$puppetInstall = "puppet-agent-x64-latest.msi"
$LOG='c:\temp\install.log'

#function to write debugging info to the console
Function Write-SerialPort ([string] $message) {
    $port = new-Object System.IO.Ports.SerialPort COM1,9600,None,8,one
    $port.open()
    $port.WriteLine($message)
    $port.Close()
}

function Get-InstalledApps
{
    if ([IntPtr]::Size -eq 4) {
        $regpath = 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*'
    }
    else {
        $regpath = @(
            'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*'
            'HKLM:\Software\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
        )
    }
    Get-ItemProperty $regpath | .{process{if($_.DisplayName -and $_.UninstallString) { $_ } }} | Select DisplayName, Publisher, InstallDate, DisplayVersion, UninstallString |Sort DisplayName
}

$result = Get-InstalledApps | where {$_.DisplayName -like $appToMatch}


If (-NOT ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator))
{
  # Relaunch as an elevated process:
  Write-SerialPort "Elevating"
  Start-Process powershell.exe "-File",('"{0}"' -f $MyInvocation.MyCommand.Path) -Verb RunAs
  exit
}

Write-SerialPort "Prefix: ${environment} Name: ${projectname}"
Write-SerialPort "Elevated"

#create temp directory if it doesn't exist
if(!(Test-Path -Path $tempdir )){
  New-Item $tempdir -itemtype directory
}

#Puppet install downloaded to temp
Read-GcsObject $BUCKET $puppetInstall -OutFile "$tempdir\$puppetInstall" -Force

# Now running elevated so launch the script:
If ($result -eq $null) {
    #Install Puppet
    Write-Host "RUN"
    #msiexec.exe /qn /norestart /i $tempdir\$puppetInstall PUPPET_AGENT_ENVIRONMENT=${puppetenvironment} PUPPET_MASTER_SERVER=${environment}-puppet-p.c.${projectname}.internal  /l* $LOG
    #setup DNS
    $dns_server_list = (Get-DnsClientServerAddress -InterfaceAlias "Ethernet" -AddressFamily "IPv4").ServerAddresses -join ","
    Write-Host $dns_server_list
    $count= $dns_server_list | measure-object -character | select -expandproperty characters
    Write-Host $count
    if ($count -le 14 -AND $dns_server_list  -notlike "*,*")
    {
        Write-Host "Add DNS Servers"
        Set-DnsClientServerAddress -InterfaceIndex (get-netadapter -name "Ethernet").IfIndex -ServerAddresses ("${dnsserver1}","${dnsserver2}",$dns_server_list)
    }
    else
    {
        Write-Host "DNS Server Additions Skipped"
    }
    #Install WSUS
    Write-Host "Install WSUS"
    Install-WindowsFeature -ComputerName ${environment}-p-wsus${number} -Name Updateservices,UpdateServices-WidDB,UpdateServices-services  -IncludeManagementTools
    cd 'C:\Program Files\Update Services\tools\'
    Write-Host "Set Content Location"
    .\wsusutil.exe postinstall CONTENT_DIR=c:\WSUS
    Write-Host "Get WSUS Server Object" -Verbose
    $wsus = Get-WSUSServer
    Write-Host "Create the Target Groups"
    $wsus.CreateComputerTargetGroup("tms")
    $wsus.CreateComputerTargetGroup("sce")
    $wsus.CreateComputerTargetGroup("windowsbastion")
    $wsus.CreateComputerTargetGroup("wcs")

    Write-Host "Connect to WSUS server configuration" -Verbose
    $wsusConfig = $wsus.GetConfiguration()

    Write-Host "Set to download updates from Microsoft Updates" -Verbose
    Set-WsusServerSynchronization -SyncFromMU

    Write-Host "Set Update Languages to English and save configuration settings" -Verbose
    $wsusConfig.AllUpdateLanguagesEnabled = $false
    $wsusConfig.SetEnabledUpdateLanguages("en")
    Write-Host "Set initialized to true so the wizard does not load"
    $wsusConfig.OobeInitialized = $true
    #$wsusConfig.SetTargetingMode("Client")
    $wsusConfig.Save()

    Write-Host "Get WSUS Subscription and perform initial synchronization to get latest categories" -Verbose
    $subscription = $wsus.GetSubscription()
    $subscription.StartSynchronizationForCategoryOnly()

     While ($subscription.GetSynchronizationStatus() -ne 'NotProcessing') {
      Write-Host "processing"
     Start-Sleep -Seconds 5
     }

    Write-Host "Sync is Done" -Verbose

    Write-Host "Disable Products" -Verbose
    Get-WsusServer | Get-WsusProduct | Where-Object -FilterScript { $_.product.title -match "Office" } | Set-WsusProduct -Disable
    Get-WsusServer | Get-WsusProduct | Where-Object -FilterScript { $_.product.title -match "Windows" } | Set-WsusProduct -Disable

    Write-Host "Enable Products" -Verbose
    Get-WsusServer | Get-WsusProduct | Where-Object -FilterScript { $_.product.title -match "Windows Server 2016" } | Set-WsusProduct
    Get-WsusServer | Get-WsusProduct | Where-Object -FilterScript { $_.product.title -match "Windows Server 2012" } | Set-WsusProduct
    Get-WsusServer | Get-WsusProduct | Where-Object -FilterScript { $_.product.title -match "SQL Server" } | Set-WsusProduct
    Get-WsusServer | Get-WsusProduct | Where-Object -FilterScript { $_.product.title -match "Active Directory" } | Set-WsusProduct
    Get-WsusServer | Get-WsusProduct | Where-Object -FilterScript { $_.product.title -match "ASP.NET" } | Set-WsusProduct
    Get-WsusServer | Get-WsusProduct | Where-Object -FilterScript { $_.product.title -match "Developer Tools, Runtimes, and Redistributables" } | Set-WsusProduct

    Write-Host "Disable Language Packs" -Verbose
    Get-WsusServer | Get-WsusProduct | Where-Object -FilterScript { $_.product.title -match "Language Packs" } | Set-WsusProduct -Disable

    Write-Host "Configure the Classifications" -Verbose

     Get-WsusClassification | Where-Object {
     $_.Classification.Title -in (
     'Critical Updates',
     'Definition Updates',
     'Feature Packs',
     'Security Updates',
     'Service Packs',
     'Update Rollups',
     'Updates')
     } | Set-WsusClassification

    Write-Host "Configure Synchronizations" -Verbose
    $subscription.SynchronizeAutomatically=$true

    Write-Host "Set synchronization scheduled for midnight each night" -Verbose
    $subscription.SynchronizeAutomaticallyTimeOfDay= (New-TimeSpan -Hours 0)
    $subscription.NumberOfSynchronizationsPerDay=1
    $subscription.Save()

    Write-Host "Kick Off Synchronization" -Verbose
    $subscription.StartSynchronization()
    Write-Host "Monitor Progress of Synchronisation" -Verbose
    Start-Sleep -Seconds 60 # Wait for sync to start before monitoring
    Write-Host $subscription.GetSynchronizationProgress().TotalItems
     while ($subscription.GetSynchronizationProgress().ProcessedItems -ne $subscription.GetSynchronizationProgress().TotalItems)
     {
     Write-Host $subscription.GetSynchronizationProgress().ProcessedItems
     Start-Sleep -Seconds 5
     }

     Write-Host "remove the default web site"
     Remove-Website 'Default Web Site'
     Write-Host "Remove Private memory Limit for apppool"
     import-module webadministration

     $applicationPoolsPath = "/system.applicationHost/applicationPools"
     $applicationPools = Get-WebConfiguration $applicationPoolsPath

     foreach ($appPool in $applicationPools.Collection)
     {
         $appPoolPath = "$applicationPoolsPath/add[@name='$($appPool.Name)']"
         Get-WebConfiguration "$appPoolPath/recycling/periodicRestart/@privateMemory"
         #app pool will recycle and crash if this is not set causing wsus server to fail
         Set-WebConfiguration "$appPoolPath/recycling/periodicRestart/@privateMemory" -Value 0
     }
     Write-Host "restart iis"
     iisreset.exe
     Write-Host "Install report viewer prerequisites"
     Read-GcsObject $BUCKET SQLSysClrTypes.msi -OutFile "$tempdir\SQLSysClrTypes.msi" -Force
     msiexec.exe /qn /norestart /i "$tempdir\SQLSysClrTypes.msi"
     Write-Host "Install report-viewer"
     #reportviewer install downloaded to temp
     Read-GcsObject $BUCKET ReportViewer.msi -OutFile "$tempdir\ReportViewer.msi" -Force
     msiexec.exe /qn /norestart /i "$tempdir\ReportViewer.msi"
    Write-Host "Complete"
}
