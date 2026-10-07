#!/usr/bin/env bash
# Consultas de validacion. Requiere: kubectl port-forward svc/<prometheus> 9090:9090
P=${PROM:-http://localhost:9090}
q(){ curl -s "$P/api/v1/query" --data-urlencode "query=$1" | jq -r '.data.result[]|"\(.value[1]|tonumber/1e6|floor) MB  \(.metric|del(.__name__)|tostring)"'; }

echo "== internet -> workload (solo series de pod, sin la del nodo)"
q 'topk(10, sum by (k8s_dst_namespace,k8s_dst_owner_name) (increase(beyla_network_flow_bytes_total{src_cidr="0.0.0.0/0",k8s_dst_namespace!=""}[15m])))'
echo "== workload -> internet (salida; el NAT cobra ambos sentidos)"
q 'topk(10, sum by (k8s_src_namespace,k8s_src_owner_name) (increase(beyla_network_flow_bytes_total{dst_cidr="0.0.0.0/0",k8s_src_namespace!=""}[15m])))'
echo "== internet -> nodo (control, incluye trafico del host)"
q 'sum by (k8s_dst_owner_name) (increase(beyla_network_flow_bytes_total{src_cidr="0.0.0.0/0",k8s_dst_namespace=""}[15m]))'
echo "== pruebas: crudo por agente (para ver el doble conteo interno)"
q 'beyla_network_flow_bytes_total{k8s_dst_owner_name="poc-downloader"}'
echo "== paquetes ignorados por el agente"
q 'sum by (pod) (beyla_bpf_network_ignored_packets_total)'
echo "== series y recursos"
q 'count(beyla_network_flow_bytes_total)'
q 'max_over_time(sum by (pod) (container_memory_working_set_bytes{namespace="ebpf-poc",container="beyla"})[30m:1m])'

# Control contra el NAT (por minuto):
# aws cloudwatch get-metric-statistics --namespace AWS/NATGateway --metric-name BytesInFromDestination \
#   --dimensions Name=NatGatewayId,Value=<NAT_ID> --start-time <T0> --end-time <T1> --period 60 --statistics Sum
