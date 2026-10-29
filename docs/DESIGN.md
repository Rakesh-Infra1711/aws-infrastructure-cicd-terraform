# Design Decisions

Why each part is built the way it is. Use this to explain the solution in a review or interview.

## Networking

**Why three subnet tiers (public, app, DB)?**
Only the ALB and NAT Gateway need public IPs. App instances sit in private subnets and are reachable only through the ALB. DB subnets have **no route to the internet at all**, not even through NAT, so the database can't reach out or be reached from outside.

**Why a NAT Gateway?**
Private instances need *outbound* internet to install packages and call AWS APIs (Secrets Manager, SSM). NAT allows outbound connections and blocks all inbound ones.

**Why one NAT instead of one per AZ?**
Cost. A single NAT is a single point of failure for *outbound* traffic only; inbound user traffic through the ALB is unaffected. Setting `single_nat_gateway = false` creates one NAT per AZ with per-AZ route tables, which is the production setting.

**Why an S3 gateway endpoint?**
It's free. Instances download code from S3 over the AWS network instead of through the NAT, which is cheaper and more private.

## Load balancer and HTTPS

- TLS terminates at the ALB using a free **ACM** certificate that renews automatically.
- `ELBSecurityPolicy-TLS13-1-2-2021-06` allows only TLS 1.2 and 1.3.
- Port 80 exists only to return a **301 redirect** to HTTPS, so no application traffic is served in plain text.
- `drop_invalid_header_fields = true` protects against HTTP request smuggling.
- Access logs go to S3. The bucket uses **SSE-S3** because ALB log delivery doesn't support SSE-KMS.

## Compute

**Why an Auto Scaling Group with ELB health checks?**
If the app on an instance stops answering `/health`, the ALB marks it unhealthy and the ASG **replaces the instance automatically** (self-healing). Instances are spread across 2 AZs, so losing one AZ keeps the app online.

**How is code deployed?**
Terraform uploads `app/` to S3 and puts a hash of the code into the launch template's user data. Any code change creates a new launch template version, and the ASG performs a **rolling instance refresh** with at least 50% of instances healthy, giving zero downtime. Each instance is rebuilt from scratch (immutable infrastructure), so there's no configuration drift.

**Why IMDSv2 and no SSH?**
IMDSv2 requires a session token, which blocks SSRF attacks from stealing instance credentials. There's no SSH key and no port 22. Admin access goes through **SSM Session Manager**, which is IAM-controlled and logged.

## Database and secrets

- **RDS-managed master password** (`manage_master_user_password`): RDS generates the password, stores it in Secrets Manager, and rotates it every 7 days by default. Terraform never sees it, so it's not in code or state.
- The app reads the secret at runtime with its **instance role** and caches it for 5 minutes, so it picks up rotated passwords.
- `require_secure_transport = 1` rejects non-TLS connections. The app verifies the server certificate against the RDS CA bundle.
- Storage is encrypted; the DB is not publicly accessible, has 7-day automated backups, and offers optional Multi-AZ standby with automatic failover.

## IAM: least privilege

| Role | Can do | Cannot do |
|---|---|---|
| EC2 instance role | Read **one** secret ARN; read `s3://app-bucket/app/*`; read/write `uploads/*`; SSM agent | Read other secrets, other buckets, or other prefixes |
| GitHub Actions role | Manage this project's services; create IAM roles named `devops-task-*` only | Create or modify any other IAM user or role; be assumed from any other repository |

## Security groups (SG chaining)

```
0.0.0.0/0 ──443/80──► ALB-SG ──8080──► App-SG ──3306──► DB-SG
```

Rules reference **security group IDs, not IP ranges**. If instances are replaced and get new IPs, the rules still apply only to the right tier.

## Terraform and CI/CD

- **Remote state** in S3: versioned (recover from mistakes), KMS-encrypted, TLS-only, and locked with `use_lockfile` (Terraform 1.10+, no DynamoDB table needed).
- **OIDC instead of access keys:** GitHub gets short-lived credentials per run, so there are no long-lived secrets to leak or rotate.
- **Plan on PR, apply on merge:** changes are reviewed before reaching AWS, and `apply` uses the *saved* plan, so exactly what was reviewed is what gets deployed.
- **`terraform test`** with a mocked AWS provider checks the security controls on every run (private DB, encryption, HTTPS-only, IMDSv2, private buckets) without creating resources.
- **Post-deploy verification:** the pipeline fails if the app isn't healthy over HTTPS after the rollout.

## What would change for production

| Area | Assessment setting | Production |
|---|---|---|
| NAT | 1 shared | 1 per AZ |
| RDS | Single-AZ, no deletion protection | Multi-AZ, deletion protection, final snapshot |
| Edge | ALB only | + AWS WAF, CloudFront |
| Observability | Default metrics | CloudWatch alarms + SNS, dashboards, VPC flow logs |
| Environments | One | Separate dev/stage/prod (workspaces or separate state keys/accounts) |
| Approval | Optional | Required reviewers on the `production` environment |
