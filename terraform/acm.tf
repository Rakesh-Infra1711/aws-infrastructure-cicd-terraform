# Public TLS certificate for the application domain, validated by DNS.
#
# - If route53_zone_id is set, Terraform creates the validation records and
#   the app alias record automatically.
# - If DNS is hosted elsewhere (e.g. GoDaddy), run the first apply with
#   -target=aws_acm_certificate.app, add the CNAME from the
#   acm_validation_records output at your DNS provider, then apply again.

locals {
  use_route53 = var.route53_zone_id != ""
}

resource "aws_acm_certificate" "app" {
  domain_name       = var.domain_name
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }

  tags = { Name = "${local.name}-cert" }
}

resource "aws_route53_record" "cert_validation" {
  for_each = local.use_route53 ? {
    for dvo in aws_acm_certificate.app.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      type   = dvo.resource_record_type
      record = dvo.resource_record_value
    }
  } : {}

  zone_id         = var.route53_zone_id
  name            = each.value.name
  type            = each.value.type
  records         = [each.value.record]
  ttl             = 300
  allow_overwrite = true
}

resource "aws_acm_certificate_validation" "app" {
  certificate_arn         = aws_acm_certificate.app.arn
  validation_record_fqdns = local.use_route53 ? [for r in aws_route53_record.cert_validation : r.fqdn] : null

  timeouts {
    create = "60m"
  }
}

resource "aws_route53_record" "app" {
  count   = local.use_route53 ? 1 : 0
  zone_id = var.route53_zone_id
  name    = var.domain_name
  type    = "A"

  alias {
    name                   = aws_lb.this.dns_name
    zone_id                = aws_lb.this.zone_id
    evaluate_target_health = true
  }
}
