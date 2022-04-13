#!/bin/sh

helm repo add bitnami https://charts.bitnami.com/bitnami
helm install my-release bitnami/jenkins

# Wait for Jenkins to install 
kubectl rollout status deploy/my-release-jenkins

export SERVICE_IP=$(kubectl get svc --namespace default my-release-jenkins --template "{{ range (index .status.loadBalancer.ingress 0) }}{{ . }}{{ end }}")
echo "Jenkins URL: http://$SERVICE_IP/"

echo Username: user
echo Password: $(kubectl get secret --namespace default my-release-jenkins -o jsonpath="{.data.jenkins-password}" | base64 --decode)

sleep 20
open http://$SERVICE_IP/

#Configure Jenkins with elavated permissions and db connection string file
kubectl apply -f scripts/cluster-role-binding.yaml
kubectl create secret generic db-connection-string \
  --from-literal=connectstring='mongodb://username:password@<mongo_server_ip>:27017'
kubectl apply -f scripts/deploy-jenkins.yaml
kubectl rollout status deploy/my-release-jenkins



