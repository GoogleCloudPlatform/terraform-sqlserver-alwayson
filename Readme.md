# Automated Terraform AlwaysOn deployment

## What is the Goal?

This will deploy a Windows environment on to Google Cloud Platform (GCP). This will include Windows Servers with SQL Server installed with AlwaysOn AG. 

## Time Considerations

The creation of the infrastructure is just the start, which takes about 4 minutes.

It then takes about 15 minutes for the domain controller to get configured.  The SQL Server VMs will wait for this to happen. After the domain controller has completed the SQL Server VMs will take an approximately 10 more minutes.

## Permissions

Before you start running Terraform, you need to create a service account in your project for Terraform to run as.  Under IAM and Admin --> Service accounts, create a serice account and then download the key.
Give the service account the permissions it needs to create infrastructure in your project.

Upload the key to wherever you are running the terraform and set GOOGLE_APPLICATION_CREDENTIALS to use this key ( or follow adding credntials in https://www.terraform.io/docs/providers/google/getting_started.html##)


## Dependencies

On a machine with `terraform` (at least 0.13) and `git` (the Google Cloud Shell can be leveraged as well):

```sh
gcloud source repos clone terraform-sqlserver-alwayson --project=cloud-ce-shared-code
```

Or:

```sh
git clone https://github.com/GoogleCloudPlatform/terraform-sqlserver-alwayson.git
```

Let's get into that directory:

```sh
cd terraform-sqlserver-alwayson/demo-staging/
```

Here we'll update the deployment variables in `prepareProject.sh`. Edit everything within the single quotes in `prepareProject.sh` (Note: `projectNumber` doesn't need single quotes, just the number itself):

```
region='{your-region-here}'
zone='{your-zone-here}'

project='{your-project-id}'
projectNumber={your-project-number}

#differentiate this deployment from others. Use lowercase alphanumerics between 6 and 30 characters.
prefix='{desired-domain-name-and-unique-seed-for-bucket-name}'

#user you will be running as
user='{user-you-will-run-as}'
```

:bangbang: For deployment troubleshooting, try entering in another unique `prefix`.

Now we'll update the terraform project in the environment folder containing `main.tf` and `backend.tf`, by running:

```sh
./prepareProject.sh
```

Here's what's happening:

* In backend.tf
	*  bucket  = "{common-backend-bucket}": change this to the bucket in your project where you will store the state
	*  project = "{cloud-project-id}" : change this to the id of your project
* In main.tf of the environment (also done by prepareProject.sh)
	*  project = "{cloud-project-id}"
	*  region = "{cloud-project-region}"
	*  primaryzone = "{cloud-project-zone}"
	*  gcs-prefix = "gs://{common-backend-bucket}"
	*  keyring = "{deployment-name}-deployment-ring"
	*  kms-key = "{deployment-name}-deployment-key"
	*  domain = "{deployment-name}.com"
	*  dc-netbios-name = "{deployment-name}"
	*  runtime-config = "{deployment-name}-runtime-config"
		* Update the gcs-prefix (done in prepareProject.sh)
* In GCP
	* Enable APIs
	    * KMS - gcloud services enable cloudkms.googleapis.com
	    * Runtime configurator - gcloud services enable runtimeconfig.googleapis.com
	    * cloud resource manager
	    * compute manager
	    * iam
  	* Make a bucket for:
	    * state file
	    * passwords
	    * powershell scripts
	    * copy up the required bootstrap scripts
	    * create a new admin service account
	    * bind the logged on user to that service account (can ran as this service account)
	    * make the service account a project editor
	    * create key ring
	    * create a key
	    * give the new admin user and the project service account rights to encrypt/decrypt with the kms key
```bash
  
  gcloud services enable cloudkms.googleapis.com
  gcloud services enable runtimeconfig.googleapis.com
  gcloud services enable cloudresourcemanager.googleapis.com
  gcloud services enable compute.googleapis.com
  gcloud services enable iam.googleapis.com

  #create the bucket
  gsutil mb -p $project gs://$bucketName
  gsutil -m cp -r ../powershell/bootstrap gs://$bucketName/powershell/bootstrap/

  gcloud kms keyrings create acme-deployment-ring --location=us-central1
  gcloud kms keys create acme-deployment-key --location=us-central1 --keyring=myring --purpose=encryption

```

## Terraforming the Environment

Next we'll run:

```sh
terraform init
```
Followed by 

```sh
terraform apply
```
You might encounter some warnings about interpolation-only expressions, due to changes between TF versions but they can safely be ignored. as of 0.13.2

## Windows Background
NetBIOS is a legacy network application used by windows for active directory.  It limits the names of machines to 15 characters. For this reason we must observe this limit on our computer names for our deployment to succeed.

