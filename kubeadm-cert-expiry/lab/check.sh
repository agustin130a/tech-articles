#!/usr/bin/env bash
#
# Muestra qué ve Prometheus y en qué estado quedaron las reglas de Grafana.
set -euo pipefail

PROM=http://localhost:19091
GRAFANA=http://localhost:13000

export CERTS RULES
CERTS="$(curl -s -G "$PROM/api/v1/query" \
  --data-urlencode 'query=sort((kubeadm_cert_not_after_seconds - time()) / 86400)')"
RULES="$(curl -s "$GRAFANA/api/prometheus/grafana/api/v1/rules")"

python3 - <<'PY'
import json, os

print("== Días hasta el vencimiento (Prometheus)")
for r in json.loads(os.environ["CERTS"])["data"]["result"]:
    m = r["metric"]
    days = float(r["value"][1])
    print(f"  {m['host']:<10} {m['cert']:<26} {m['kind']:<16} {days:8.1f} d")

print("\n== Reglas de Grafana")
for g in json.loads(os.environ["RULES"])["data"]["groups"]:
    for r in g["rules"]:
        print(f"  [{r['state']:<8}] {r['name']} (health={r['health']})")
        for a in r.get("alerts", []):
            if a["state"].lower().startswith("alerting"):
                print(f"      -> {a['annotations'].get('summary', '')}")
PY
