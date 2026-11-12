#!/usr/bin/env bash
#
# Crea un "nodo" de mentira con la misma estructura de archivos que kubeadm, con
# certificados que vencen en DAYS días (20 por defecto), para ver la alerta disparar.
#
# Uso: ./make-fake-node.sh <directorio> [DAYS]
#
set -euo pipefail

ROOT="${1:?uso: $0 <directorio> [DAYS]}"
DAYS="${2:-20}"
K8S="${ROOT}/etc/kubernetes"
KUBELET="${ROOT}/var/lib/kubelet/pki"
mkdir -p "${K8S}/pki/etcd" "$KUBELET"

# CA de 10 años, como la de kubeadm
openssl req -x509 -newkey rsa:2048 -nodes -days 3650 -subj "/CN=kubernetes" \
  -keyout "${K8S}/pki/ca.key" -out "${K8S}/pki/ca.crt" 2>/dev/null

# leaf <nombre> <CN> <dias> <salida.crt>
leaf() {
  local cn="$1" days="$2" out="$3" key
  key="$(mktemp)"
  openssl req -newkey rsa:2048 -nodes -subj "/CN=${cn}" -keyout "$key" -out "${key}.csr" 2>/dev/null
  openssl x509 -req -in "${key}.csr" -CA "${K8S}/pki/ca.crt" -CAkey "${K8S}/pki/ca.key" \
    -CAcreateserial -days "$days" -out "$out" 2>/dev/null
  rm -f "$key" "${key}.csr"
}

leaf kube-apiserver           "$DAYS" "${K8S}/pki/apiserver.crt"
leaf kube-etcd                "$DAYS" "${K8S}/pki/etcd/server.crt"
leaf system:kube-scheduler    "$DAYS" "${ROOT}/scheduler.crt"
leaf system:node:lab-cp-1     300     "${KUBELET}/kubelet-client-current.pem"

# kubeconfig con el certificado embebido en base64, igual que scheduler.conf
cat > "${K8S}/scheduler.conf" <<EOF
apiVersion: v1
kind: Config
users:
- name: system:kube-scheduler
  user:
    client-certificate-data: $(base64 -w0 < "${ROOT}/scheduler.crt")
    client-key-data: REDACTED
EOF
rm -f "${ROOT}/scheduler.crt" "${K8S}/pki/ca.key" "${K8S}/pki/ca.srl"

echo "Nodo de prueba creado en ${ROOT} (leaf certs a ${DAYS} días)"
