# ClickToDeploy

The clicktodeploy pattern is a one click deployment pattern used to deploy environments from the google marketplace.  It requires a minimal number of inputs to define the environment, and with those it uses deployment manager, python (and powershell on windows) to automate the end-to-end deployment.

For the original click to deploy search the google cloud marketplace for SQL Server 2016 AlwaysOn Failover cluster instance

It requires 3 files:
  * windows-startup-script-ps1 
    * defaulted on install 
    * downloads the following 2 scripts to c:\C2D
    * runs c:\c2D\sql_install.ps1 as a schedulted task
  * sql_install.ps1 - downloaded from gs://c2d-windows/scripts/sqlserver
    * parameters come from metadata of the instance
      * c2d-property-sa-account       : domain admin account
      * c2d-property-sa-password      : domain admin password
      * c2d-property-domain-dns-name  : Fully qualified domain name
      * sql-nodes                     : pipe delimited list of sql server nodes
    * states are stored in the following keys - create these keys yourself to skip steps
      * $sql_on_domain_reg = "HKLM:\SOFTWARE\Google\SQLOnDomain" 
      * $sql_configured_reg = "HKLM:\SOFTWARE\Google\SQLServerConfigured"
      * $sql_server_task = "HKLM:\SOFTWARE\Google\SQLServerTask"
      * $shares_already_created_reg = "HKLM:\SOFTWARE\Google\SharesCreated"
    * WSFC cluster is setup on node 1
    * AlwaysOn is enabled
    * VIP is configured
  * c2d_base.psm1 - downloaded from gs://c2d-windows/scripts/
  * gce_base.psm1 - pre-installed to C:\Program Files\Google\Compute Engine\sysprep

  The following is the code that defines the downloading process.

``` Powershell

    $script:gce_install_dir = 'C:\Program Files\Google\Compute Engine\sysprep'

    $Script:c2d_scripts_bucket = 'c2d-windows/scripts'
    $Script:install_path="C:\C2D" # Folder for downloads
    $script:show_msgs = $false
    $script:write_to_serial = $false

    # Instance specific variables
    $script_name = 'sql_install.ps1'
    $script_subpath = 'sqlserver'
    $task_name = "SQLInstall"

    # Download the scripts
    # Base Script
    $base_script_path = "$Script:c2d_scripts_bucket/c2d_base.psm1"
    $base_script = "$Script:install_path\c2d_base.psm1"

    # Run Script
    $run_script = "$Script:install_path\$script_name"
    $run_script_path = "$Script:c2d_scripts_bucket/$script_subpath/$script_name"
```

So...
ClickToDeploy depends upon (preinstalled on all windows instances):
1. C:\Program Files\Google\Compute Engine\sysprep\gce_base.psm1

We are downloading:
1. From "gs://c2d-windows/scripts/c2d_base.psm1"
2. To "C:\C2D\c2d_base.psm1"
3. From: "gs://c2d-windows/scripts/sqlserver/sql_install.ps1"
4. To: "C:\C2D\sql_install.ps1"

These are provided for reference purposes in powershell/c2d

### gce_base.ps1 - This provides a library of functions for interfacing with GCE (pre-installed)
   * Get-Metadata
   * Generate-Random_Password
   * Write-Serial-Port
   * Write-Log

### c2d_base.ps1 - Library of c2d flow control libraries
  * Write-Logger - Write log messages to instance log
  * Write-ToReg - Write to registry
  * Runtime config functions for creating configs, variables and waiters
  * Functions for creating and deleting scheduled tasks

### sql_install.ps1 - Everything required to configure alwayson
  * Create a Windows Server Failover Cluster (WSFC)
  * Create an availability group
  * Create a database
  * Backup and restore a database from powershell
  * Create shared folders
  * Join a domain
  * Setup an entire cluster

sql_install.ps1 gets called without any arguments from a scheduled task. It does the following:
  * SetScriptVar - Setup all the variables that will be consumed later in the setup
    * Reads the service account from c2d-property-sa-account
    * Reads domain name (Fully qualified) from c2d-property-domain-dns-name
    * Gets the Netbios domain by splitting domain on '.'
    * Reads sa password from c2d-property-sa-password
    * Reads list of nodes in cluster from sql-nodes into all_nodes
    * sets static ip addresses to 10.x.1.4
    * sets listener ip addresses to 10.x.1.5
    * it is assume the gateway and DC will always be 10.0.0.100
    * keep list of remote nodes (nodes this isnt running on) in remote_nodes
  * SetIP 
    * Set IP addresses in Script:static_ip array
    * Set gateway to 10.0.0.100 in $Script:static_listner_ip
    * Add firewall rules for SQL server (1433) and AlwaysOn (5022) at windows level

On all sql instances:
``` Powershell
    Install-WindowsFeature RSAT-AD-PowerShell
    Install-WindowsFeature Failover-Clustering -IncludeManagementTools
```

``` Powershell
$Script:static_ip=@("10.10.0.3","10.10.0.4","10.10.0.5")
$Script:cluster_name="cluster-dbclus"
$Script:all_nodes_fqdn=@('c2d-sql-01.corp.acme.com','c2d-sql-02.corp.acme.com','c2d-sql-03.corp.acme.com')
New-Cluster -Name $Script:cluster_name -Node $Script:all_nodes_fqdn -NoStorage -StaticAddress $Script:static_ip

```
