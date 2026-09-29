terraform {
  required_version = ">= 1.5.5"

  # Provider AWS >= 6.28: versión mínima que exigen terraform-aws-modules/lambda, step-functions y sns en las
  # versiones fijadas abajo (confirmado contra el versions.tf de cada tag, no solo por lectura de
  # docs). Si tu repo fija una versión de aws menor en otros módulos, no pasa nada: el bloque
  # `provider "aws"` de este módulo es local a la unit que lo llama.
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

data "aws_caller_identity" "current" {}

locals {
  scaler_function_name   = "${var.name_prefix}-scaler"
  notifier_function_name = "${var.name_prefix}-notifier"
  state_machine_name     = "${var.name_prefix}-state-machine"
  sns_topic_name         = "${var.name_prefix}-failures"

  # Ajusta esta ruta si mueves el módulo: apunta a la carpeta lambda/ en la raíz del proyecto.
  lambda_code_root      = "${path.module}/../../../lambda"
  statemachine_def_path = "${path.module}/statemachine.json.tpl"
}

# ---------------------------------------------------------------------------------------------------------------------
# SNS — notificación de fallos (lo consume la Lambda notifier)
# ---------------------------------------------------------------------------------------------------------------------
module "sns_failures" {
  source  = "terraform-aws-modules/sns/aws"
  version = "~> 7.1"

  name = local.sns_topic_name
  tags = var.tags
}

# ---------------------------------------------------------------------------------------------------------------------
# LAMBDA — scaler (ajusta min/desired/max del ASG de cada node group)
# ---------------------------------------------------------------------------------------------------------------------
module "lambda_scaler" {
  source  = "terraform-aws-modules/lambda/aws"
  version = "~> 8.8"

  function_name = local.scaler_function_name
  description   = "Ajusta min/desired/max del ASG de un node group EKS (apagado nocturno)."
  handler       = "handler.handler"
  runtime       = var.lambda_runtime
  timeout       = var.scaler_timeout_seconds

  source_path = "${local.lambda_code_root}/scaler"

  attach_policy_statements = true
  policy_statements = {
    describe_nodegroup = {
      effect    = "Allow"
      actions   = ["eks:DescribeNodegroup"]
      resources = ["arn:aws:eks:${var.aws_region}:${data.aws_caller_identity.current.account_id}:nodegroup/${var.cluster_name}/*/*"]
    }
    scale_asg = {
      effect    = "Allow"
      actions   = ["autoscaling:DescribeAutoScalingGroups", "autoscaling:UpdateAutoScalingGroup"]
      resources = ["*"]
      # OJO: esta `condition` tiene que ser una LISTA de objetos, no un objeto suelto. El módulo
      # itera policy_statements[*].condition esperando [{test, variable, values}] — con un objeto
      # suelto falla en tiempo de APPLY con "Unsupported attribute" (el tipo es `any`, así que
      # `terraform validate` no lo detecta). Costó un apply real descubrir esto.
      condition = [
        {
          test     = "StringEquals"
          variable = "autoscaling:ResourceTag/eks:cluster-name"
          values   = [var.cluster_name]
        }
      ]
    }
  }

  tags = var.tags
}

# ---------------------------------------------------------------------------------------------------------------------
# LAMBDA — notifier (SNS -> Slack, webhook vía SSM SecureString)
# ---------------------------------------------------------------------------------------------------------------------
module "lambda_notifier" {
  source  = "terraform-aws-modules/lambda/aws"
  version = "~> 8.8"

  function_name = local.notifier_function_name
  description   = "Publica en Slack (Incoming Webhook vía SSM) los fallos del apagado nocturno."
  handler       = "handler.handler"
  runtime       = var.lambda_runtime
  timeout       = 10

  source_path = "${local.lambda_code_root}/notifier"

  environment_variables = {
    SLACK_WEBHOOK_PARAM_NAME = var.slack_webhook_ssm_parameter_name
  }

  attach_policy_statements = true
  policy_statements = {
    read_webhook_param = {
      effect    = "Allow"
      actions   = ["ssm:GetParameter"]
      resources = ["arn:aws:ssm:${var.aws_region}:${data.aws_caller_identity.current.account_id}:parameter${var.slack_webhook_ssm_parameter_name}"]
    }
    decrypt_webhook_param = {
      effect    = "Allow"
      actions   = ["kms:Decrypt"]
      resources = ["arn:aws:kms:${var.aws_region}:${data.aws_caller_identity.current.account_id}:alias/aws/ssm"]
    }
  }

  allowed_triggers = {
    sns = {
      principal  = "sns.amazonaws.com"
      source_arn = module.sns_failures.topic_arn
    }
  }
  # Sin publish=true (por defecto false) no hay una "current version" real distinta de $LATEST — el
  # módulo igual intenta crear un permiso calificado a esa versión si no se le indica lo contrario, y
  # falla: "We currently do not support adding policies for $LATEST". Encontrado en un apply real.
  create_current_version_allowed_triggers = false

  tags = var.tags
}

resource "aws_sns_topic_subscription" "notifier" {
  topic_arn = module.sns_failures.topic_arn
  protocol  = "lambda"
  endpoint  = module.lambda_notifier.lambda_function_arn
}

# ---------------------------------------------------------------------------------------------------------------------
# STEP FUNCTION — Map sobre nodegroups, invoca el scaler, notifica fallos sin bloquear al resto
# ---------------------------------------------------------------------------------------------------------------------
module "step_function" {
  source  = "terraform-aws-modules/step-functions/aws"
  version = "~> 5.1"

  name = local.state_machine_name
  type = "STANDARD"

  definition = templatefile(local.statemachine_def_path, {
    scaler_lambda_arn      = module.lambda_scaler.lambda_function_arn
    sns_topic_arn          = module.sns_failures.topic_arn
    max_concurrency        = var.map_max_concurrency
    scaler_timeout_seconds = var.scaler_timeout_seconds
  })

  service_integrations = {
    lambda = {
      lambda = [module.lambda_scaler.lambda_function_arn]
    }
    sns = {
      sns = [module.sns_failures.topic_arn]
    }
  }

  tags = var.tags
}

# ---------------------------------------------------------------------------------------------------------------------
# EVENTBRIDGE SCHEDULER — apagado (down) y encendido (up), mismo target (la Step Function)
# ---------------------------------------------------------------------------------------------------------------------
# Se usa EventBridge Scheduler (aws_scheduler_schedule), no EventBridge Rules clásicas: Scheduler
# soporta `schedule_expression_timezone` y ajusta el cambio de horario de verano/invierno (DST)
# solo; las Rules clásicas solo soportan cron en UTC. Va con recursos directos, aunque
# terraform-aws-modules/eventbridge/aws también soporta Scheduler (input `schedules`).
data "aws_iam_policy_document" "scheduler_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["scheduler.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "scheduler_invoke_state_machine" {
  name               = "${var.name_prefix}-scheduler-invoke-sfn"
  assume_role_policy = data.aws_iam_policy_document.scheduler_assume_role.json
  tags               = var.tags
}

data "aws_iam_policy_document" "scheduler_invoke_state_machine" {
  statement {
    actions   = ["states:StartExecution"]
    resources = [module.step_function.state_machine_arn]
  }
}

resource "aws_iam_role_policy" "scheduler_invoke_state_machine" {
  name   = "invoke-state-machine"
  role   = aws_iam_role.scheduler_invoke_state_machine.id
  policy = data.aws_iam_policy_document.scheduler_invoke_state_machine.json
}

resource "aws_scheduler_schedule" "down" {
  name       = var.schedule_down_name
  group_name = "default" # el grupo "default" ya existe en toda cuenta/región, no hace falta crearlo
  state      = var.schedule_state

  schedule_expression          = var.shutdown_cron_expression
  schedule_expression_timezone = var.schedule_timezone

  flexible_time_window {
    mode = "OFF"
  }

  target {
    arn      = module.step_function.state_machine_arn
    role_arn = aws_iam_role.scheduler_invoke_state_machine.arn

    input = jsonencode({
      cluster_name = var.cluster_name
      nodegroups = [for ng in var.nodegroups : {
        name         = ng.name
        min_size     = 0
        desired_size = 0
        max_size     = 0
      }]
    })
  }
}

resource "aws_scheduler_schedule" "up" {
  name       = var.schedule_up_name
  group_name = "default"
  state      = var.schedule_state

  schedule_expression          = var.startup_cron_expression
  schedule_expression_timezone = var.schedule_timezone

  flexible_time_window {
    mode = "OFF"
  }

  target {
    arn      = module.step_function.state_machine_arn
    role_arn = aws_iam_role.scheduler_invoke_state_machine.arn

    input = jsonencode({
      cluster_name = var.cluster_name
      nodegroups = [for ng in var.nodegroups : {
        name         = ng.name
        min_size     = ng.restore_min_size
        desired_size = ng.restore_desired_size
        max_size     = ng.restore_max_size
      }]
    })
  }
}
