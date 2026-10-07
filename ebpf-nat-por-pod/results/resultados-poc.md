# Resultados medidos en la PoC (anonimizados)

Cluster EKS Auto Mode, Bottlerocket, kernel 6.12, 7 nodos (t3/t3a.medium y m5a.xlarge),
`snatPolicy: Random`. Beyla 3.32.0 (chart 1.16.11), `preset: network`, captura `socket_filter`.

| Prueba | Bytes reales | NAT (CloudWatch, 1 min) | Beyla (serie del pod) |
|---|---|---|---|
| Ráfaga 1 GB en 11 s (~90 MB/s) | 1.000 MB | 1.050 MB | 624 MB (62 %) |
| 500 MB limitados a 10 MB/s | 500 MB | 520 MB | 506 MB (101 %) |
| 300 MB pod a pod (nodos distintos) | 300 MB | 0 | 302 + 301 MB (doble: un agente por nodo) |

| Otros datos | Valor |
|---|---|
| Pods de Beyla programados | 4 de 6 (2 `Pending`: nodos con 99 % de memoria reservada o máximo de pods) |
| Errores al cargar eBPF | Ninguno |
| CPU por pod | max 5m, promedio 1m (con `rate[2m]`: el pico de la ráfaga no se midió) |
| Memoria por pod | 38-47 Mi |
| Series `beyla_network_flow_bytes_total` | 144 (4 nodos, atributos acotados) |
| `beyla_bpf_network_ignored_packets_total` | 0 (el subconteo en ráfaga no se ve aquí) |
| Tráfico base del NAT antes de la prueba | ~0,4 MB/min |
