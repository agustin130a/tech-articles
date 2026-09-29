"""Diagrama de aislamiento: qué cargas se apagan y cuáles no se tocan.

Regenerar (parado en la raíz del workshop) con:
    ~/.venvs/aws-diagrams/bin/python3 docs/aislamiento.py

Requiere Graphviz instalado a nivel de sistema y la librería `diagrams`
(instalada en el venv de arriba, no en el Python del sistema).
"""

from diagrams import Diagram, Cluster, Edge, Node

# Fix de estilo conocido: el default (1.9) deja el label pegado al ícono.
Node._height = 2.3

from diagrams.k8s.compute import Pod
from diagrams.aws.compute import EC2AutoScaling

graph_attr = {
    "fontsize": "20",
    "bgcolor": "white",
    "pad": "0.5",
    "nodesep": "0.8",
    "ranksep": "1.2",
    "dpi": "96",
}

OK = "darkgreen"
FAIL = "firebrick"

with Diagram(
    "Solo se apaga lo que lo pide explícitamente",
    filename="docs/aislamiento",
    show=False,
    direction="TB",
    graph_attr=graph_attr,
):
    with Cluster("Pods"):
        pod_ok = Pod("nodeSelector\n+ toleration")
        pod_tol = Pod("solo toleration\n(sin nodeSelector)")
        pod_plain = Pod("sin nada\n(cargas actuales)")

    with Cluster("Cluster EKS"):
        with Cluster("Node groups existentes (no se tocan, 24/7)"):
            existing = EC2AutoScaling("ASG existente")
        with Cluster("Node groups apagables\ntaint nightly-shutdown=true:NoSchedule"):
            nightly = EC2AutoScaling("ASG apagable\n0 nodos de noche")

    pod_ok >> Edge(label="queda anclado\n(Pending de noche)", color=OK, fontcolor=OK) >> nightly
    pod_tol >> Edge(label="puede ir a cualquiera", color=FAIL, fontcolor=FAIL, style="dashed") >> existing
    pod_tol >> Edge(color=FAIL, style="dashed") >> nightly
    pod_plain >> Edge(label="solo a los existentes\n(el taint lo repele)") >> existing
