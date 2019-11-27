#!/bin/bash
#
#  Copyright 2019 Google Inc.
#
#  Licensed under the Apache License, Version 2.0 (the "License");
#  you may not use this file except in compliance with the License.
#  You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
#  Unless required by applicable law or agreed to in writing, software
#  distributed under the License is distributed on an "AS IS" BASIS,
#  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#  See the License for the specific language governing permissions and
#  limitations under the License.
#

#Enter your project details for setting up the project dependencies
region='{your-region-here}'
zone=$region"-a"
hazone=$region"-b"
drregion='{your-dr-region}'   #eg. us-east1 (b,c and d are valid)
drzone=$drregion"-b"

#Generate a uniqueu prefix for the bucket
uniq=$(head /dev/urandom | tr -dc a-z0-9 | head -c 13 ; echo '')

project='{your-project-id}'
projectNumber={your-project-number}

#differentiate this deployment from others. Use lowercase alphanumerics up to 8 characters.
prefix='{desired-unique-prefix-for-resources}'

#domain name (this will have .com added to make it fully qualified)
domainName='{domain}'

#user you will be running as (a fully google or gmail email address)
user='{user-you-will-run-as}'

#######################################################################################
### For the purposes of this demo script, you dont need to fill in anything past here
#######################################################################################

#bucket where your terraform state file, passwords and outputs will be stored
bucketName=$uniq'-deployment-staging'

kmsKeyRing=$prefix"-deployment-ring"
kmsKey=$prefix"-deployment-key"

echo $prefix
echo $bucketName
echo $kmsKeyRing
echo $kmsKey

# The files we have to substitute in are:
# backend.tf  clearwaiters.sh  copyBootstrapArtifacts.sh  getDomainPassword.sh  main.tf
sed -i "s/{common-backend-bucket}/$bucketName/g;s/{windows-domain}/$domainName/g;s/{cloud-project-id}/$project/g;s/{cloud-project-region}/$region/g;s/{cloud-project-zone}/$zone/g;s/{cloud-project-hazone}/$hazone/g;s/{cloud-project-drregion}/$drregion/g;s/{cloud-project-drzone}/$drzone/g;s/{deployment-name}/$prefix/g" backend.tf main.tf clearwaiters.sh copyBootstrapArtifacts.sh getDomainPassword.sh
 
#########################################
#enable the services that we depend upon
##########################################
 for API in compute cloudkms deploymentmanager runtimeconfig cloudresourcemanager iam storage-api storage-component
 do
         gcloud services enable "$API.googleapis.com" --project $project
 done
 
#create the bucket
 gsutil mb -p $project gs://$bucketName
 gsutil -m cp -r ../powershell/bootstrap/* gs://$bucketName/powershell/bootstrap/
 
DefaultServiceAccount="$projectNumber-compute@developer.gserviceaccount.com"
AdminServiceAccountName="admin-$prefix"
echo AdminServiceAccountName
 
AdminServiceAccount="$AdminServiceAccountName@$project.iam.gserviceaccount.com"
echo $AdminServiceAccount
 
gcloud iam service-accounts create $AdminServiceAccountName --display-name "Admin service account for bootstrapping domain-joined servers with elevated permissions" --project $project
gcloud iam service-accounts add-iam-policy-binding $AdminServiceAccount --member "user:$user" --role "roles/iam.serviceAccountUser" --project $project
gcloud projects add-iam-policy-binding $project --member "serviceAccount:$AdminServiceAccount" --role "roles/editor"
 
ServiceAccount=$AdminServiceAccount
echo  "Service Account: [$ServiceAccount]"
 
 
 gcloud kms keyrings create $kmsKeyRing --project $project --location $region
 gcloud kms keys create $kmsKey --project $project --purpose=encryption --keyring $kmsKeyRing --location $region
 
 sed "s/{Usr}/$user/g;s/{SvcAccount}/$ServiceAccount/g" policy.json | tee policy.out
 echo $policy
 
 
 gcloud kms keys set-iam-policy $kmsKey policy.out --project $project --location=$region --keyring=$kmsKeyRing
 rm policy.out
 
 
 sed "s/{Usr}/$user/g;s/{SvcAccount}/$DefaultServiceAccount/g" policy.json | tee policy.out
 gcloud kms keys set-iam-policy $kmsKey policy.out --project $project --location=$region --keyring=$kmsKeyRing
 rm policy.out


