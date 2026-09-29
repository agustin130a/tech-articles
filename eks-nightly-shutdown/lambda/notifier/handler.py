"""
Lambda "notifier" del apagado nocturno.

Se suscribe al tópico SNS de fallos de la Step Function y postea un mensaje a un Incoming
Webhook de Slack. La URL del webhook nunca se hardcodea ni viaja en texto plano: se lee en
runtime desde un parámetro SSM SecureString, cuyo *nombre* (no el valor) llega por variable
de entorno.

Sin dependencias externas: boto3 viene en el runtime de Lambda, y para el POST a Slack
basta con `urllib.request` de la stdlib.
"""

import json
import logging
import os
import urllib.request

import boto3

logger = logging.getLogger()
logger.setLevel(os.environ.get("LOG_LEVEL", "INFO"))

ssm = boto3.client("ssm")

_SSM_PARAM_NAME = os.environ["SLACK_WEBHOOK_PARAM_NAME"]
_webhook_url_cache = None


def _get_webhook_url() -> str:
    global _webhook_url_cache
    if _webhook_url_cache is None:
        response = ssm.get_parameter(Name=_SSM_PARAM_NAME, WithDecryption=True)
        _webhook_url_cache = response["Parameter"]["Value"]
    return _webhook_url_cache


def _build_slack_message(sns_message: str) -> dict:
    return {
        "text": (
            ":rotating_light: *Apagado nocturno EKS — falló el escalado de un node group*\n"
            f"```{sns_message}```"
        )
    }


def handler(event, context):
    logger.info("Evento SNS recibido: %s", json.dumps(event))

    webhook_url = _get_webhook_url()
    notified = 0

    for record in event.get("Records", []):
        sns_message = record["Sns"]["Message"]
        payload = json.dumps(_build_slack_message(sns_message)).encode("utf-8")

        request = urllib.request.Request(
            webhook_url,
            data=payload,
            headers={"Content-Type": "application/json"},
            method="POST",
        )
        with urllib.request.urlopen(request, timeout=10) as response:
            logger.info("Slack respondió con status %s", response.status)
        notified += 1

    return {"notified": notified}
