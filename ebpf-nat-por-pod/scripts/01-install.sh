#!/usr/bin/env bash
set -euo pipefail
helm repo add grafana https://grafana.github.io/helm-charts >/dev/null 2>&1 || true
helm repo update grafana >/dev/null
helm upgrade --install beyla grafana/beyla --version 1.16.11 \
  -n ebpf-poc --create-namespace -f ../manifests/beyla-values.yaml
kubectl -n ebpf-poc rollout status ds/beyla --timeout=5m || true
kubectl -n ebpf-poc get pods -o wide
# Validar que eBPF cargo: buscar "Flows agent successfully started"
for p in $(kubectl -n ebpf-poc get pods -l app.kubernetes.io/name=beyla -o name); do
  kubectl -n ebpf-poc logs "$p" | grep -E "successfully started|level=ERROR" || true
done
