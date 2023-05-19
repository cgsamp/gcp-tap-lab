#!/bin/bash

set -x

function install_tanzu_cli {
  echo $(date) Starting install_tanzu_cli
  export PIVNET_API_TOKEN="$(cat secrets/tanzu-secrets.json | jq -r '.pivnetApiToken')"
  export TAP_VERSION="$(cat lab-config.json | jq -r '.tapVersion')"

  pivnet login --api-token=$PIVNET_API_TOKEN
  export PRODUCT_FILE_ID=$(pivnet product-files --product-slug='tanzu-application-platform' --release-version="$TAP_VERSION" --format json | jq '.[] | select(.name=="tanzu-framework-bundle-mac") | .id')
  rm tanzu-framework-darwin-amd64*
  pivnet download-product-files --product-slug='tanzu-application-platform' --release-version="$TAP_VERSION" --product-file-id=$PRODUCT_FILE_ID
  tar -xvf tanzu-framework-darwin-amd64*.tar -C $HOME/tanzu
  export TANZU_CLI_NO_INIT=true
  echo Tanzu cli $(tanzu version)
  tanzu plugin install --local $HOME/tanzu/cli all
}

function copy_tanzu_registry {
  echo $(date) Starting copy_tanzu_registry
  export TAP_VERSION="$(cat lab-config.json | jq -r '.tapVersion')"
  export TANZU_NET_USERNAME="$(cat secrets/tanzu-secrets.json | jq -r '.tanzuNetUsername')"
  export TANZU_NET_PASSWORD="$(cat secrets/tanzu-secrets.json | jq -r '.tanzuNetPassword')"
  export LOCAL_REGISTRY_HOSTNAME="$(cat lab-config.json | jq -r '.localRegistryHostname')"
  export LOCAL_INSTALL_REGISTRY="$(cat lab-config.json | jq -r '.localInstallRegistry')"
  export GCP_PROJECT="$(cat lab-config.json | jq -r '.gcpProject')"

  docker login $LOCAL_REGISTRY_HOSTNAME/$GCP_PROJECT/$LOCAL_INSTALL_REGISTRY
  docker login registry.tanzu.vmware.com -u $TANZU_NET_USERNAME --password $TANZU_NET_PASSWORD
  imgpkg copy -b registry.tanzu.vmware.com/tanzu-application-platform/tap-packages:${TAP_VERSION} --to-repo $LOCAL_REGISTRY_HOSTNAME/$GCP_PROJECT/$LOCAL_INSTALL_REGISTRY/tap-packages
}


function install_gke_cluster {
  echo $(date) Starting install_gke_cluster
  export GKE_CLUSTER_NAME=$(cat lab-config.json | jq -r '.gkeClusterName')
  export GKE_REGION=$(cat lab-config.json | jq -r '.gkeRegion')
  export GCP_PROJECT=$(cat lab-config.json | jq -r '.gcpProject')
  export MACHINE_TYPE=$(cat lab-config.json | jq -r '.machineType')
  export CLUSTER_VERSION=$(cat lab-config.json | jq -r '.clusterVersion')

  gcloud container clusters delete $GKE_CLUSTER_NAME --region $GKE_REGION --quiet || true

  gcloud beta container \
    --project "$GCP_PROJECT" \
    clusters create "$GKE_CLUSTER_NAME" \
    --region "$GKE_REGION" \
    --machine-type "$MACHINE_TYPE" \
    --cluster-version "1.25.7-gke.1000" \
    --no-enable-basic-auth --release-channel "regular" --image-type "COS_CONTAINERD" --disk-type "pd-balanced" --disk-size "100" --metadata disable-legacy-endpoints=true --scopes "https://www.googleapis.com/auth/devstorage.read_only","https://www.googleapis.com/auth/logging.write","https://www.googleapis.com/auth/monitoring","https://www.googleapis.com/auth/servicecontrol","https://www.googleapis.com/auth/service.management.readonly","https://www.googleapis.com/auth/trace.append" --max-pods-per-node "110" --num-nodes "3" --logging=SYSTEM,WORKLOAD --monitoring=SYSTEM --enable-ip-alias --network "projects/samp-tap/global/networks/default" --subnetwork "projects/samp-tap/regions/us-central1/subnetworks/default" --no-enable-intra-node-visibility --default-max-pods-per-node "110" --no-enable-master-authorized-networks --addons HorizontalPodAutoscaling,HttpLoadBalancing,GcePersistentDiskCsiDriver --enable-autoupgrade --enable-autorepair --max-surge-upgrade 1 --max-unavailable-upgrade 0 --enable-shielded-nodes
}

