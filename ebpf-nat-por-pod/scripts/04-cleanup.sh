#!/usr/bin/env bash
set -euo pipefail
kubectl delete -f ../manifests/test-pods.yaml --ignore-not-found
helm uninstall beyla -n ebpf-poc --wait || true
kubectl delete ns ebpf-poc --wait=true
kubectl get clusterrole,clusterrolebinding -o name | grep -i beyla || echo "sin RBAC de beyla"
./00-snapshot.sh despues && diff snapshot-antes.txt snapshot-despues.txt && echo "cluster igual que antes"
