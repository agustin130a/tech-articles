variable "aws_region" {
  description = "Región del provider (IAM es global)"
  type        = string
  default     = "us-east-2"
}

variable "role_name" {
  description = "Nombre del rol que asumen los workflows"
  type        = string
  default     = "gha-oidc-restrict-lab"
}

variable "github_org" {
  description = "Organización (u owner) de GitHub"
  type        = string
}

variable "github_org_id" {
  description = "ID numérico de la org (gh api orgs/<org> -q .id), para el formato de sub por IDs inmutables"
  type        = string
  default     = null
}

variable "github_repo" {
  description = "Repo que contiene los workflows de deploy"
  type        = string
}

variable "github_repo_id" {
  description = "ID numérico del repo de deploy (gh api repos/<org>/<repo> -q .id)"
  type        = string
}

variable "branch" {
  description = "Rama desde la que se permite correr los workflows de deploy"
  type        = string
  default     = "main"
}

variable "allowed_actor_ids" {
  description = "IDs numéricos de los usuarios de GitHub autorizados (gh api users/<login> -q .id)"
  type        = list(string)
}

variable "allowed_workflows" {
  description = "Archivos de workflow (en .github/workflows/) que pueden asumir el rol"
  type        = list(string)
  default     = ["deploy.yaml", "rollback.yaml", "upgrade-platform.yaml"]
}

variable "allowed_caller_workflows" {
  description = "Nombres (name:) de los workflows que pueden disparar la corrida, para cuando allowed_workflows son reusables. Vacío: no se restringe"
  type        = list(string)
  default     = []
}

variable "restrict_ref" {
  description = "true: la corrida tiene que ser de la rama principal (claim ref), no solo el workflow"
  type        = bool
  default     = false
}

variable "restrict" {
  description = "false: trust policy solo por sub (escenario de antes). true: además actor_id y job_workflow_ref"
  type        = bool
  default     = true
}
