# 📖 Infrastructure Deployment & Reproduction Guide

This guide documents the exact step-by-step procedure used to provision, configure, validate, and tear down the **Terraform AWS Production Infrastructure**.

> ⚠️ **IMPORTANT NOTICE: INFRASTRUCTURE STATUS**
> The AWS infrastructure for this project has already been **fully validated and destroyed** (`terraform destroy`) to avoid ongoing AWS cloud costs.
> The instructions below are provided as a **technical reference runbook** for reproducing and understanding the deployment lifecycle. **Do not execute `terraform apply` or `terraform destroy` unless you explicitly intend to spin up live billable AWS resources.**

---

## 1. Prerequisites & Environment Setup

Before provisioning the infrastructure, ensure the following local tools and AWS assets are configured:

### Required Tools
* **AWS CLI** (v2.x+): Configured with appropriate IAM administrative permissions.
* **Terraform** (v1.14+): Installed locally.
* **Docker** (v24.x+): For local container testing.
* **Git**: For version control.

```bash
# Verify local tool installations
aws --version
terraform -version
docker --version
git --version
```

### AWS Account Configuration
1. Configure AWS CLI credentials:
   ```bash
   aws configure
   # Enter AWS Access Key ID
   # Enter AWS Secret Access Key
   # Default region name: ap-south-1
   # Default output format: json
   ```
2. **EC2 SSH Key Pair**: Ensure an EC2 Key Pair named `devops-key` exists in the `ap-south-1` (Mumbai) region:
   ```bash
   aws ec2 describe-key-pairs --key-names devops-key --region ap-south-1
   ```

---

## 2. Terraform Execution Workflow

### Step 1: Clone Repository & Navigate to Terraform Directory
```bash
git clone https://github.com/omkarmm19/terraform-aws-production-infrastructure.git
cd terraform-aws-production-infrastructure/terraform
```

### Step 2: Initialize Terraform Working Directory
Downloads the AWS provider plugin (`hashicorp/aws ~> 6.0`):
```bash
terraform init
```

### Step 3: Format & Validate Syntax
Ensures standard HCL styling and validates configuration consistency without contacting AWS:
```bash
terraform fmt -check
terraform validate
```

### Step 4: Generate & Inspect Execution Plan
Previews the exact set of resources Terraform will create:
```bash
terraform plan -out=tfplan
```

### Step 5: Provision Infrastructure
Applies the planned changes to AWS:
```bash
terraform apply tfplan
```

### Step 6: Retrieve Outputs
View created resource identifiers:
```bash
terraform output
```

---

## 3. CI/CD Deployment Setup (GitHub Actions)

The deployment pipeline (`.github/workflows/deploy.yml`) automates container delivery to EC2 upon pushes to the `main` branch.

### Required GitHub Repository Secrets

Navigate to **GitHub Repository -> Settings -> Secrets and variables -> Actions** and add:

| Secret Name | Description | Example / Value |
|---|---|---|
| `EC2_HOST` | Public IP of the web EC2 instance | Output from `terraform output ec2_public_ip` |
| `EC2_USERNAME` | SSH username for Ubuntu AMI | `ubuntu` |
| `EC2_SSH_KEY` | Private SSH key matching `devops-key` | `-----BEGIN OPENSSH PRIVATE KEY-----...` |

### Pipeline Workflow Trigger
When a developer pushes changes to `main`:
1. GitHub Actions runner checks out code.
2. Configures SSH credentials in `~/.ssh/known_hosts`.
3. Synchronizes the `app/` folder to `/home/ubuntu/app` on the EC2 host via `scp`.
4. Executes remote Docker commands:
   ```bash
   docker rm -f production-app 2>/dev/null || true
   docker build -t production-infrastructure:latest /home/ubuntu/app
   docker run -d -p 80:80 --name production-app production-infrastructure:latest
   ```

---

## 4. Post-Deployment Verification & Testing Runbook

Once provisioned, the following checks were performed to validate the infrastructure:

### 1. Application Load Balancer Endpoint Check
Retrieve the ALB DNS name from the AWS Console or EC2 ALB dashboard and query it:
```bash
curl -I http://<ALB-DNS-NAME>
# Expected HTTP Response: HTTP/1.1 200 OK
```

### 2. Target Group Health Status
Verify that all registered EC2 instances and ASG instances pass health checks:
```bash
aws elbv2 describe-target-health \
  --target-group-arn $(aws elbv2 describe-target-groups --names "terraform-aws-production-tg" --query "TargetGroups[0].TargetGroupArn" --output text) \
  --region ap-south-1
```
*Expected State:* Target instances report `TargetHealth.State = "healthy"`.

### 3. Auto Scaling Group Scaling Check
Verify that the ASG maintained the desired instance count (2 instances) across both subnets:
```bash
aws autoscaling describe-auto-scaling-groups \
  --auto-scaling-group-names "terraform-aws-production-asg" \
  --region ap-south-1 \
  --query "AutoScalingGroups[0].Instances[].{InstanceId:InstanceId,AZ:AvailabilityZone,HealthStatus:HealthStatus}"
```

### 4. CloudWatch Metric Alarms Check
Confirm that metric alarms are active and monitoring `CPUUtilization`:
```bash
aws cloudwatch describe-alarms \
  --alarm-names "terraform-aws-production-high-cpu" "terraform-aws-production-low-cpu" \
  --region ap-south-1 \
  --query "MetricAlarms[].{Name:AlarmName,State:StateValue,Threshold:Threshold}"
```

---

## 5. Teardown & Cost Management

To prevent idle infrastructure costs on AWS:

```bash
cd terraform
terraform destroy -auto-approve
```

### Destruction Verification
Check that `terraform.tfstate` reflects 0 active resources:
```bash
terraform state list
# Should return empty output
```
All AWS infrastructure in this repository was cleanly destroyed following phase validation.
