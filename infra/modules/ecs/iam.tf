# Two roles, and the distinction matters:
#
#   execution role -- used by the ECS agent before the container starts: pull
#                     the image, fetch secrets, create the log stream.
#   task role      -- assumed by the application code itself at runtime.
#
# Collapsing them into one is the usual shortcut, and it hands the application
# permission to read every secret referenced by the task definition.

data "aws_iam_policy_document" "assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "execution" {
  name               = "${var.name}-task-execution"
  description        = "Pulls images, reads secrets and writes logs for ${var.name}"
  assume_role_policy = data.aws_iam_policy_document.assume_role.json

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "execution_managed" {
  role       = aws_iam_role.execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# The managed policy above covers ECR and Logs but not Secrets Manager, and it
# is scoped to exactly the secrets this task declares rather than "*".
data "aws_iam_policy_document" "execution_secrets" {
  count = length(var.container_secrets) > 0 ? 1 : 0

  statement {
    effect    = "Allow"
    actions   = ["secretsmanager:GetSecretValue"]
    resources = values(var.container_secrets)
  }
}

resource "aws_iam_role_policy" "execution_secrets" {
  count = length(var.container_secrets) > 0 ? 1 : 0

  name   = "read-task-secrets"
  role   = aws_iam_role.execution.id
  policy = data.aws_iam_policy_document.execution_secrets[0].json
}

resource "aws_iam_role" "task" {
  name               = "${var.name}-task"
  description        = "Runtime identity for the ${var.name} application"
  assume_role_policy = data.aws_iam_policy_document.assume_role.json

  tags = var.tags
}

# ECS Exec talks to SSM over the task role, not the execution role.
data "aws_iam_policy_document" "task_exec_command" {
  count = var.enable_execute_command ? 1 : 0

  statement {
    effect = "Allow"
    actions = [
      "ssmmessages:CreateControlChannel",
      "ssmmessages:CreateDataChannel",
      "ssmmessages:OpenControlChannel",
      "ssmmessages:OpenDataChannel",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "task_exec_command" {
  count = var.enable_execute_command ? 1 : 0

  name   = "ecs-exec"
  role   = aws_iam_role.task.id
  policy = data.aws_iam_policy_document.task_exec_command[0].json
}
