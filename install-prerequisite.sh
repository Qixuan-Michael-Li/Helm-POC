#!/bin/bash

# exit when any command fails
set -e

echo 'Running pre-requisite installation script to install OCI CLI, Kubectl, and Helm'
echo 'Step 1: Installing OCI CLI'
if ! [ -x "$(command -v oci)" ]
then
  echo "OCI CLI has not been found. Installing OCI CLI."
  curl -L -O https://raw.githubusercontent.com/oracle/oci-cli/master/scripts/install/install.sh; chmod +x install.sh; ./install.sh --accept-all-defaults
else
   echo "OCI CLI has already been installed. Skipping this step."
fi

echo 'Step 2: Installing Kubectl'
if ! [ -x "$(command -v kubectl)" ]
then
  echo "Kubectl has not been found. Installing Kubectl."
  curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
  sudo install -o root -g root -m 0755 kubectl /usr/bin/kubectl
  echo "Setting up KubeConfig using OCI CLI."
  mkdir -p /var/lib/ocarun/.kube; oci ce cluster create-kubeconfig --cluster-id ${clusterId} --file /var/lib/ocarun/.kube/config  --region us-ashburn-1 --token-version 2.0.0 --kube-endpoint PRIVATE_ENDPOINT --auth instance_principal
else
   echo "Kubectl has already been installed. Skipping this step."
fi

echo 'Step 3: Installing Helm'
if ! [ -x "$(command -v helm)" ]
then
  echo "Helm has not been found. Installing Helm."
  export PATH=$PATH:/usr/local/bin; curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash; mv /usr/local/bin/helm /usr/bin/helm
else
   echo "Helm has already been installed. Skipping this step."
fi

echo 'Step 4: Setting up Credential Helper to pull charts from OCIR'
if ! [ -x "$(command -v docker-credential-ocir)" ]
then
  echo "OCIR Credential Helper has not been found. Setting up Credential Helper."
  mv /tmp/helmDemo/docker-credential-ocir /usr/bin/docker-credential-ocir; mkdir -p $HOME/.config/helm; json='{"credsStore": "ocir"}'; echo $json > $HOME/.config/helm/registry.json
else
   echo "OCIR Credential Helper has has already been set up. Skipping this step."
fi

echo 'All pre-requisite installations have completed.'
