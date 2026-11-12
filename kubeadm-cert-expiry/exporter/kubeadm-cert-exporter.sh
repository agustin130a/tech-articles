#!/usr/bin/env bash
#
# kubeadm-cert-exporter.sh
#
# Publica la fecha de vencimiento de los certificados de un nodo kubeadm en formato
# Prometheus, para que node_exporter la exponga con su textfile collector.
#
# Solo lee certificados públicos: nunca abre ni imprime claves privadas.
# En un worker solo encuentra la CA y los certificados del kubelet; el resto se omite.
#
# Uso:
#   kubeadm-cert-exporter.sh            # escribe $TEXTFILE_DIR/kubeadm_certs.prom (atómico)
#   kubeadm-cert-exporter.sh --stdout   # imprime las métricas y no escribe nada
#
# Variables:
#   K8S_DIR          directorio de kubeadm             (default /etc/kubernetes)
#   KUBELET_PKI_DIR  certificados del kubelet           (default /var/lib/kubelet/pki)
#   TEXTFILE_DIR     directorio del textfile collector  (default /var/lib/node_exporter/textfile_collector)
#   HOST_LABEL       valor del label host               (default: hostname corto)
#
set -euo pipefail

K8S_DIR="${K8S_DIR:-/etc/kubernetes}"
KUBELET_PKI_DIR="${KUBELET_PKI_DIR:-/var/lib/kubelet/pki}"
TEXTFILE_DIR="${TEXTFILE_DIR:-/var/lib/node_exporter/textfile_collector}"
HOST_LABEL="${HOST_LABEL:-$(hostname -s | tr '[:upper:]' '[:lower:]')}"
PKI="${K8S_DIR}/pki"

STDOUT=0
[[ "${1:-}" == "--stdout" ]] && STDOUT=1

errors=0
lines=()

# Convierte el notAfter de un certificado PEM (leído por stdin) a epoch.
not_after_epoch() {
  local end
  end="$(openssl x509 -noout -enddate 2>/dev/null | cut -d= -f2)" || return 1
  [[ -n "$end" ]] || return 1
  date -d "$end" +%s
}

# emit <cert> <kind> <epoch>
emit() {
  lines+=("kubeadm_cert_not_after_seconds{host=\"${HOST_LABEL}\",cert=\"$1\",kind=\"$2\"} $3")
}

# Certificado en un archivo .crt/.pem. Si el archivo no existe, se omite.
from_file() {
  local name="$1" kind="$2" file="$3" epoch
  [[ -f "$file" ]] || return 0
  if epoch="$(not_after_epoch < "$file")"; then
    emit "$name" "$kind" "$epoch"
  else
    errors=$((errors + 1))
  fi
}

# Certificado de cliente embebido en un kubeconfig (client-certificate-data),
# o referenciado por ruta (client-certificate). Nunca lee client-key-data.
from_kubeconfig() {
  local name="$1" kind="$2" file="$3" data path epoch
  [[ -f "$file" ]] || return 0
  data="$(awk '/^[[:space:]]*client-certificate-data:/ {print $2; exit}' "$file")"
  if [[ -n "$data" ]]; then
    if epoch="$(printf '%s' "$data" | base64 -d 2>/dev/null | not_after_epoch)"; then
      emit "$name" "$kind" "$epoch"
    else
      errors=$((errors + 1))
    fi
    return 0
  fi
  path="$(awk '/^[[:space:]]*client-certificate:/ {print $2; exit}' "$file")"
  if [[ -n "$path" ]]; then
    from_file "$name" "$kind" "$path"
  fi
}

# --- Autoridades de certificación (10 años por defecto) ---
from_file ca                ca   "${PKI}/ca.crt"
from_file etcd-ca           ca   "${PKI}/etcd/ca.crt"
from_file front-proxy-ca    ca   "${PKI}/front-proxy-ca.crt"

# --- Leaf certificates del control plane (1 año por defecto) ---
from_file apiserver                 leaf "${PKI}/apiserver.crt"
from_file apiserver-kubelet-client  leaf "${PKI}/apiserver-kubelet-client.crt"
from_file apiserver-etcd-client     leaf "${PKI}/apiserver-etcd-client.crt"
from_file front-proxy-client        leaf "${PKI}/front-proxy-client.crt"
from_file etcd-server               leaf "${PKI}/etcd/server.crt"
from_file etcd-peer                 leaf "${PKI}/etcd/peer.crt"
from_file etcd-healthcheck-client   leaf "${PKI}/etcd/healthcheck-client.crt"

# --- Kubeconfigs que genera kubeadm (1 año por defecto) ---
from_kubeconfig admin.conf               kubeconfig "${K8S_DIR}/admin.conf"
from_kubeconfig super-admin.conf         kubeconfig "${K8S_DIR}/super-admin.conf"
from_kubeconfig controller-manager.conf  kubeconfig "${K8S_DIR}/controller-manager.conf"
from_kubeconfig scheduler.conf           kubeconfig "${K8S_DIR}/scheduler.conf"

# --- Kubelet (todos los nodos) ---
# Cliente: rota solo si rotateCertificates=true.
from_file kubelet-client kubelet-client "${KUBELET_PKI_DIR}/kubelet-client-current.pem"
# Serving: autofirmado (kubelet.crt) salvo que se use serverTLSBootstrap.
if [[ -f "${KUBELET_PKI_DIR}/kubelet-server-current.pem" ]]; then
  from_file kubelet-serving kubelet-serving "${KUBELET_PKI_DIR}/kubelet-server-current.pem"
else
  from_file kubelet-serving kubelet-serving "${KUBELET_PKI_DIR}/kubelet.crt"
fi

render() {
  echo "# HELP kubeadm_cert_not_after_seconds Fecha de vencimiento (epoch) de un certificado del nodo."
  echo "# TYPE kubeadm_cert_not_after_seconds gauge"
  [[ ${#lines[@]} -gt 0 ]] && printf '%s\n' "${lines[@]}"
  echo "# HELP kubeadm_cert_exporter_last_run_timestamp_seconds Última ejecución del exportador (epoch)."
  echo "# TYPE kubeadm_cert_exporter_last_run_timestamp_seconds gauge"
  echo "kubeadm_cert_exporter_last_run_timestamp_seconds{host=\"${HOST_LABEL}\"} $(date +%s)"
  echo "# HELP kubeadm_cert_exporter_errors Certificados presentes que no se pudieron leer en la última ejecución."
  echo "# TYPE kubeadm_cert_exporter_errors gauge"
  echo "kubeadm_cert_exporter_errors{host=\"${HOST_LABEL}\"} ${errors}"
}

if [[ "$STDOUT" == "1" ]]; then
  render
  exit 0
fi

# Escritura atómica: node_exporter nunca ve un archivo a medio escribir.
mkdir -p "$TEXTFILE_DIR"
tmp="$(mktemp "${TEXTFILE_DIR}/.kubeadm_certs.prom.XXXXXX")"
render > "$tmp"
chmod 0644 "$tmp"
mv "$tmp" "${TEXTFILE_DIR}/kubeadm_certs.prom"
