#!/usr/bin/env bash
# Genera trafico de tamano conocido. Anotar las horas para cruzar con CloudWatch.
set -euo pipefail
kubectl apply -f ../manifests/test-pods.yaml
kubectl -n ebpf-poc wait --for=condition=Ready pod/poc-downloader pod/poc-server --timeout=3m
SERVER_IP=$(kubectl -n ebpf-poc get pod poc-server -o jsonpath='{.status.podIP}')
ISO=https://releases.ubuntu.com/24.04/ubuntu-24.04.3-live-server-amd64.iso   # soporta Range (HTTP 206)

echo "rafaga 1 GB: $(date -u +%T)"
kubectl -n ebpf-poc exec poc-downloader -- sh -c "t=0; for i in 0 1 2 3 4; do s=\$((i*200000000)); b=\$(curl -s -o /dev/null -r \$s-\$((s+199999999)) -w '%{size_download}' $ISO); t=\$((t+b)); done; echo bytes=\$t"

echo "interno 300 MB: $(date -u +%T)"
kubectl -n ebpf-poc exec poc-downloader -- curl -s -o /dev/null -w 'bytes=%{size_download}\n' "http://$SERVER_IP:8000/file.bin"

echo "500 MB a 10 MB/s: $(date -u +%T)"
kubectl -n ebpf-poc exec poc-downloader -- curl -s -o /dev/null --limit-rate 10M -r 1000000000-1499999999 -w 'bytes=%{size_download}\n' $ISO
echo "fin: $(date -u +%T)"
