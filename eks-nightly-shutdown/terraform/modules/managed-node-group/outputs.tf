output "node_group_name" {
  description = "Nombre del node group creado."
  value       = aws_eks_node_group.this.node_group_name
}

output "node_group_arn" {
  description = "ARN del node group."
  value       = aws_eks_node_group.this.arn
}

output "asg_names" {
  description = "Nombres de los Auto Scaling Groups que EKS crea para este node group."
  value       = [for asg in aws_eks_node_group.this.resources[0].autoscaling_groups : asg.name]
}

output "node_role_arn" {
  description = "ARN del IAM role de los nodos (creado por el módulo, o el que se haya pasado en var.node_role_arn)."
  value       = local.node_role_arn
}