### Naming Convention
We are limited as described above.
${var.deployment-name} - a unique  8 character deployment name
${var.function} - 3 characters decribing the purpose of the instance
${var.instancenumber} - two digits
computername = "${var.deployment-name}-${var.function}-${var.instancenumber}"

## For Debugging purposes:
domain admin: usr: {full domain name}\Administrator pw:
    * Domain Controller Password: 
    * SQL 1 Password: 
    * SQL 2 Password: 
    * SQL 3 Password: 

## Project Layout
There are folders for environment-specific content such as sandbox, clickToDeploy and acme-staging.  Modules, used by the deployment scripts, can be found in the ./modules directory. The contents of the docs directory is for documentary purposes, even if it is code.  The 2 shell scripts in the environment folders are:
  * clearwaiters.sh - if you are redeploying only the sql servers (you havent destroyed the whole environment including the runtime-config) this script will delete the waiters.
  * copyBootstrapArticles.sh - will copy essential scripts from ../powershell/bootstrap/ to {your deployment bucket (gcs-prefix in main.tf)}/powershell/bootstrap/

## Runtime-Config nuances
Runtime-config has limited support in terraform.  In deployment manager one can create the config and variables.  In terraform, you can only create the runtime config, variable and waiters must be created in powershell scipts or using command line or rest API.

The following deletes a waiter, which you might need to do if you redeploy

``` bash
gcloud beta runtime-config configs waiters delete clicktodeploy-dev-sql-p-01_waiter --config-name=acme-runtime-config
```

## TO connect to the instances we need firewall rules allowing access
The network module has a defult firewall resource that allows access for 3389 and 8080 to machines tagged we, pdc pr sql. If you are testing in a google project, your rules will be deleted by gce enforcer every 15 minutes and you will need to recreate your rule.

1. Go to www.whatismyip.com and find your external ip address
2. Ensure your ip address with /32 (only that  ip address) is in the source range
3. Ensure your the target tags list contains the tag of the machine you are trying to get to.

``` bash
terraform apply --target=module.create-network.google_compute_firewall.default
```

## ClickToDeploy
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

#The following is how you add a cluster in powershell. This must be run as domain admin

```Powershell
$Script:cluster_name='cluster-dbclust'
#$Script:all_nodes_fqdn ="c2d-sql-01.acme.com,c2d-sql-02.acme.com,c2d-sql-03.acme.com"
$Script:all_nodes_fqdn =@("c2d-sql-01.acme.com","c2d-sql-02.acme.com","c2d-sql-03.acme.com")
$Script:static_ip= @("10.1.0.4","10.2.0.4","10.3.0.4")

   
    Write-Host "Setting up cluster $Script:cluster_name for nodes $Script:all_nodes_fqdn and ips $Script:static_ip"
    # Create the cluster
    try {
      $result = New-Cluster -Name $Script:cluster_name -Node $Script:all_nodes_fqdn `
       -NoStorage -StaticAddress $Script:static_ip
      Write-Host "Result for setup cluster: $result"
      return $true
    }
    catch {
      Write-Host "** Failed to setup cluster: $Script:cluster_name ** "
      Write-Host $_.Exception.GetType().FullName
      Write-Host "$_.Exception.Message"
      return $false
    }


    #New-Cluster -Name "cluster-dbclus" -Node "c2d-sql-01.acme.com,c2d-sql-02.acme.com,c2d-sql-03.acme.com"  -NoStorage -StaticAddress  "10.1.0.4,10.2.0.4,10.3.0.4"
    New-Cluster -Name "cluster-dbclus" -Node @("c2d-sql-01","c2d-sql-02","c2d-sql-03")  -NoStorage -StaticAddress  @("10.1.0.4","10.2.0.4","10.3.0.4")

```


# Known issues
  * Once complete, sometimes the two replicas are not synchonized.  I think this is dues to the faiure of the script executed in sql_install.ps1._DBPermission.  THis is currently taking nodes as an array as a parameter but it needs to rather loop through because SUSER_ID() does not take an array as a parameter. Not a big issue though because this is just a demo db.
    * removing and radding the db on nodes 2 and 3 succeeds.
  * Once the deployment is complete, the scopes of the machines can be reset and also the access to the kms key shuld be adjusted to reflect the desired administrative priorities.
  * TODO: Hardcoded domain ip in sql_install.ps1 10.0.0.100 replace with fetch from metadata
  * TODO: the getMetaData functions and Rutime-Config functions are repeated in the gce_base.psm1, c2d_base.psm1 and also in some of the ps1 scripts. In general, if we are importing a library that contains a function, it should be used in that function rather than re-implemented locally.  Refactor this code to ensure optimal definition and implimentation of common functions. 






 
