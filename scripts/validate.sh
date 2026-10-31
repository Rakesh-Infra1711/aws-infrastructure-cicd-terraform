#!/usr/bin/env bash
# End-to-end validation of the deployed environment.
# Usage (from the repo root, after terraform apply):  ./scripts/validate.sh
set -uo pipefail

cd "$(dirname "$0")/../terraform"

# tr -d '\r' keeps this working in Git Bash on Windows, where tools emit CRLF
out() { terraform output -raw "$1" | tr -d '\r'; }
URL=$(out app_url)
ALB=$(out alb_dns_name)
TG=$(out target_group_arn)
ASG=$(out asg_name)
HOST=${URL#https://}
PASS=0
FAIL=0

check() {
  local name="$1"; shift
  if "$@" >/dev/null 2>&1; then
    echo "PASS  $name"; PASS=$((PASS + 1))
  else
    echo "FAIL  $name"; FAIL=$((FAIL + 1))
  fi
}

echo "Validating $URL"
echo "------------------------------------------------------------"

check "HTTPS /health returns 200" curl -fsS "$URL/health"
check "HTTPS /db connects to RDS over TLS" curl -fsS "$URL/db"
check "HTTP redirects to HTTPS (301)" \
  bash -c "[ \"\$(curl -s -o /dev/null -w '%{http_code}' http://$HOST/)\" = 301 ]"
check "TLS certificate is valid for $HOST" \
  bash -c "echo | openssl s_client -connect $HOST:443 -servername $HOST 2>/dev/null | openssl x509 -noout -checkend 0"
check "TLS 1.1 is rejected" \
  bash -c "! echo | openssl s_client -connect $HOST:443 -servername $HOST -tls1_1 >/dev/null 2>&1"

HEALTHY=$(aws elbv2 describe-target-health --target-group-arn "$TG" \
  --query "length(TargetHealthDescriptions[?TargetHealth.State=='healthy'])" --output text | tr -d '\r')
check "At least 2 healthy targets in the target group (found: $HEALTHY)" test "$HEALTHY" -ge 2

AZS=$(aws autoscaling describe-auto-scaling-groups --auto-scaling-group-names "$ASG" \
  --query "AutoScalingGroups[0].Instances[].AvailabilityZone" --output text | tr -d '\r' | tr '\t' '\n' | sort -u | wc -l | tr -d ' ')
check "Instances spread across multiple AZs (found: $AZS)" test "$AZS" -ge 2

echo
echo "Load balancing across instances (5 requests):"
for _ in 1 2 3 4 5; do
  curl -fsS "$URL/" | grep -o 'i-[0-9a-f]\{8,17\}' | head -1
done | sort | uniq -c

echo "------------------------------------------------------------"
echo "ALB DNS: $ALB"
echo "Result: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
