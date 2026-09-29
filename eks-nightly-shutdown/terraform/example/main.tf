# Ejemplo de uso completo: dos node groups apagables y el mecanismo de apagado nocturno.
# Los valores de tu cuenta/cluster van en terraform.tfvars (copiar terraform.tfvars.example).
# Requiere un cluster EKS existente y el parámetro SSM SecureString con el webhook de Slack
# creado a mano (ver README).

terraform {
  required_version = ">= 1.5.5"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.28"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# Node group apagable #1: de uso general
module "nodegroup_general" {
  source = "../modules/managed-node-group"

  cluster_name    = var.cluster_name
  node_group_name = "nightly-shutdown-general"
  subnet_ids      = var.subnet_ids

  instance_types = var.instance_types
  scaling_config = {
    min_size     = 0
    desired_size = 1
    max_size     = 10
  }

  labels = { workload-class = "nightly-shutdown-general" }
  taints = [{ key = "nightly-shutdown", value = "true", effect = "NO_SCHEDULE" }]
}

# Node group apagable #2: reservado para picos/incidentes, arranca en 0
module "nodegroup_incidents" {
  source = "../modules/managed-node-group"

  cluster_name    = var.cluster_name
  node_group_name = "nightly-shutdown-incidents"
  subnet_ids      = var.subnet_ids

  instance_types = var.instance_types
  scaling_config = {
    min_size     = 0
    desired_size = 0 # no levanta ningún nodo solo; se escala a mano cuando hace falta
    max_size     = 10
  }

  labels = { workload-class = "nightly-shutdown-incidents" }
  taints = [{ key = "nightly-shutdown", value = "true", effect = "NO_SCHEDULE" }]
}

# El mecanismo de apagado: soporta N node groups sin cambios de código
module "nightly_shutdown" {
  source = "../modules/nightly-shutdown"

  aws_region   = var.aws_region
  cluster_name = var.cluster_name
  name_prefix  = "nightly-shutdown"

  nodegroups = [
    {
      name                 = module.nodegroup_general.node_group_name
      restore_min_size     = 0
      restore_desired_size = 1
      restore_max_size     = 10
    },
    {
      name                 = module.nodegroup_incidents.node_group_name
      restore_min_size     = 0
      restore_desired_size = 0
      restore_max_size     = 10
    },
  ]

  # Cron en hora LOCAL de schedule_timezone (no UTC). EventBridge Scheduler ajusta el DST solo.
  shutdown_cron_expression = var.shutdown_cron_expression
  startup_cron_expression  = var.startup_cron_expression
  schedule_timezone        = var.schedule_timezone

  schedule_state = var.schedule_state

  slack_webhook_ssm_parameter_name = var.slack_webhook_ssm_parameter_name
}
