# Screenshots

Capture these after a successful deployment and save them in this folder using the file names below.

| # | File name | What to capture |
|---|---|---|
| 1 | `01-app-https.png` | Browser showing the app at `https://<domain>` with the padlock, database "Connected" |
| 2 | `02-certificate.png` | Browser certificate details (issued by Amazon, valid for your domain) |
| 3 | `03-vpc-subnets.png` | VPC → Subnets: 6 subnets across 2 AZs |
| 4 | `04-route-tables.png` | Route tables: public → IGW, app → NAT, DB with no internet route |
| 5 | `05-alb-listeners.png` | ALB → Listeners: HTTP 80 redirect, HTTPS 443 with ACM certificate |
| 6 | `06-target-group-healthy.png` | Target group → Targets: 2 healthy instances in different AZs |
| 7 | `07-asg.png` | Auto Scaling Group: desired/min/max, instances, instance refresh history |
| 8 | `08-launch-template.png` | Launch template: IMDSv2 required, encrypted EBS |
| 9 | `09-rds.png` | RDS: private, encrypted, in the DB subnet group, not publicly accessible |
| 10 | `10-secrets-manager.png` | Secrets Manager: the RDS-managed secret (do not reveal the value) |
| 11 | `11-security-groups.png` | Security group inbound rules (ALB, App, DB) |
| 12 | `12-iam-role.png` | EC2 role policy showing least-privilege permissions |
| 13 | `13-s3-buckets.png` | S3 buckets: encryption and "Block all public access" on |
| 14 | `14-alb-logs.png` | ALB access log files arriving in the log bucket |
| 15 | `15-github-actions.png` | Successful pipeline run (tests → plan → apply → health check) |
| 16 | `16-validate-script.png` | Terminal output of `./scripts/validate.sh` with all checks passing |
| 17 | `17-http-redirect.png` | `curl -I http://<domain>` showing `301` → `https://` |
