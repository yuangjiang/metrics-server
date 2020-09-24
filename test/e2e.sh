#!/bin/bash

set -e

: ${IMAGE:?Need to set metrics-server IMAGE variable to test}
: ${KUBERNETES_VERSION:?Need to set KUBERNETES_VERSION to test}
KIND=$(which kind || true)

delete_cluster() {
  ${KIND} delete cluster --name=e2e &> /dev/null || true
}

setup_kind() {
  if [[ ${KIND} == "" ]] ; then
    if ! [[ -f _output/kind ]] ; then
      echo "kind not found, downloading binary"
      mkdir -p _output
      curl -Lo _output/kind "https://github.com/kubernetes-sigs/kind/releases/download/v0.7.0/kind-$(uname)-amd64"
      chmod +x _output/kind
    fi
    KIND=_output/kind
  fi
}

create_cluster() {
  if ! (${KIND} create cluster --name=e2e --image=kindest/node:${KUBERNETES_VERSION}) ; then
    echo "Could not create KinD cluster"
    exit 1
  fi
}

deploy_metrics_server(){
  ${KIND} load docker-image ${IMAGE} --name e2e
  kubectl apply -k manifests/test
  # Apply patch to use provided image
  kubectl -n kube-system patch deployment metrics-server --patch "{\"spec\": {\"template\": {\"spec\": {\"containers\": [{\"name\": \"metrics-server\", \"image\": \"${IMAGE}\"}]}}}}"
}

wait_for_metrics_server_ready() {
  # Wait for metrics server pod ready
  while [[ $(kubectl get pods -n kube-system -l k8s-app=metrics-server -o 'jsonpath={..status.conditions[?(@.type=="Ready")].status}') != "True" ]]; do
    echo "waiting for pod ready" && sleep 5;
  done
}

run_tests() {
  GO111MODULE=on go test -mod=readonly test/e2e_test.go -v -count=1
}

setup_kind
trap delete_cluster EXIT
delete_cluster
create_cluster
deploy_metrics_server
wait_for_metrics_server_ready
run_tests
