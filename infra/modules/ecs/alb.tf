resource "aws_lb" "this" {
  name               = substr("${var.name}-alb", 0, 32)
  load_balancer_type = "application"
  internal           = false
  subnets            = var.public_subnet_ids
  security_groups    = [var.alb_security_group_id]

  enable_deletion_protection = var.enable_deletion_protection

  # Reject requests with headers the ALB cannot parse instead of passing them
  # through to the application -- cheap protection against request smuggling.
  drop_invalid_header_fields = true

  idle_timeout = 60

  tags = merge(var.tags, { Name = "${var.name}-alb" })
}

resource "aws_lb_target_group" "this" {
  name        = substr("${var.name}-tg", 0, 32)
  port        = var.container_port
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "ip" # awsvpc networking gives every task its own ENI

  deregistration_delay = var.deregistration_delay

  health_check {
    enabled             = true
    path                = var.health_check_path
    matcher             = var.health_check_matcher
    interval            = 15
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }

  tags = merge(var.tags, { Name = "${var.name}-tg" })

  # The service holds a reference to the target group, so a change that forces
  # a new target group has to create the replacement first.
  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.this.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.this.arn
  }

  tags = var.tags
}

# Production would add an HTTPS listener here with an ACM certificate and turn
# this one into a permanent redirect. Left out because it needs a real domain
# and a validated certificate, and this stack is plan-only. See README.
