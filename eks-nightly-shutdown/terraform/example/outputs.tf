output "state_machine_arn" {
  value = module.nightly_shutdown.state_machine_arn
}

output "scaler_lambda_arn" {
  value = module.nightly_shutdown.scaler_lambda_arn
}

output "notifier_lambda_arn" {
  value = module.nightly_shutdown.notifier_lambda_arn
}

output "schedule_down_name" {
  value = module.nightly_shutdown.schedule_down_name
}

output "schedule_up_name" {
  value = module.nightly_shutdown.schedule_up_name
}

output "nodegroup_general_asg_names" {
  value = module.nodegroup_general.asg_names
}
