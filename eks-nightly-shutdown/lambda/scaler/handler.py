"""
Lambda "scaler" del apagado nocturno.

Recibe una iteración del Map de la Step Function con el node group a escalar y los valores
de min/desired/max a aplicar, resuelve el ASG real detrás de ese node group (no se asume ni
se hardcodea el nombre del ASG, porque cambia si el node group se recrea) y lo actualiza.

Event esperado:
{
  "cluster_name": "my-cluster",
  "nodegroup": {
    "name": "nightly-shutdown-batch",
    "min_size": 0,
    "desired_size": 0,
    "max_size": 0
  }
}
"""

import json
import logging
import os

import boto3

logger = logging.getLogger()
logger.setLevel(os.environ.get("LOG_LEVEL", "INFO"))

eks = boto3.client("eks")
autoscaling = boto3.client("autoscaling")


def _resolve_asg_name(cluster_name: str, nodegroup_name: str) -> str:
    response = eks.describe_nodegroup(clusterName=cluster_name, nodegroupName=nodegroup_name)
    asgs = response["nodegroup"]["resources"]["autoScalingGroups"]
    if not asgs:
        raise RuntimeError(
            f"El node group '{nodegroup_name}' del cluster '{cluster_name}' no tiene ningún ASG asociado"
        )
    return asgs[0]["name"]


def handler(event, context):
    logger.info("Evento recibido: %s", json.dumps(event))

    cluster_name = event["cluster_name"]
    nodegroup = event["nodegroup"]
    nodegroup_name = nodegroup["name"]

    asg_name = _resolve_asg_name(cluster_name, nodegroup_name)

    autoscaling.update_auto_scaling_group(
        AutoScalingGroupName=asg_name,
        MinSize=nodegroup["min_size"],
        DesiredCapacity=nodegroup["desired_size"],
        MaxSize=nodegroup["max_size"],
    )

    logger.info(
        "ASG %s (node group %s, cluster %s) actualizado a min=%s desired=%s max=%s",
        asg_name,
        nodegroup_name,
        cluster_name,
        nodegroup["min_size"],
        nodegroup["desired_size"],
        nodegroup["max_size"],
    )

    return {
        "cluster_name": cluster_name,
        "nodegroup_name": nodegroup_name,
        "asg_name": asg_name,
        "applied": nodegroup,
    }
