{
  "Comment": "Apagado/encendido nocturno de node groups EKS - Map sobre nodegroups, invoca el scaler, notifica fallos sin bloquear al resto",
  "StartAt": "ScaleNodeGroups",
  "States": {
    "ScaleNodeGroups": {
      "Type": "Map",
      "ItemsPath": "$.nodegroups",
      "ItemSelector": {
        "cluster_name.$": "$.cluster_name",
        "nodegroup.$": "$$.Map.Item.Value"
      },
      "MaxConcurrency": ${max_concurrency},
      "ItemProcessor": {
        "ProcessorConfig": {
          "Mode": "INLINE"
        },
        "StartAt": "InvokeScaler",
        "States": {
          "InvokeScaler": {
            "Type": "Task",
            "Resource": "arn:aws:states:::lambda:invoke",
            "Parameters": {
              "FunctionName": "${scaler_lambda_arn}",
              "Payload.$": "$"
            },
            "ResultSelector": {
              "Payload.$": "$.Payload"
            },
            "OutputPath": "$.Payload",
            "TimeoutSeconds": ${scaler_timeout_seconds},
            "Retry": [
              {
                "ErrorEquals": ["States.ALL"],
                "IntervalSeconds": 10,
                "MaxAttempts": 3,
                "BackoffRate": 2.0
              }
            ],
            "Catch": [
              {
                "ErrorEquals": ["States.ALL"],
                "ResultPath": "$.error",
                "Next": "NotifyFailure"
              }
            ],
            "End": true
          },
          "NotifyFailure": {
            "Type": "Task",
            "Resource": "arn:aws:states:::sns:publish",
            "Parameters": {
              "TopicArn": "${sns_topic_arn}",
              "Subject": "Apagado nocturno EKS: fallo al escalar un node group",
              "Message.$": "States.JsonToString($)"
            },
            "End": true
          }
        }
      },
      "End": true
    }
  }
}
