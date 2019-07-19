# Key Management Service

We create a random password for local admin and safemode admin in primary-domain-controller-step-1.ps1. These are stored in SecureStrings.

This project is depedent upon the creation of a kms ring and key that you will reference from the metadata.

```powershell

$KmsKey = Invoke-RestMethod -Headers @{"Metadata-Flavor" = "Google"} -Uri http://169.254.169.254/computeMetadata/v1/instance/attributes/kms-key
$GcsPrefix = Invoke-RestMethod -Headers @{"Metadata-Flavor" = "Google"} -Uri http://169.254.169.254/computeMetadata/v1/instance/attributes/gcs-prefix
$Region = Invoke-RestMethod -Headers @{"Metadata-Flavor" = "Google"} -Uri http://169.254.169.254/computeMetadata/v1/instance/attributes/region
$Keyring = Invoke-RestMethod -Headers @{"Metadata-Flavor" = "Google"} -Uri http://169.254.169.254/computeMetadata/v1/instance/attributes/keyring


$SafeModeAdminPassword = New-RandomPassword
$LocalAdminPassword = New-RandomPassword

Set-LocalUser Administrator -Password $LocalAdminPassword
Enable-LocalUser Administrator

Write-Host "Saving encrypted credentials in GCS..."

$TempFile = New-TemporaryFile

Unwrap-SecureString $LocalAdminPassword | gcloud kms encrypt --key $KmsKey --plaintext-file - --ciphertext-file $TempFile.FullName --location $Region  --keyring $Keyring
gsutil cp $TempFile.FullName "$GcsPrefix/output/domain-admin-password.bin"

Unwrap-SecureString $SafeModeAdminPassword | gcloud kms encrypt --key $KmsKey --plaintext-file - --ciphertext-file $TempFile.FullName --location $Region --keyring $Keyring
gsutil cp $TempFile.FullName "$GcsPrefix/output/dsrm-admin-password.bin"

Remove-Item $TempFile.FullName -Force

```
Now decrypt when you need it
```powershell
    $TempFile = New-TemporaryFile

	# invoke-command sees gsutil output as an error so redirect stderr to stdout and stringify to suppress
	gsutil cp $GcsPrefix/output/domain-admin-password.bin $TempFile.FullName 2>&1 | %{ "$_" }

	$DomainAdminPassword = $(gcloud kms decrypt --key $KmsKey --location $Region --keyring $Keyring --ciphertext-file $TempFile.FullName --plaintext-file - | ConvertTo-SecureString -AsPlainText -Force)

	Remove-Item $TempFile.FullName
```

KMS is used to encrypt the password to a temporary file which is copied to cloud storage.  This process is dependent upon the existence of a keyring and key in the specified region.


```bash
#create a keyring
gcloud kms keyrings create myring --location=us-central1

#create an encryption key
gcloud kms keys create mykey --location=us-central1 --keyring=myring --purpose=encryption

#list rings
gcloud kms keyrings list --location=us-central1

NAME
projects/{project-name}/locations/us-central1/keyRings/acme-deployment-ring
projects/{project-name}/locations/us-central1/keyRings/acme-ring


gcloud kms keys list --location=us-central1 --keyring=acme-deployment-ring

NAME                                                                                                                      PURPOSE          LABELS  PRIMARY_ID  PRIMARY_STATE
projects/{project-name}/locations/us-central1/keyRings/acme-deployment-ring/cryptoKeys/acme-deployment-key  ENCRYPT_DECRYPT          1           ENABLED

```

In bash you can download the file as follows
```bash
gsutil cp gs://acme-deployment/output/domain-admin-password.bin .

gcloud kms decrypt --key acme-deployment-key --location us-central1 --keyring acme-deployment-ring --ciphertext-file 
domain-admin-password.bin --plaintext-file domain-admin-password.txt

```



