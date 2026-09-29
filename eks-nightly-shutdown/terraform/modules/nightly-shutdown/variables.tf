variable "aws_region" {
  description = "Región AWS del cluster."
  type        = string
}

variable "cluster_name" {
  description = "Nombre del cluster EKS."
  type        = string
}

variable "name_prefix" {
  description = "Prefijo para nombrar los recursos (Lambdas, Step Function, SNS, schedules)."
  type        = string
  default     = "nightly-shutdown"
}

variable "nodegroups" {
  description = "Node groups apagables y sus valores de restauración al encender. Basta con agregar una entrada aquí para sumar un node group nuevo, sin tocar el módulo."
  type = list(object({
    name                 = string
    restore_min_size     = number
    restore_desired_size = number
    restore_max_size     = number
  }))
}

variable "shutdown_cron_expression" {
  description = "Cron (EventBridge Scheduler, formato de 6 campos) del apagado, en hora LOCAL de var.schedule_timezone — no UTC."
  type        = string
  default     = "cron(0 21 ? * * *)"
}

variable "startup_cron_expression" {
  description = "Cron (EventBridge Scheduler, formato de 6 campos) del encendido, en hora LOCAL de var.schedule_timezone — no UTC."
  type        = string
  default     = "cron(0 7 ? * * *)"
}

variable "schedule_timezone" {
  description = "Timezone IANA para los dos schedule_expression de arriba (ej. \"America/Santiago\", \"Europe/Madrid\"). EventBridge Scheduler ajusta el DST solo — no hace falta tocar el cron dos veces al año."
  type        = string
  default     = "UTC"
}

variable "schedule_down_name" {
  type    = string
  default = "nightly-shutdown-down"
}

variable "schedule_up_name" {
  type    = string
  default = "nightly-shutdown-up"
}

variable "schedule_state" {
  description = "ENABLED o DISABLED. Si los node groups apagables ya tienen cargas reales, arranca en DISABLED y prueba el flujo a mano antes de habilitar."
  type        = string
  default     = "ENABLED"
}

variable "slack_webhook_ssm_parameter_name" {
  description = "Nombre (no ARN, no valor) del parámetro SSM SecureString con el Incoming Webhook de Slack. El valor se crea a mano, fuera de Terraform."
  type        = string
}

variable "lambda_runtime" {
  type    = string
  default = "python3.12"
}

variable "scaler_timeout_seconds" {
  type    = number
  default = 30
}

variable "map_max_concurrency" {
  description = "Máxima cantidad de node groups escalados en paralelo por ejecución del Map."
  type        = number
  default     = 5
}

variable "tags" {
  type    = map(string)
  default = {}
}
