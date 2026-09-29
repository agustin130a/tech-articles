output "state_machine_arn" {
  value = module.step_function.state_machine_arn
}

output "sns_topic_arn" {
  value = module.sns_failures.topic_arn
}

output "scaler_lambda_arn" {
  value = module.lambda_scaler.lambda_function_arn
}

output "notifier_lambda_arn" {
  value = module.lambda_notifier.lambda_function_arn
}

output "schedule_down_name" {
  value = aws_scheduler_schedule.down.name
}

output "schedule_up_name" {
  value = aws_scheduler_schedule.up.name
}

output "scheduler_execution_role_arn" {
  value = aws_iam_role.scheduler_invoke_state_machine.arn
}
