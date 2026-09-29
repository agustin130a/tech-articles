"""Diagrama de arquitectura del apagado nocturno de node groups EKS.

Regenerar (parado en la raíz del workshop) con:
    ~/.venvs/aws-diagrams/bin/python3 docs/arquitectura.py

Requiere Graphviz instalado a nivel de sistema y la librería `diagrams`
(instalada en el venv de arriba, no en el Python del sistema).
"""

from diagrams import Diagram, Cluster, Edge, Node

# Fix de estilo conocido: el default (1.9) deja el label pegado al ícono.
Node._height = 2.3

from diagrams.aws.integration import EventbridgeScheduler, StepFunctions, SimpleNotificationServiceSns
from diagrams.aws.compute import Lambda, EC2AutoScaling, ElasticKubernetesService
from diagrams.aws.management import SystemsManagerParameterStore
from diagrams.saas.chat import Slack

graph_attr = {
    "fontsize": "20",
    "bgcolor": "white",
    "pad": "1.0",
    "nodesep": "0.8",
    "ranksep": "1.0",
    "dpi": "96",
}

FAIL = "firebrick"

with Diagram(
    "Apagado nocturno de node groups EKS",
    filename="docs/arquitectura",
    show=False,
    direction="LR",
    graph_attr=graph_attr,
):
    scheduler = EventbridgeScheduler("EventBridge Scheduler\n21:00 apaga / 07:00 enciende\n(timezone IANA, DST automático)")
    sfn = StepFunctions("Step Function\nMap sobre node groups\nRetry por iteración")
    scaler = Lambda("Lambda scaler\nmin / desired / max")

    with Cluster("Cluster EKS"):
        eks = ElasticKubernetesService("eks:DescribeNodegroup\n(resuelve el ASG real)")
        with Cluster("Node groups apagables (taint + label)"):
            asg = EC2AutoScaling("ASG del node group\nmax también a 0")

    with Cluster("Solo si falla (después de los reintentos)"):
        sns = SimpleNotificationServiceSns("SNS")
        notifier = Lambda("Lambda notifier")
        ssm = SystemsManagerParameterStore("SSM SecureString\n(URL del webhook)")
        slack = Slack("Slack\n(Incoming Webhook)")

    scheduler >> Edge(label="dispara con la lista\nde node groups") >> sfn
    sfn >> Edge(label="1 invocación por\nnode group") >> scaler
    scaler >> eks
    scaler >> Edge(label="UpdateAutoScalingGroup") >> asg

    sfn >> Edge(label="Catch", color=FAIL, fontcolor=FAIL, style="dashed") >> sns
    sns >> Edge(color=FAIL, style="dashed") >> notifier
    notifier >> Edge(label="lee", style="dotted") >> ssm
    notifier >> Edge(label="POST", color=FAIL, fontcolor=FAIL, style="dashed") >> slack
