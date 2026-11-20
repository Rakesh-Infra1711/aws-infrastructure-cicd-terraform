# Containers: Docker, ECR and ECS Fargate

The same Flask app from [`app/`](../app) also runs as a Docker container on
**Amazon ECS Fargate**, built and deployed by GitHub Actions.

```
Developer push / PR
      |
      v
GitHub Actions (.github/workflows/docker.yml)
  1. hadolint        lint the Dockerfile
  2. test stage      run pytest inside the image build
  3. build           multi-stage runtime image (non-root user, healthcheck)
  4. smoke test      run the container, check /health, check it isn't root
  5. Trivy           scan the image, fail on CRITICAL vulnerabilities
  6. terraform test  offline checks of the ECS stack (fmt, validate, 5 tests)
      |
      |  merge to main ("production" environment, OIDC: no stored AWS keys)
      v
  7. push            image to Amazon ECR, tagged with the git commit SHA
  8. deploy          new ECS task definition revision -> update service
  9. verify          wait for the rollout, fail if the circuit breaker rolled back
 10. live check      curl the new task's /health and match the commit SHA
```

| Item | Location |
|---|---|
| Dockerfile (multi-stage) | [`app/Dockerfile`](../app/Dockerfile) |
| Build-context exclusions | [`app/.dockerignore`](../app/.dockerignore) |
| Local stack (app + MySQL) | [`docker-compose.yml`](../docker-compose.yml) |
| ECR, ECS cluster/service, IAM, logs | [`ecs/`](../ecs) |
| Offline Terraform tests | [`ecs/tests/ecs.tftest.hcl`](../ecs/tests/ecs.tftest.hcl) |
| Pipeline | [`.github/workflows/docker.yml`](../.github/workflows/docker.yml) |

## 1. Run it locally

```bash
docker compose up --build        # app on http://localhost:8080 with a MySQL container
curl localhost:8080/health       # {"status":"ok","version":"local-compose"}
curl localhost:8080/db           # writes a row to MySQL and returns the visit count
docker compose down -v           # stop and delete the local database volume
```

Build and run the image on its own:

```bash
docker build -t devops-app:local --target runtime app     # build from app/Dockerfile
docker build --target test app                            # run the unit tests in the build
docker run -d --name app -p 8080:8080 -e DISABLE_IMDS=1 devops-app:local
docker ps                                                 # STATUS shows (healthy)
docker logs -f app
docker exec -it app sh
docker rm -f app
```

## 2. Image design: why it is small and safe

| Technique | Where | Why |
|---|---|---|
| `python:3.12-slim` base | Dockerfile | Much smaller than the full Python image |
| Multi-stage build | `build` -> `runtime` | Pip, build files and tests never reach the final image |
| Dependencies copied before code | `COPY requirements.txt` first | The slow `pip install` layer stays cached until dependencies change |
| `.dockerignore` | `app/.dockerignore` | Keeps `.git`, caches, venvs and `.env` files out of the build context |
| Non-root user | `USER app` | A compromised process has no root inside the container |
| `HEALTHCHECK` | Dockerfile and task definition | Docker and ECS replace unhealthy containers |
| `exec gunicorn` | `CMD` | Gunicorn gets signals directly, so `docker stop` shuts it down cleanly |
| No secrets in the image | app reads Secrets Manager at runtime | Images can be shared and scanned safely |

## 3. Deploy to AWS

**Cost:** one Fargate task (0.25 vCPU, 0.5 GB) plus its public IPv4 address costs
roughly **USD 0.016 per hour (about USD 12 per month)** in ap-south-1, plus a few cents
for ECR storage and logs. Scale to 0 or destroy the stack when you are not demoing it.

1. Create the stack from your machine (local state):
   ```bash
   cd ecs
   cp terraform.tfvars.example terraform.tfvars   # set allowed_cidr to your IP/32
   # If the GitHub OIDC provider already exists in the account (e.g. from
   # terraform/bootstrap), set create_github_oidc_provider = false
   terraform init
   terraform test                                 # offline checks, no AWS calls
   terraform apply
   terraform output github_variables
   ```
2. In GitHub, go to **Settings > Secrets and variables > Actions > Variables** and add
   each value from `github_variables`: `ECS_DEPLOY_ROLE_ARN`, `ECR_REPOSITORY`,
   `ECS_CLUSTER`, `ECS_SERVICE`, `ECS_TASK_FAMILY` (and `AWS_REGION` if not ap-south-1).
3. Make sure the **production** environment exists under **Settings > Environments**
   (add yourself as a required reviewer for a manual approval gate).
4. Run **Actions > Docker CI/CD (ECR + ECS Fargate) > Run workflow** with
   `desired_count = 1`, or merge any change under `app/`.
5. Open the job summary: it shows the app URL `http://<task-public-ip>:8080`.

Useful commands:

```bash
aws ecs describe-services --cluster devops-task-cluster --services devops-task-app \
  --query "services[0].{running:runningCount,desired:desiredCount,deployments:deployments[].rolloutState}"
aws logs tail /ecs/devops-task-app --follow
aws ecr describe-image-scan-findings --repository-name devops-task-app --image-id imageTag=<sha>
```

**Stop or remove:**
- Stop (keeps everything, about USD 0 per hour): Run workflow with `desired_count = 0`.
- Remove everything: `cd ecs && terraform destroy` (ECR images are deleted too).

## 4. Reliability and security

- **Zero-downtime rollout:** minimum healthy 100%, maximum 200%. New tasks start and
  pass health checks before old ones stop.
- **Automatic rollback:** the ECS deployment circuit breaker rolls back a version that
  keeps failing, and the pipeline then fails instead of reporting success.
- **Immutable tags:** every image is tagged with its commit SHA and ECR refuses
  overwrites, so you always know exactly what is running. Rolling back means deploying
  an earlier SHA.
- **Least-privilege deploy role:** GitHub can assume it only from the `production`
  environment of this repository; it can push only to this ECR repository, update
  only this service, and pass only the two ECS task roles.
- **Scanning:** Trivy in CI blocks CRITICAL vulnerabilities; ECR also scans on push.
- **Lifecycle policy:** ECR keeps the last 10 images and removes untagged ones after a day.

## 5. Demo shortcuts vs production

To keep the demo cheap, tasks run in the **default VPC with a public IP** and no load
balancer. For production I would:

- put an **ALB with an ACM certificate** in front, with tasks in **private subnets**
  (reached through a NAT gateway or VPC endpoints for ECR, S3 and CloudWatch Logs);
- run at least **2 tasks across 2 AZs** with **ECS Service Auto Scaling** on CPU or
  request count;
- move Terraform state to **S3 with locking**, like the EC2 stack;
- inject database credentials with the task definition's **`secrets`** field from
  Secrets Manager.
