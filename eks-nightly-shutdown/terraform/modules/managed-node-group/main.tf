terraform {
  required_version = ">= 1.5.5"

  required_providers {
    aws = {
      source = "hashicorp/aws"
      # Sin upper bound: este módulo no usa nada específico de una major version de AWS, y en el
      # ejemplo (terraform/example/) convive en el mismo root que el módulo nightly-shutdown, que
      # sí necesita >= 6.28 (ver el comentario en ese módulo). Si lo usas en tu propio repo como
      # unit separada (ej. una unit de Terragrunt propia), no hay problema en fijar una versión
      # más vieja aquí — el provider de cada unit es independiente.
      version = ">= 5.72"
    }
  }
}

# ---------------------------------------------------------------------------------------------------------------------
# IAM ROLE PARA LOS NODOS (se crea solo si no se pasa var.node_role_arn)
# ---------------------------------------------------------------------------------------------------------------------
data "aws_iam_policy_document" "eks_node_assume_role_policy" {
  count = var.node_role_arn == null ? 1 : 0

  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "this" {
  count = var.node_role_arn == null ? 1 : 0

  name               = "${var.node_group_name}-nodes"
  assume_role_policy = data.aws_iam_policy_document.eks_node_assume_role_policy[0].json
  tags               = var.tags
}

resource "aws_iam_role_policy_attachment" "this" {
  for_each = var.node_role_arn == null ? toset([
    "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy",
    "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy",
    "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly",
    "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore",
  ]) : toset([])

  role       = aws_iam_role.this[0].name
  policy_arn = each.value
}

locals {
  node_role_arn = var.node_role_arn != null ? var.node_role_arn : aws_iam_role.this[0].arn
}

# ---------------------------------------------------------------------------------------------------------------------
# MANAGED NODE GROUP
# ---------------------------------------------------------------------------------------------------------------------
resource "aws_eks_node_group" "this" {
  cluster_name    = var.cluster_name
  node_group_name = var.node_group_name
  node_role_arn   = local.node_role_arn
  subnet_ids      = var.subnet_ids

  instance_types = var.instance_types
  ami_type       = var.ami_type
  capacity_type  = var.capacity_type
  disk_size      = var.disk_size

  scaling_config {
    min_size     = var.scaling_config.min_size
    desired_size = var.scaling_config.desired_size
    max_size     = var.scaling_config.max_size
  }

  labels = var.labels

  dynamic "taint" {
    for_each = var.taints
    content {
      key    = taint.value.key
      value  = lookup(taint.value, "value", null)
      effect = taint.value.effect
    }
  }

  tags = var.tags

  lifecycle {
    # El scaler de apagado nocturno modifica min/desired/max directamente en el ASG subyacente
    # vía autoscaling:UpdateAutoScalingGroup. Sin ignorar los tres campos aquí, cualquier `apply`
    # posterior de Terraform revierte el apagado (pelea contra la Lambda).
    ignore_changes = [
      scaling_config[0].min_size,
      scaling_config[0].desired_size,
      scaling_config[0].max_size,
    ]
  }

  depends_on = [aws_iam_role_policy_attachment.this]
}
