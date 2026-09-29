variable "aws_region" {
  description = "Región AWS del cluster."
  type        = string
}

variable "cluster_name" {
  description = "Nombre del cluster EKS existente."
  type        = string
}

variable "subnet_ids" {
  description = "Subnets (privadas, con salida a ECR) donde se lanzan los nodos de los node groups apagables."
  type        = list(string)
}

variable "instance_types" {
  description = "Tipos de instancia de los node groups apagables."
  type        = list(string)
  default     = ["t3.large"]
}

variable "shutdown_cron_expression" {
  description = "Cron del apagado, en hora local de schedule_timezone."
  type        = string
  default     = "cron(0 21 ? * * *)"
}

variable "startup_cron_expression" {
  description = "Cron del encendido, en hora local de schedule_timezone."
  type        = string
  default     = "cron(0 7 ? * * *)"
}

variable "schedule_timezone" {
  description = "Timezone IANA de los dos cron (ej. \"America/Santiago\", \"America/Mexico_City\", \"Europe/Madrid\")."
  type        = string
}

variable "schedule_state" {
  description = "ENABLED o DISABLED. Si los node groups apagables ya tienen cargas reales, conviene arrancar en DISABLED."
  type        = string
  default     = "ENABLED"
}

variable "slack_webhook_ssm_parameter_name" {
  description = "Nombre del parámetro SSM SecureString con la URL del Incoming Webhook de Slack (se crea a mano)."
  type        = string
  default     = "/nightly-shutdown/slack-webhook-url"
}
