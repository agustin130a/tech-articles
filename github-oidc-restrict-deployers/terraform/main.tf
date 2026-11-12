# Rol de deploy que asume GitHub Actions por OIDC, con la trust policy restringida por actor y
# por workflow. El rol no tiene políticas de permisos: alcanza para probar quién puede asumirlo
# (sts:GetCallerIdentity no requiere permisos).
# Los valores de tu cuenta/org van en terraform.tfvars (copiar terraform.tfvars.example).

terraform {
  required_version = ">= 1.5.5"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# El proveedor OIDC de GitHub es uno por cuenta y suele estar compartido: se lee, no se crea
data "aws_iam_openid_connect_provider" "github" {
  url = "https://token.actions.githubusercontent.com"
}

locals {
  oidc = "token.actions.githubusercontent.com"

  # Quién (actor_id, inmutable), desde dónde (repo) y qué (workflow + rama) puede asumir el rol
  restrictions = {
    "${local.oidc}:actor_id" = var.allowed_actor_ids
    # job_workflow_ref no alcanza: otro repo puede llamar al workflow como reusable y sus acciones
    # locales (./.github/actions/...) salen del repo que llama
    "${local.oidc}:repository_id" = [var.github_repo_id]
    "${local.oidc}:job_workflow_ref" = [
      for wf in var.allowed_workflows :
      "${var.github_org}/${var.github_repo}/.github/workflows/${wf}@refs/heads/${var.branch}"
    ]
  }

  # Si los workflows permitidos son reusables, job_workflow_ref es el del reusable: workflow (el
  # nombre del que dispara la corrida) distingue a quién lo llama, y ref evita que una rama copie
  # ese nombre y llame al reusable de la rama principal por ruta completa
  caller_restrictions = {
    for k, v in {
      "${local.oidc}:workflow" = var.allowed_caller_workflows
      "${local.oidc}:ref"      = ["refs/heads/${var.branch}"]
    } : k => v if(k == "${local.oidc}:workflow" ? length(var.allowed_caller_workflows) > 0 : var.restrict_ref)
  }
}

resource "aws_iam_role" "deploy" {
  name = var.role_name

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Federated = data.aws_iam_openid_connect_provider.github.arn }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        # Sin restrict queda la policy "de antes": cualquier workflow de la org, desde cualquier rama
        StringEquals = merge(
          { "${local.oidc}:aud" = "sts.amazonaws.com" },
          { for k, v in local.restrictions : k => v if var.restrict },
          { for k, v in local.caller_restrictions : k => v if var.restrict },
        )
        StringLike = {
          # Repos con el formato de sub por IDs inmutables emiten repo:<org>@<org_id>/<repo>@<repo_id>:...
          "${local.oidc}:sub" = compact([
            "repo:${var.github_org}/*",
            var.github_org_id == null ? null : "repo:${var.github_org}@${var.github_org_id}/*",
          ])
        }
      }
    }]
  })
}
