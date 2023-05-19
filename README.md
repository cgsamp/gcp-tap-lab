# Tanzu Application Platform GCP Lab

## Prerequisites

- A GCP account with the ability to create GKE Clusters via command line
- A GCP artifact registry with a read/write service account
- A Pivnet / Tanzu Net login
- 

## Gather credentials and configuration

### lab-config.json

This has the version numbers of Tanzu Application Platform and Tanzu Cluster Essentials being installed.

It also has details of the GCP project and configuration.

| Variable name | Comment |
| -- | --  |
tapVersion| 1.5.0,  for example
tanzuClusterEssentialsVersion| 1.5.0,  for example
tanzuClusterEssentialsBundleSha| Retrieve from documentation: https://docs.vmware.com/en/Cluster-Essentials-for-VMware-Tanzu/1.5/cluster-essentials/deploy.html
localRegistryHostname| us-central1-docker.pkg.dev,  the hostname of Google's Artifact Registry
gkeClusterName| tap-lab,  a name invented for this lab
gkeRegion| us-central1,  the Region in which to create the cluster. Cluster is non-Autopilot, Regional not Zonal.
gcpProject| samp-tap,  the name of the project being used
localInstallRegistry| tap-lab  a registry created for this lab
machineType | VM type used to create the nodes. e2-highcpu-8 seems effective.
clusterVersion | The GKE Kubernetes version. May change from time to time.

### secrets/tanzu-secrets.json

Copy the sample-tanzu-secrets.json file to tanzu-secrets.json.

 Variable name | Comment |
| -- | --  |
tanzuNetUsername| Typically an email address
tanzuNetPassword| Password for the account
pivnetApiToken| Go to tanzu.network.vmware.com. Log in with the above credentials. Click on Edit Profile. Click on Request New Refresh Token. Copy the value to this location.

### secrets/service-account.json

Create a Artifact Registry service account with at least read/write credentials. Get the credental json file from GCP and place it here.

### tap-values.yaml

The values here depend on what is being installed. A sample is included. See TAP docs for details.

### DNS

Ability to create DNS records on a domain.

## Run Commands

The bash file `deploy-tap.sh` is constructed of functions to allow specific portions to be rerun or omitted. The high tech way to do so is to comment in / out the function commands at the bottom of the file. Given the prerequistes above, the script should result in a working TAP instance. 

**Note on coding style** 
- Variables are stored in json config and extracted via `jq -r [path]`. There is probably a better way with a Carvel tool, but moving from known to known.
- Variables are explicitly marshalled from the json extraction to a bash variable. This makes for better self-documentation, and allows the interpreter to echo the constructed variables for troubleshooting.


1. Install Tanzu CLI

This step downloads and installs the version of the `tanzu` cli associated with the TAP release. Notice the various mechanics with pivnet commands to go from a version number to a specific file to download and install. Macos (darwin) is assumed.

2. Copy Tanzu Registry

To prevent rate limiting while installing (perhaps repeatedly) the TAP binaries, they are first copied from the Tanzu registry to a GCP registry. There are about 250 of them and **this process can take a while** depending on bandwidth. Like an hour.

3. Run `gcloud auth login` and complete the browser-based login process.

4. Install GKE Cluster

Use the `gcloud` CLI to create an approprite GKE cluster. Parameters are inline in the function and may be changed or parameterized if required. Mostly they seem stable and sufficient.

5. Install Cluster Essentials

Downloads and installs Cluster Essentials. `kapp` and similar.

6. Install TAP

Deploys the TAP components into the GKE cluster.

7. Update DNS

Updates the DNS record to point to the new cluster's ingress IP. TODO: Modularize.

8. Create Dev Namespace

Creates the `developer` namespace to create applications. TODO: has this been replaced by TAP functionality?

9. Deploy Workload

Go ahead and deploy a sample workload on TAP to make sure it is all running.

TODO:

Register an app catalog.





