#!/usr/bin/env bash
#
# Levanta el laboratorio:
#   1. crea un nodo de prueba con certificados a 20 días y le corre el exportador;
#   2. copia las reglas de Grafana con evaluación cada 10 s y "for" cortos, para no esperar
#      (la regla del exportador conserva 1 min para no avisar antes del primer scrape);
#   3. levanta node_exporter, Prometheus y Grafana.
#
# Para sumar nodos reales, deja sus .prom en ./textfile (ver README).
set -euo pipefail
cd "$(dirname "$0")"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

./make-fake-node.sh "$work/lab-cp-1" "${DAYS:-20}"
mkdir -p textfile
K8S_DIR="$work/lab-cp-1/etc/kubernetes" \
KUBELET_PKI_DIR="$work/lab-cp-1/var/lib/kubelet/pki" \
HOST_LABEL=lab-cp-1 \
  ../exporter/kubeadm-cert-exporter.sh --stdout > textfile/lab-cp-1.prom

mkdir -p grafana/provisioning/alerting
sed -E -e 's/^(\s*)interval: 5m/\1interval: 10s/' \
       -e 's/^(\s*)for: 1h/\1for: 0s/' \
       -e 's/^(\s*)for: 15m/\1for: 1m/' \
  ../alerts/grafana-kubeadm-certs.yaml > grafana/provisioning/alerting/kubeadm-certs.yaml

docker compose up -d
echo "Prometheus: http://localhost:19091  ·  Grafana: http://localhost:13000 (Alerting > Alert rules)"
