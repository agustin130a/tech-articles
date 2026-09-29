# ----------------------------------------------------------------------------------------------------------------------
# REQUIRED PARAMETERS
# ----------------------------------------------------------------------------------------------------------------------
variable "cluster_name" {
  description = "Nombre del cluster EKS al que pertenece el node group."
  type        = string
}

variable "node_group_name" {
  description = "Nombre del node group (y base del nombre del IAM role si se crea uno nuevo)."
  type        = string
}

variable "subnet_ids" {
  description = "Subnets donde se lanzan los nodos del node group."
  type        = list(string)
}

variable "scaling_config" {
  description = <<-EOT
    min/desired/max del node group.

    Si este node group participa del apagado nocturno, el scaler lo modifica directamente en el
    ASG en runtime — ver el bloque `lifecycle.ignore_changes` en main.tf, que evita que un `apply`
    de Terraform lo revierta.
  EOT
  type = object({
    min_size     = number
    desired_size = number
    max_size     = number
  })
}

# ----------------------------------------------------------------------------------------------------------------------
# OPTIONAL PARAMETERS
# ----------------------------------------------------------------------------------------------------------------------
variable "node_role_arn" {
  description = "ARN de un IAM role existente para los nodos. Si es null (default), el módulo crea uno nuevo con las policies EKS estándar (WorkerNodePolicy, CNI, ECR read-only, SSM)."
  type        = string
  default     = null
}

variable "instance_types" {
  description = "Tipos de instancia EC2 del node group."
  type        = list(string)
  default     = ["t3.large"]
}

variable "ami_type" {
  description = "Tipo de AMI del node group (ver el recurso aws_eks_node_group)."
  type        = string
  default     = "AL2023_x86_64_STANDARD"
}

variable "capacity_type" {
  description = "ON_DEMAND o SPOT."
  type        = string
  default     = "ON_DEMAND"
}

variable "disk_size" {
  description = "Tamaño de disco (GiB) de los nodos. null usa el default de la AMI."
  type        = number
  default     = null
}

variable "labels" {
  description = "Labels de Kubernetes a aplicar a los nodos del node group."
  type        = map(string)
  default     = {}
}

variable "taints" {
  description = "Taints a aplicar a los nodos del node group. Ej: [{ key = \"nightly-shutdown\", value = \"true\", effect = \"NO_SCHEDULE\" }]"
  type = list(object({
    key    = string
    value  = optional(string)
    effect = string
  }))
  default = []
}

variable "tags" {
  description = "Tags a aplicar a los recursos del módulo."
  type        = map(string)
  default     = {}
}
