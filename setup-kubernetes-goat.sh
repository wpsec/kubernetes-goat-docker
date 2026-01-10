#!/bin/bash
set -e

INSECURE=""
KUBECONFIG_ARG=""
export KUBECTL_INSECURE=""
export HELM_INSECURE=""

VALUES_FILE="scenarios/metadata-db/values.yaml"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --insecure)
      INSECURE="yes"
      shift
      ;;
    --kubeconfig)
      KUBECONFIG_ARG="$2"
      shift 2
      ;;
    *)
      shift
      ;;
  esac
done

if [[ -n "$KUBECONFIG_ARG" ]]; then
  export KUBECONFIG="$KUBECONFIG_ARG"
fi

if [[ -n "$INSECURE" ]]; then
  export KUBECTL_INSECURE="--insecure-skip-tls-verify"
  export HELM_INSECURE="--kube-insecure-skip-tls-verify"
fi

kubectl $KUBECTL_INSECURE version >/dev/null 2>&1 || exit 1

kubectl $KUBECTL_INSECURE apply -f scenarios/insecure-rbac/setup.yaml

HELM_ARGS=""
if [ -f "$VALUES_FILE" ]; then
  HELM_ARGS="-f $VALUES_FILE"
fi

helm $HELM_INSECURE upgrade --install metadata-db scenarios/metadata-db \
  --namespace default \
  $HELM_ARGS \
  --wait

kubectl $KUBECTL_INSECURE apply -f scenarios/batch-check/job.yaml
kubectl $KUBECTL_INSECURE apply -f scenarios/build-code/deployment.yaml
kubectl $KUBECTL_INSECURE apply -f scenarios/cache-store/deployment.yaml
kubectl $KUBECTL_INSECURE apply -f scenarios/health-check/deployment.yaml
kubectl $KUBECTL_INSECURE apply -f scenarios/hunger-check/deployment.yaml
kubectl $KUBECTL_INSECURE apply -f scenarios/internal-proxy/deployment.yaml
kubectl $KUBECTL_INSECURE apply -f scenarios/kubernetes-goat-home/deployment.yaml
kubectl $KUBECTL_INSECURE apply -f scenarios/poor-registry/deployment.yaml
kubectl $KUBECTL_INSECURE apply -f scenarios/system-monitor/deployment.yaml
kubectl $KUBECTL_INSECURE apply -f scenarios/hidden-in-layers/deployment.yaml
