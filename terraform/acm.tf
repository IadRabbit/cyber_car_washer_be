# The ALB is only exposed under its own AWS-generated DNS name (no custom
# domain), so ACM cannot issue a publicly-trusted certificate for it. This
# generates a self-signed certificate instead and imports it into ACM.
# Clients hitting the ALB will need to skip/ignore TLS verification since
# the cert isn't signed by a trusted CA.
resource "tls_private_key" "alb" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

resource "tls_self_signed_cert" "alb" {
  private_key_pem = tls_private_key.alb.private_key_pem

  subject {
    common_name  = "${var.project_name}.local"
    organization = var.project_name
  }

  validity_period_hours = 8760 # 1 year

  allowed_uses = [
    "key_encipherment",
    "digital_signature",
    "server_auth",
  ]
}

resource "aws_acm_certificate" "alb" {
  private_key      = tls_private_key.alb.private_key_pem
  certificate_body = tls_self_signed_cert.alb.cert_pem

  lifecycle {
    create_before_destroy = true
  }

  tags = {
    Name = "${var.project_name}-self-signed-cert"
  }
}
