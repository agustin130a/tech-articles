# ¿Quién se está comiendo el NAT Gateway?

Código y guía paso a paso del artículo sobre cómo atribuir el tráfico de **NAT Gateway** a un pod o workload
en **Amazon EKS** (probado en EKS Auto Mode) con **Grafana Beyla** (eBPF), cuando ni cAdvisor ni VPC Flow
Logs alcanzan.

- Artículo: `<URL-DEL-ARTÍCULO>`
- Resultados medidos en la prueba: [`results/resultados-poc.md`](results/resultados-poc.md)

## Por qué hace falta

| Fuente | Qué dice | Qué no dice |
|---|---|---|
| Cost Explorer / budget | Cuánto cuesta el procesamiento del NAT | Quién lo genera |
| CloudWatch `AWS/NATGateway` | GB por minuto, entrada y salida | Quién lo genera |
| cAdvisor `container_network_receive_bytes_total` | Bytes por pod | Si vienen de internet o de otro pod |
| VPC Flow Logs | IP de destino, nodo | El pod: con SNAT en el nodo, todo sale con la IP del nodo |
| **Beyla (eBPF)** | Bytes por workload y CIDR, capturados antes del SNAT | — (ver limitaciones) |

## Estructura

```
ebpf-nat-por-pod/
├── manifests/
│   ├── beyla-values.yaml   # values del chart grafana/beyla (modo network, CIDRs, ServiceMonitor)
│   └── test-pods.yaml      # pod que descarga de internet + pod que sirve un archivo interno
├── scripts/
│   ├── 00-snapshot.sh      # foto del cluster antes/después
│   ├── 01-install.sh       # instala Beyla y valida que eBPF cargó
│   ├── 02-traffic.sh       # tráfico de tamaño conocido
│   ├── 03-queries.sh       # consultas de validación en Prometheus
│   └── 04-cleanup.sh       # desinstala y compara contra la foto
└── results/
    └── resultados-poc.md   # números medidos
```

## Requisitos

- Cluster con kernel moderno (probado en Bottlerocket 6.12) y permisos para un DaemonSet privilegiado con `hostNetwork`.
- kube-prometheus-stack (o cualquier Prometheus con ServiceMonitor).
- `helm`, `kubectl`, `jq`, `aws` CLI (para el control contra el NAT).
- Espacio en **todos** los nodos para un pod más (~64 Mi de request). Si no, ese nodo queda sin cobertura.

## Pasos

```bash
cd scripts
./00-snapshot.sh antes        # foto del cluster
# editar ../manifests/beyla-values.yaml (<VPC_CIDR>, <SERVICE_CIDR>, tolerations, label del ServiceMonitor)
./01-install.sh               # DaemonSet de Beyla en ebpf-poc; validar "Flows agent successfully started"
# editar ../manifests/test-pods.yaml (<NODO_A>, <NODO_B>: nodos con Beyla, distintos)
./02-traffic.sh               # 1 GB en ráfaga, 300 MB internos, 500 MB a 10 MB/s; anotar horas
kubectl -n <ns-prometheus> port-forward svc/<prometheus> 9090:9090 &
./03-queries.sh               # esperar 2-3 scrapes antes de consultar
# comparar con CloudWatch BytesInFromDestination del NAT (período 60 s) en las mismas horas
./04-cleanup.sh               # desinstala y compara contra la foto
```

## Qué validar

| Pregunta | Pasa si |
|---|---|
| ¿Carga eBPF? | Pods `Running` **y** "Flows agent successfully started", sin errores de BTF ni de permisos |
| ¿Atribuye detrás del SNAT? | La descarga aparece como `src_cidr="0.0.0.0/0"` → `k8s_dst_owner_name=poc-downloader` |
| ¿Coincide con el NAT? | Bytes de Beyla ≈ bytes del NAT en la misma ventana |
| ¿Separa lo interno? | Los 300 MB entre pods salen con el CIDR de la VPC y no aparecen en el NAT |
| ¿Cuesta poco? | CPU y memoria por pod, cantidad de series nuevas en Prometheus |

## Limitaciones encontradas

1. **Ráfagas muy rápidas se subcuentan:** a ~90 MB/s contó el 62 %; a 10 MB/s, el 101 %. El umbral no se determinó (una corrida en cada extremo). No se ve en `beyla_bpf_network_ignored_packets_total`. Pendiente: repetir con velocidades intermedias y probar `network.source: tc`.
2. **Doble conteo pod / nodo:** el mismo tráfico se ve en la interfaz del pod (atribuido al workload) y en la `eth0` del nodo después del SNAT (atribuido al nodo). Filtrar `k8s_dst_namespace!=""` para los workloads y usar la serie del nodo como control.
3. **Tráfico interno entre nodos contado dos veces:** lo reporta el agente de cada extremo.
4. **Gateway endpoints (S3, DynamoDB):** van a IPs públicas sin pasar por el NAT; con `0.0.0.0/0` cuentan como internet. Agregar esos rangos como CIDR propios.
5. **Nodos llenos:** un DaemonSet nuevo puede quedar `Pending`; Karpenter no agrega nodos para DaemonSets. Preferible ajustar requests o agrandar los nodos. `priorityClassName` de sistema garantiza que entre, pero desaloja otros pods.
6. **Cardinalidad:** acotar `attributes.select`. Con direcciones IP como atributo, las series explotan.
7. **Solo se validó la entrada.** El NAT cobra los dos sentidos: para costo, sumar también `dst_cidr="0.0.0.0/0"` (salida) por workload.
8. **CPU medida con `rate[2m]`:** el pico durante una ráfaga corta queda promediado.

## Fuentes

- [Grafana Beyla — métricas de red](https://grafana.com/docs/beyla/latest/network/) y [configuración](https://grafana.com/docs/beyla/latest/network/config/)
- [EKS Auto Mode — Node Class (`snatPolicy`)](https://docs.aws.amazon.com/eks/latest/userguide/create-node-class.html)
- [Precios de Amazon VPC (NAT Gateway)](https://aws.amazon.com/vpc/pricing/) y [precios de CloudWatch (vended logs)](https://aws.amazon.com/cloudwatch/pricing/)
