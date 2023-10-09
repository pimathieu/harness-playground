#!/bin/bash

### The following steps are not neccessary if you already have the cluster built
              # Check if Docker Desktop is running
              if ! docker info >/dev/null 2>&1; then
                echo "Docker Desktop is not running. Please start Docker Desktop and try again."
                exit 1
              fi


              # Enable Kubernetes in Docker Desktop
              if ! kubectl config use-context docker-desktop >/dev/null 2>&1; then
                echo "Enabling Kubernetes in Docker Desktop..."
                #docker run --rm -it --privileged --pid=host justincormack/nsenter1 /bin/sh -c "mount -t proc proc /proc && echo 0 > /proc/sys/kernel/unprivileged_userns_clone"
                #docker run --rm -it --privileged --net=host -v /var/run/docker.sock:/var/run/docker.sock k8s.gcr.io/kindnetd:1.0.1 /sbin/ip route replace default via $(docker run --rm -it --privileged --net=host k8s.gcr.io/pause:3.6 cat /etc/resolv.conf | grep nameserver | awk '{print $2}' | head -n1)
                kubectl config use-context docker-desktop
              fi

              # Check if the cluster is already running 
              if kubectl get nodes >/dev/null 2>&1; then
                echo "Kubernetes cluster is already running in Docker Desktop."
              else
                # Create a Kubernetes cluster using Docker Desktop
                echo "Creating Kubernetes cluster in Docker Desktop..."
                kubectl create cluster docker-desktop
              fi
              ## ------------------



kubectl config use-context docker-desktop

# Verify cluster status
echo "Verifying cluster status..."
kubectl get nodes


# Setup three separate namespaces that represent different environments: dev, stage, prod
kubectl create namespace dev
kubectl create namespace stage
kubectl create namespace prod

# Verify the creation of the namespaces
kubectl get namespace dev stage prod


# Set Env variables for Git user, Harness Account_id, Harness API token, Harness Delegate token: 
echo 'export GIT_USER="*****GIT_USERNAME NEEDED HERE*******"' >> ~/.bash_profile
echo 'export HARNESS_ACCOUNT_ID="*****ACCOUNT_ID NEEDED HERE*******"' >> ~/.bash_profile
echo 'export HARNESS_API_TOKEN="*********API TOKEN NEEDED HERE**********"' >> ~/.bash_profile
echo 'export HARNESS_DELEGATE_TOKEN="**********DELEGATE TOKEN NEEDED HERE***************"' >> ~/.bash_profile
source ~/.bash_profile


# Add and update Harness helm chart repo to your local helm registry
helm repo add harness-delegate https://app.harness.io/storage/harness-download/delegate-helm-chart/
helm repo update harness-delegate

# Install the delegate
helm upgrade -i helm-delegate --namespace dev \
  harness-delegate/harness-delegate-ng \
  --set delegateName=helm-delegate \
  --set accountId=$HARNESS_ACCOUNT_ID \
  --set delegateToken= $HARNESS_DELEGATE_TOKEN\
  --set managerEndpoint=https://app.harness.io \
  --set delegateDockerImage=harness/delegate:23.09.80505 \
  --set replicas=1 --set upgrader.enabled=false

# Download CLI 
curl -LO https://github.com/harness/harness-cli/releases/download/v0.0.15-Preview/harness-v0.0.15-Preview-darwin-amd64.tar.gz 
tar -xvf harness-v0.0.15-Preview-darwin-amd64.tar.gz 
export PATH="$(pwd):$PATH" 
echo 'export PATH="'$(pwd)':$PATH"' >> ~/.bash_profile


# Login to harness cli 
harness login --api-key $HARNESS_API_TOKEN  --account-id $HARNESS_ACCOUNT_ID 

# Create a Secret for GitHub PAT: This securely stores the token. 
harness secret  --token $HARNESS_API_TOKEN

# Create a GiHub Connector: Access to YAMLs. 
harness connector --file pipeline/github-connector.yml apply --git-user $GIT_USER  

# Create a Kubernetes Cluster Connector: Access to the deployment target. 
harness connector --file pipeline/kubernetes-connector.yml apply --delegate-name helm-delegate 

# Create a Docker connector:
connector --file pipeline/docker-connector.yml apply

# Create a Service: Represents your application. 
harness service --file pipeline/k8s-service.yml apply 

# Create an Environment: Represents the production or non-production infrastructure. 
harness environment --file pipeline/k8s-dev-environment.yml apply 
harness environment --file pipeline/k8s-stage-environment.yml apply 
harness environment --file pipeline/k8s-prod-environment.yml apply 

# Create an Infrastructure Definition: Specifies the target cluster for the infrastructure.  
harness infrastructure  --file pipeline/k8s-dev-infrastructure-definition.yml apply
harness infrastructure  --file pipeline/k8s-stage-infrastructure-definition.yml apply
harness infrastructure  --file pipeline/k8s-prod-infrastructure-definition.yml apply

# Create the pipeline
harness service --file pipeline/k8s-http-helm-service.yml apply