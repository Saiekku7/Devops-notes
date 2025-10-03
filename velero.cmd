# #################################################CREATE AWS EKS BACKUP AND RESTORE #######################################################

# velerocli install
wget https://github.com/vmware-tanzu/velero/releases/download/v1.15.0/velero-v1.15.0-linux-amd64.tar.gz
tar -xzvf velero-v1.15.0-linux-amd64.tar.gz
sudo cp velero-v1.15.0-linux-amd64/velero /usr/local/bin/

velero install --provider aws --plugins velero/velero-plugin-for-aws:v1.0.1 --bucket backup-sg-12 --backup-location-config region=eu-north-1 --snapshot-location-config region=eu-north-1 --secret-file ~/.aws/credentials

kubectl logs deployment/velero -n velero
velero backup-location get


1. CREATE S3 BUCKET
aws s3api create-bucket --bucket awseksbackup --region eu-north-1

kubectl get all -n velero
2. DEPLOY TEST APPLICATION
kubectl create namespace eksbackupdemo
kubectl create deployment web --image=gcr.io/google-samples/hello-app:1.0 -n eksbackupdemo
kubectl create deployment nginx --image=nginx -n eksbackupdemo
3. VERIFY DEPLOYMENT
kubectl get deployments -n eksbackupdemo
4. BACKUP AND RESTORE
velero backup create <backupname> --include-namespaces <namespacename>
velero backup create test1 --include-namespaces eksbackupdemo
5. DESCRIBE BACKUP
velero backup describe <backupname>
velero backup describe test1
6. DELETE ABOVE DEPLOYMENT
kubectl delete namespace eksbackupdemo
7. RESTORE BACKUP ON SAME CLUSTER.
velero restore create --from-backup test1

velero restore describe test1-20251003061942

8. RESTORE ON ONTHER EKS CLUSTER
# *************** Install the velero on both the clusters but make sure that cluster points to the same S3 bucket ****************************
velero install --provider aws --plugins velero/velero-plugin-for-aws:v1.0.1 --bucket backup-sg-12 --backup-location-config region=eu-north-1 --snapshot-location-config region=eu-north-1 --secret-file ~/.aws/credentials
velero restore create --from-backup test1
#############################################################################################################################################
