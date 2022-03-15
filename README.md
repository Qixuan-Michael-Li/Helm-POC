# Helm-POC
This repository stores the helper scripts used for Helm POC project.

Instructions for using the helper scripts:

1. Create an instance and set up Internet access and sudo permission for run commnad user.

First, we need to create an instance in the same VCN as the private OKE cluster. This instance will serve as the jump host to the private OKE cluster. When creating the instance, we should use the following cloud-init file to set up sudo permission for the run command plugin user. The run commnad plugin user will be used later by the instance group deployment pipeline to run commands to set up OCI CLI, kubectl, and Helm. The cloud-init.yaml file required is:
```
#cloud-config
users:
  - default
  - name: ocarun
    sudo: ALL=(ALL) NOPASSWD:ALL
```
When creating the instance, click on "Show advanced options" and upload the cloud-init.yaml file there.
If you have already launched the instance, then you can set up the sudo permisson by SSH to the instance and follow the instructions here: https://docs.oracle.com/en-us/iaas/Content/Compute/Tasks/runningcommands.htm#administrator-privileges

Next, we must make sure the instance can reach the public Internet in order to download OCI CLI, Kubectl, and Helm. To provide Internet access, we can either create a NAT gateway, or we can add an Egress rule to the instance's subnet. The Egress rule should look has a destination of 0.0.0.0/0.

2. Configure instance principal and other IAM policies

We will use OCI CLI to create the Kubeconfig file on the jump host that points to the private cluster. To use OCI CLI, we should set up Instance principal to avoid uploading a private key and creating a OCI config file. And to set up instance principal, we just need to create a dynamic group for the jump host, and then add the following policies to the dynamic group.
```
Allow dynamic-group helm-project-dynamic-group to manage repos in tenancy
Allow dynamic-group helm-project-dynamic-group to manage cluster-family in compartment integration_tests
```
Note that we need to set these policies at the root compartment level, because later when we push the Helm chart to OCI Container Registry, the Helm chart will be stored at a repository under the root compartment. The policy for accessing the cluster can still be specified under a certain compartment (in this example, the private OKE cluster lives in the integration_tests compartment). The verb for the OKE's policy must be "manage" in order to satisfy Kubernetes' RBAC authorization mechanism. More information on this can be found at https://docs.oracle.com/en-us/iaas/Content/ContEng/Concepts/contengaboutaccesscontrol.htm#About_Access_Control_and_Container_Engine_for_Kubernetes.

For more information on how to set up instance principal, please check out the official OCI documentation at https://docs.oracle.com/en-us/iaas/Content/Identity/Tasks/callingservicesfrominstances.htm.

3. Upload two helper scripts to OCI Artifact Registry and push the Helm chart to OCI Container Registry
- To avoid manually login to the OCIR repository every time the jump host pull a Helm chart, we need to download this helper script created by OCIR team: docker-credential-ocir. This script can be found in the current repo.
- To to automate all the manual set up work, I have created a helper script to check whether OCI CLI, Kubectl, and Helm is present, and install if not found. This script will also take care of setting up the credential helper script mentioned above. The pre-requisite installation script can be found in the current repo as well.

After we downloaded the two scripts, we need to upload them as Generic Artifacts to OCI Artifact Registry. This way the instance group workflow can download those scripts from Artifact Registry and place them on to the jump host during the deployment.

Next, we need to push the Helm chart we want to deploy to the private OKE cluster to OCI Container Registry. To do that, first create a repository in OCI Container Registry (refer to [this](https://docs.oracle.com/en-us/iaas/Content/Registry/Tasks/registrycreatingarepository.htm) link on how to create a repository) and install Helm on our local machine. Then, follow the official OCI documentation [here](https://docs.oracle.com/en-us/iaas/Content/Registry/Tasks/registrypushingimagesusingthedockercli.htm) to create an Auth Token for our user. Once we obtained the Auth Token, we can login to the repository we just created by running this command on our local machine:
```
helm registry login -u <tenancy-namespace/username> iad.ocir.io
```
When prompted for a password, enter the Auth Token. Note: if the user we use is a BOAT user, then we need to enter bmc_operator_access/<username>, rather than <tenancy-namespace/username>.

After we successfully login to the repository, we can push the Helm chart by
```
helm push <chart-name>.tgz oci://iad.ocir.io/<tenancy-namespace>/<repo-name>
```  
4. Create DevOps resources for an instance group deployment pipeline

- Create a DevOps instance group environment that points to the jump host
- Create two DevOps artifacts with generic artifact types. One artifact points to the docker-credential-ocir script, and the other artifact points to install-prerequisite.sh. These will be additional artifacts that will be downloaded to the jump host by the instance group deployment.
- Create a DevOps artifact with Instance group deployment configuration type. This will be the deployment spec for the instance group deployment pipeline. Below is the content of the deployment spec I used:
```
version: 1.0
component: deployment
runAs: ocarun
env:
  variables:
    clusterId: "${clusterId}"
    OCI_CLI_AUTH: "instance_principal"
    chartVersion: "${chartVersion}"
    HELM_EXPERIMENTAL_OCI: "1"
files:
- source: /
  destination: /tmp/helmDemo
steps:
  - stepType: Command
    name: Install pre-req
    command: ./install-prerequisite.sh
    timeoutInSeconds: 600
    runAs: root
  - stepType: Command
    name: Pull chart from OCIR
    command: helm pull -d /tmp/helmDemo oci://iad.ocir.io/idjrnzlldnlw/mychart --version ${chartVersion} --untar
    timeoutInSeconds: 60
    runAs: root
  - stepType: Command
    name: Install myChart
    command: helm install mychart /tmp/helmDemo/mychart
    timeoutInSeconds: 60
  - stepType: Command
    name: Verify Chart Has Been Released
    command: helm list
    timeoutInSeconds: 60
  - stepType: Command
    name: Verify Chart Has Been Released from Kubectl side
    command: kubectl get configmap
    timeoutInSeconds: 60
  - stepType: Command
    name: Uninstall the Release
    command: helm uninstall mychart
    timeoutInSeconds: 60
  - stepType: Command
    name: Verify the Helm release has been uninstalled
    command: helm list
    timeoutInSeconds: 60
```
Note:

- The "install-prerequisite" step and the "pull chart from OCIR" step must be run as root user. The helm pull command will first download the helm to a tmp location, rename, and untar the chart, before placing chart to the destination directory. This process will fail if not run as root user.
- At line 41 of the install-prerequisite.sh script, the command to be run is:
```
mv /tmp/helmDemo/docker-credential-ocir /usr/bin/docker-credential-ocir; mkdir...
```
The source path (/tmp/helmDemo/) of the mv command must match to the destination path defined in the files section of the deployment spec file (/tmp/helmDemo/). The file section I used is
```
files:
- source: /
  destination: /tmp/helmDemo
```
So, the docker-credential-ocir script can be found at /tmp/helmDemo, and can be succesfully moved to the /usr/bin, which is the $PATH for ocarun user. If you want to specify a different destination in the file section of the deployment spec, you must also update the path referenced in the mv command.

Once the DevOps resources are created, we can launch the instance group deployment pipeline to run Helm commands to deploy to the private OKE cluster. Before triggering a deployment, make sure we have defined pipeline parameters for clusterId and chartVersion, as those two are environment variables specified in the deployment spec file.





