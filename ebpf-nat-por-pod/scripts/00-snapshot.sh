#!/usr/bin/env bash
# Foto del estado del cluster antes/despues de la prueba. Uso: ./00-snapshot.sh antes|despues
set -euo pipefail
out="snapshot-${1:?antes|despues}.txt"
{
  kubectl get ds -A --no-headers | awk '{print "ds "$1"/"$2}'
  kubectl get ns --no-headers | awk '{print "ns "$1}'
  kubectl get podmonitor,servicemonitor -A --no-headers | awk '{print "mon "$1"/"$2}'
} > "$out"
echo "guardado en $out"
# Despues de la prueba: diff snapshot-antes.txt snapshot-despues.txt