function install_cluster_essentials {
  export TANZU_NET_USERNAME=$(cat secrets/tanzu-secrets.json | jq -r '.tanzuNetUsername')
  export TANZU_NET_PASSWORD=$(cat secrets/tanzu-secrets.json | jq -r '.tanzuNetPassword')
  export PIVNET_API_TOKEN=$(cat secrets/tanzu-secrets.json | jq -r '.pivnetApiToken')
  export TANZU_CLUSTER_ESSENTIALS_VERSION=$(cat lab-config.json | jq -r '.tanzuClusterEssentialsVersion')
  export TANZU_CLUSTER_ESSENTIALS_BUNDLE=$(cat lab-config.json | jq -r '.tanzuClusterEssentialsBundleSha')

  pivnet login --api-token=$PIVNET_API_TOKEN
  export FILE_ID=$(pivnet product-files --product-slug='tanzu-cluster-essentials' --release-version="1.5.0" --format json | jq '.[] | select(.name | startswith("tanzu-cluster-essentials-darwin")) | .id')
  pivnet download-product-files -p tanzu-cluster-essentials -r $TANZU_CLUSTER_ESSENTIALS_VERSION -i $FILE_ID
  rm -rf $HOME/tanzu-cluster-essentials
  mkdir $HOME/tanzu-cluster-essentials
  tar -xvf tanzu-cluster-essentials-darwin-amd64-$TANZU_CLUSTER_ESSENTIALS_VERSION.tgz -C $HOME/tanzu-cluster-essentials

  export INSTALL_BUNDLE=registry.tanzu.vmware.com/tanzu-cluster-essentials/cluster-essentials-bundle@sha256:$TANZU_CLUSTER_ESSENTIALS_BUNDLE
  export INSTALL_REGISTRY_HOSTNAME=registry.tanzu.vmware.com
  export INSTALL_REGISTRY_USERNAME=$TANZU_NET_USERNAME
  export INSTALL_REGISTRY_PASSWORD=$TANZU_NET_PASSWORD

  export CURRENT_DIR=$(pwd)
  cd $HOME/tanzu-cluster-essentials
  ./install.sh --yes
  cd $CURRENT_DIR
}

function install_tap {
  echo $(date) Starting install_tap
  export LOCAL_REGISTRY_HOSTNAME="$(cat lab-config.json | jq -r '.localRegistryHostname')"
  export LOCAL_INSTALL_REGISTRY="$(cat lab-config.json | jq -r '.localInstallRegistry')"
  export GCP_PROJECT="$(cat lab-config.json | jq -r '.gcpProject')"
  export TAP_VERSION=$(cat lab-config.json | jq -r '.tapVersion')
  export TAP_REPOSITORY=$LOCAL_REGISTRY_HOSTNAME/$GCP_PROJECT/$LOCAL_INSTALL_REGISTRY/tap-packages:$TAP_VERSION
  kubectl create ns tap-install || true

  tanzu secret registry add tap-registry \
    --username "_json_key" --password "$(cat secrets/gcp-service-account.json)" \
    --server $LOCAL_REGISTRY_HOSTNAME \
    --export-to-all-namespaces --yes --namespace tap-install

  tanzu package repository add tanzu-tap-repository \
    --url $TAP_REPOSITORY \
    --namespace tap-install

  tanzu package install tap -p tap.tanzu.vmware.com -v $TAP_VERSION --values-file tap-values.yaml -n tap-install
}

function update_dns {
  echo $(date) Starting update_dns
  export SHARED_INGRESS_IP=$(kubectl get service envoy -n tanzu-system-ingress -ojson | jq -r '.status.loadBalancer.ingress[].ip')
  gcloud dns --project=samp-tap record-sets update "tap.gcp.csamp-tanzu.com." --type="A" --zone="csamp-tanzu-com" --rrdatas=${SHARED_INGRESS_IP} --ttl="300"
  gcloud dns --project=samp-tap record-sets update "*.tap.gcp.csamp-tanzu.com." --type="A" --zone="csamp-tanzu-com" --rrdatas=${SHARED_INGRESS_IP} --ttl="300"
}

function create_dev_namespace {
  kubectl create ns developer
  tanzu secret registry add registry-credentials --server $LOCAL_REGISTRY_HOSTNAME --username "_json_key" --password "$(cat secrets/gcp-service-account.json)" --namespace developer
  kubectl -n developer apply -f developer-secrets.yaml
}

function deploy_app {
  echo $(date) Starting deploy_app
  export GIT_URL_TO_REPO=https://github.com/cgsamp/tanzu-java-web-app
  tanzu apps workload create -f workload.yaml --yes
  tanzu apps workload tail tanzu-java-web-app --namespace developer --since 1h
}


# install_tanzu_cli
# copy_tanzu_registry
# gcloud auth login
# install_gke_cluster
# install_cluster_essentials
# create_dev_namespace
# install_tap
update_dns
# deploy_app
echo $(date) DONE

