output "role_arn" {
  description = "ARN del rol, para la variable AWS_ROLE_ARN del repo"
  value       = aws_iam_role.deploy.arn
}

output "trust_policy" {
  description = "Trust policy aplicada"
  value       = jsondecode(aws_iam_role.deploy.assume_role_policy)
}
