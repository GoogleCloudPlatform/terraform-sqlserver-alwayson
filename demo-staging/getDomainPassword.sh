gsutil cp gs://{deployment-name}-deployment-staging/output/domain-admin-password.bin .
gcloud kms decrypt --key {deployment-name}-deployment-key --location {cloud-project-region} --keyring {deployment-name}-deployment-ring --ciphertext-file domain-admin-password.bin --plaintext-file domain-admin-password.txt
cat domain-admin-password.txt
rm domain-admin-password.txt
