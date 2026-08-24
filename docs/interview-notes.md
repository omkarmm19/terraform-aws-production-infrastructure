# 💼 DevOps & Cloud Architecture Interview Notes

A structured technical reference and interview Q&A guide based on the **AWS Infrastructure with Terraform** implemented in this repository.

---

## 1. Project Elevator Pitch

> *"In this project, I engineered and deployed a production-ready, highly available AWS infrastructure using Terraform as Infrastructure as Code. The architecture spans two availability zones in `ap-south-1` (Mumbai) with a custom VPC, an Application Load Balancer for Layer 7 traffic distribution, an Auto Scaling Group with CPU target tracking (60%) for dynamic elasticity, and Dockerized Nginx web services. Security was hardened by chaining Security Groups so web servers only accept HTTP traffic from the ALB and locking down SSH to a specific administrator IP. The application is continuously deployed via GitHub Actions, and cluster health is monitored with Amazon CloudWatch alarms."*

---

## 2. Networking & Subnet Architecture

### Q: Why did you create subnets across two different Availability Zones?
* **Answer**: AWS Application Load Balancers (ALBs) require a minimum of **two public subnets in distinct Availability Zones** to operate. Distributing resources across `ap-south-1a` and `ap-south-1b` eliminates single-data-center failure points and provides high availability.

### Q: What is the CIDR block design used?
* **VPC**: `10.0.0.0/16` (65,536 total private IP addresses).
* **Public Subnet A**: `10.0.1.0/24` (256 IPs in `ap-south-1a`) - Hosts EC2 Node 1, ASG instances, and ALB Interface A.
* **Public Subnet B**: `10.0.3.0/24` (256 IPs in `ap-south-1b`) - Hosts EC2 Node 2, ASG instances, and ALB Interface B.
* **Private Subnet**: `10.0.2.0/24` (256 IPs in `ap-south-1a`) - Reserved for isolated internal workloads.

---

## 3. Load Balancing & Traffic Distribution

### Q: Why use an Application Load Balancer (ALB) instead of a Network Load Balancer (NLB)?
* **Answer**: The application operates over HTTP (Layer 7). ALB provides advanced Layer 7 features such as host/path-based routing, native Target Group health checks (`/` HTTP check with 30s interval), SSL termination capabilities, and tight integration with AWS Auto Scaling.

### Q: How does ALB health checking work in this project?
* **Path**: `/`
* **Port**: 80 (HTTP)
* **Interval**: 30 seconds
* **Timeout**: 5 seconds
* **Healthy Threshold**: 2 consecutive successful responses (HTTP 200).
* **Unhealthy Threshold**: 2 consecutive failed responses.
* When an instance fails health checks, the ALB immediately stops routing incoming requests to that node while the Auto Scaling Group replaces it.

---

## 4. Auto Scaling & Elasticity

### Q: How does Target Tracking Scaling differ from Simple/Step Scaling?
* **Answer**:
  * **Simple/Step Scaling** requires creating manual CloudWatch alarm actions that increment or decrement instance counts by fixed step values (e.g., add 1 instance if CPU > 80%).
  * **Target Tracking Scaling** (used here with `ASGAverageCPUUtilization = 60%`) behaves like a thermostat. It automatically creates and manages internal CloudWatch alarms to continuously adjust capacity to maintain the average metric at exactly the target value, handling proportional scale-out and scale-in smoothly.

### Q: What is the role of the EC2 Launch Template?
* **Answer**: The Launch Template (`aws_launch_template.web`) defines the instance blueprint: Ubuntu 24.04 AMI, `t3.micro` instance type, `devops-key` SSH key pair, security group association, and the **User Data bootstrap script** that installs Docker and launches the containerized app automatically upon instance launch.

---

## 5. Security & Network Hardening

### Q: How is the Security Group architecture hardened?
* **Answer**: We implemented **Security Group Chaining (Least Privilege Principle)**:
  1. **ALB Security Group (`alb-sg`)**: Ingress on Port 80 is open to `0.0.0.0/0` (public web).
  2. **Web Security Group (`web-sg`)**: Ingress on Port 80 is restricted **strictly to `security_groups = [aws_security_group.alb.id]`**. Direct public access to the EC2 instances on port 80 is completely blocked.
  3. **SSH Access (Port 22)**: Restricted strictly to the administrator's `/32` CIDR block (`14.194.135.206/32`).

---

## 6. Containerization & Application Architecture

### Q: Why use Docker with `nginx:alpine`?
* **Answer**:
  * **Lightweight & Fast**: The `nginx:alpine` image has a tiny footprint (~23MB), minimizing image download time during instance bootstrapping.
  * **Consistency**: Packages the static web application and server runtime identically across local development, standalone EC2s, and ASG nodes.
  * **Process Isolation**: Decouples application execution from the host operating system.

---

## 7. Observability & Monitoring

### Q: What CloudWatch Alarms are configured?
* **High CPU Alarm (`terraform-aws-production-high-cpu`)**:
  * Metric: `CPUUtilization` on `AutoScalingGroupName`
  * Threshold: `> 70%` for 2 evaluation periods of 300 seconds (10 minutes sustained load).
* **Low CPU Alarm (`terraform-aws-production-low-cpu`)**:
  * Metric: `CPUUtilization` on `AutoScalingGroupName`
  * Threshold: `< 20%` for 2 evaluation periods of 300 seconds.

---

## 8. Infrastructure as Code (Terraform) Concepts

### Q: Why use dynamic data sources (e.g., `aws_ami.ubuntu`) instead of hardcoding AMI IDs?
* **Answer**: AMI IDs are region-specific and change frequently as security patches are published. Using the `aws_ami` data source with name and owner filters ensures the latest stable official Ubuntu 24.04 LTS image is retrieved automatically regardless of region updates.

### Q: What is the purpose of `terraform.tfstate`?
* **Answer**: Terraform state maps the declared configuration files to real-world cloud resources, tracks metadata, and manages dependency resolution during incremental updates.

---

## 9. CI/CD Automation (GitHub Actions)

### Q: How does the deployment pipeline handle security credentials?
* **Answer**: No SSH keys or server credentials are stored in git. The workflow leverages **GitHub Actions Encrypted Secrets** (`EC2_SSH_KEY`, `EC2_HOST`, `EC2_USERNAME`). The pipeline dynamically writes the private key into a temporary memory-backed file, restricts permissions (`chmod 600`), and securely executes the build/run commands.

---

## 10. Cost Management & Production Teardown

### Q: What was the post-validation lifecycle strategy?
* **Answer**: After deploying and verifying all 10 project phases and capturing evidence screenshots (ALB routing, ASG health, CloudWatch alarms), `terraform destroy` was executed. This adheres to cloud cost optimization best practices by eliminating recurring idle charges for load balancers and EC2 instances while retaining a 100% reproducible IaC codebase.
