output "alb_dns_name" {
  description = "Public DNS name of the ALB. Access it over https:// — the cert is self-signed, so clients must skip/ignore TLS verification."
  value       = aws_lb.this.dns_name
}

output "lambda_function_name" {
  description = "Name of the deployed Lambda function"
  value       = aws_lambda_function.this.function_name
}
