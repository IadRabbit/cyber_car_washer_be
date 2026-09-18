resource "aws_lb" "this" {
  name               = "${var.project_name}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = aws_subnet.public[*].id

  tags = {
    Name = "${var.project_name}-alb"
  }
}

resource "aws_lb_target_group" "lambda" {
  name        = "${var.project_name}-tg"
  target_type = "lambda"

  # Health checks would invoke the Lambda with a synthetic request that
  # fails our payload validation (400), marking the target unhealthy.
  # Lambda targets don't need health checks the way instance targets do.
  health_check {
    enabled  = false
    interval = 35
    timeout  = 30
  }
}

resource "aws_lb_target_group_attachment" "lambda" {
  target_group_arn = aws_lb_target_group.lambda.arn
  target_id        = aws_lambda_function.this.arn

  depends_on = [aws_lambda_permission.alb_invoke]
}

resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.this.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = aws_acm_certificate.alb.arn

  default_action {
    type = "fixed-response"

    fixed_response {
      status_code  = "404"
      content_type = "text/plain"
      message_body = "Not Found"
    }
  }
}

resource "aws_lb_listener_rule" "api_key" {
  listener_arn = aws_lb_listener.https.arn
  priority     = 1

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.lambda.arn
  }

  condition {
    http_header {
      http_header_name = "X-Api-Key"
      values           = [var.api_key]
    }
  }
}
