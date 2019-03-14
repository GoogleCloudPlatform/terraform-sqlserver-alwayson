#Runtime Config

Runtime config variables are project scoped key value pairs that allow you to:
  * Dynamically configure services
  * Communicate service states
  * Send notification of changes to data
  * Share information between multiple tiers of services

We create a runtime config resource in Terraform in the creation of the domain controller (in this case the variable value is "acme-runtime-config").

```terraform
    resource "google_runtimeconfig_config" "ad-runtime-config" {
        name = "${var.runtime-config}"
        description = "Runtime configuration values for my service"
    }

```

This is created with the terraform apply at the time of creation of the domain controller and the will be the basis of a number of runtime config variables that will be used for the synchronisation of our deployment process.  Most of it will be done from powershell which is where most of our windows configuration happens.

The runtime config of a project can be found at the following full path:

https://runtimeconfig.googleapis.com/v1beta1/projects/{project id}/configs/{runtime-config}. 

This is important because some methods reuire the full path to the config and variables while others do not.  The clicktodeploy code which I am leveraging, requires that in metadata is a key value pair as follows:
status-config-url:https://runtimeconfig.googleapis.com/v1beta1/projects/{project-name}/configs/acme-runtime-config


# Get RuntimeConfig URL for the deployment

THis is important because we cannot change code in c2d_base or gce_base as they are common public libraries.  We have to provide the appropriate inputs which is the status-config-url metadata key.

### In c2d_base.ps1  (Imports gce_base.ps1)
    NOTE: 
      * c2d_base.ps1 is downloaded from gs://c2d-windows/scripts to c:/c2d/ in install-sql-server-principal-step-1.ps1
      * gce_base.ps1 is in C:\Program Files\Google\Compute Engine\sysprep on all gce machines


    ```powershell
    $runtime_config = _FetchFromMetaData -property 'attributes/status-config-url'

    if ($runtime_config) {
      # Use second part of the config URL
      #run_time_base='https://runtimeconfig.googleapis.com/v1beta1'
      $config_name = (($runtime_config -split "$Script:run_time_base/")[1])
      return $config_name
    }
    else {
      Write-Log 'No RunTimeConfig found URL found in metadata.' -error
      return $false
    }
    ```
The split results in $config_name=/projects/{project-name}/configs/acme-runtime-config

We are now set up such that the sql_install.ps1 script will work.



# After the domain controller installs

We fetch the necessary variables from metadata and set the runtime config variable.

```powershell

 --flag completion of bootstrap requires beta gcloud component
$projectId = Invoke-RestMethod -Headers @{"Metadata-Flavor" = "Google"} -Uri http://169.254.169.254/computeMetadata/v1/instance/attributes/project-id
$RuntimeConfig = Invoke-RestMethod -Headers @{"Metadata-Flavor" = "Google"} -Uri http://169.254.169.254/computeMetadata/v1/instance/attributes/runtime-config
$deploymentName = Invoke-RestMethod -Headers @{"Metadata-Flavor" = "Google"} -Uri http://169.254.169.254/computeMetadata/v1/instance/attributes/deployment-name
$statusPath = Invoke-RestMethod -Headers @{"Metadata-Flavor" = "Google"} -Uri http://169.254.169.254/computeMetadata/v1/instance/attributes/status-variable-path


Set-RuntimeConfigVariable -ConfigPath "projects/$projectId/configs/$RuntimeConfig" -Variable bootstrap/$deploymentName/$statusPath/success/time -Text (Get-Date -Format g)

```

This results in a key of:
"projects/{project-name}/configs/acme-runtime-config/variables/bootstrap/c2d/ad/success/time" having a value of the current time.

# SQL Servers install WSFC and then wait.

We can list the configs
```bash
gcloud beta runtime-config configs  list

NAME                  DESCRIPTION
acme-runtime-config  Runtime configuration values for my service
```

We can list the variables created by the process
```bash
gcloud beta runtime-config configs variables list --config-name=acme-runtime-config

NAME                           UPDATE_TIME
backup/success/done            2018-12-05T23:38:55.792737384Z
bootstrap/c2d/ad/success/time  2018-12-05T23:31:54.887933211Z
cluster/success/done           2018-12-05T23:38:49.315840745Z
initdb/success/done            2018-12-05T23:39:39.210801908Z
replica/success/done           2018-12-05T23:39:56.925089787Z
status/success/1768351525      2018-12-05T23:40:20.676334530Z
status/success/2033934784      2018-12-05T23:40:19.905856083Z
status/success/255883414       2018-12-05T23:40:40.431274139Z
success/1710287108             2018-12-05T23:34:30.532767805Z
success/825333265              2018-12-05T23:35:04.360200890Z
success/865857694              2018-12-05T23:34:25.276051895Z
```

We can list the waiters that were created to block while waiting for the domain to come up

```bash
gcloud beta runtime-config configs waiters list --config-name=acme-runtime-config
NAME               CREATE_TIME          WAITER_STATUS  MESSAGE
c2d-sql-01_waiter  2018-12-05T23:23:32  SUCCESS
c2d-sql-02_waiter  2018-12-05T23:22:58  SUCCESS
c2d-sql-03_waiter  2018-12-05T23:23:00  SUCCESS
```



