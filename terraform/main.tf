resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name    = "${var.project_name}-vpc"
    Project = var.project_name
  }
}

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "ap-south-1a"
  map_public_ip_on_launch = true

  tags = {
    Name    = "${var.project_name}-public-subnet"
    Project = var.project_name
    Tier    = "public"
  }
}

resource "aws_subnet" "public_b" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.3.0/24"
  availability_zone       = "ap-south-1b"
  map_public_ip_on_launch = true

  tags = {
    Name    = "${var.project_name}-public-subnet-b"
    Project = var.project_name
    Tier    = "public"
  }
}

resource "aws_subnet" "private" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = "ap-south-1a"

  tags = {
    Name    = "${var.project_name}-private-subnet"
    Project = var.project_name
    Tier    = "private"
  }
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name    = "${var.project_name}-igw"
    Project = var.project_name
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name    = "${var.project_name}-public-route-table"
    Project = var.project_name
  }
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "public_b" {
  subnet_id      = aws_subnet.public_b.id
  route_table_id = aws_route_table.public.id
}

resource "aws_security_group" "web" {
  name        = "${var.project_name}-web-sg"
  description = "Security group for web server"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "HTTP from ALB"
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  ingress {
    description = "SSH from admin IP"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["14.194.135.206/32"]
  }

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name    = "${var.project_name}-web-sg"
    Project = var.project_name
  }
}

resource "aws_security_group" "alb" {
  name        = "${var.project_name}-alb-sg"
  description = "Security group for application load balancer"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "HTTP from internet"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name    = "${var.project_name}-alb-sg"
    Project = var.project_name
  }
}

resource "aws_lb" "app" {
  name               = "${var.project_name}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]

  subnets = [
    aws_subnet.public.id,
    aws_subnet.public_b.id
  ]

  tags = {
    Name    = "${var.project_name}-alb"
    Project = var.project_name
  }
}

resource "aws_lb_target_group" "app" {
  name     = "${var.project_name}-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.main.id

  health_check {
    enabled             = true
    path                = "/"
    protocol            = "HTTP"
    port                = "80"
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 5
    interval            = 30
  }

  tags = {
    Name    = "${var.project_name}-target-group"
    Project = var.project_name
  }
}

resource "aws_lb_listener" "app" {
  load_balancer_arn = aws_lb.app.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }
}

data "aws_ami" "ubuntu" {
  most_recent = true

  owners = ["099720109477"]

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }
}

resource "aws_instance" "web" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = "t3.micro"
  subnet_id                   = aws_subnet.public.id
  vpc_security_group_ids      = [aws_security_group.web.id]
  associate_public_ip_address = true
  key_name                    = "devops-key"

  root_block_device {
    volume_size = 8
    volume_type = "gp3"
  }

  tags = {
    Name    = "${var.project_name}-web-server"
    Project = var.project_name
  }
}

resource "aws_lb_target_group_attachment" "web_1" {
  target_group_arn = aws_lb_target_group.app.arn
  target_id        = aws_instance.web.id
  port             = 80
}

resource "aws_instance" "web_2" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = "t3.micro"
  subnet_id                   = aws_subnet.public_b.id
  vpc_security_group_ids      = [aws_security_group.web.id]
  associate_public_ip_address = true
  key_name                    = "devops-key"

  root_block_device {
    volume_size = 8
    volume_type = "gp3"
  }

  tags = {
    Name    = "${var.project_name}-web-server-2"
    Project = var.project_name
  }
}

resource "aws_lb_target_group_attachment" "web_2" {
  target_group_arn = aws_lb_target_group.app.arn
  target_id        = aws_instance.web_2.id
  port             = 80
}

resource "aws_launch_template" "web" {
  name_prefix   = "${var.project_name}-web-"
  image_id      = data.aws_ami.ubuntu.id
  instance_type = "t3.micro"
  key_name      = "devops-key"

  vpc_security_group_ids = [aws_security_group.web.id]

  user_data = base64encode(<<-EOF
    #!/bin/bash

    apt-get update
    apt-get install -y docker.io

    systemctl enable --now docker

    usermod -aG docker ubuntu

    mkdir -p /home/ubuntu/app

    cat > /home/ubuntu/app/index.html <<'HTML'
    <!DOCTYPE html>
    <html>
    <head>
      <meta charset="UTF-8">
      <title>Production Infrastructure</title>
    </head>
    <body>
      <h1>Production Infrastructure</h1>
      <p>Auto Scaling Instance</p>
    </body>
    </html>
    HTML

    cat > /home/ubuntu/app/Dockerfile <<'DOCKERFILE'
    FROM nginx:alpine
    COPY index.html /usr/share/nginx/html/index.html
    EXPOSE 80
    DOCKERFILE

    docker build -t production-infrastructure:latest /home/ubuntu/app
    docker run -d -p 80:80 --name production-app production-infrastructure:latest
  EOF
  )

  tag_specifications {
    resource_type = "instance"

    tags = {
      Name    = "${var.project_name}-asg-instance"
      Project = var.project_name
    }
  }
}

resource "aws_autoscaling_group" "web" {
  name              = "${var.project_name}-asg"
  min_size          = 2
  desired_capacity  = 2
  max_size          = 4
  health_check_type = "ELB"
  vpc_zone_identifier = [
    aws_subnet.public.id,
    aws_subnet.public_b.id
  ]

  launch_template {
    id      = aws_launch_template.web.id
    version = "$Latest"
  }

  target_group_arns = [
    aws_lb_target_group.app.arn
  ]

  tag {
    key                 = "Name"
    value               = "${var.project_name}-asg-instance"
    propagate_at_launch = true
  }

  tag {
    key                 = "Project"
    value               = var.project_name
    propagate_at_launch = true
  }
}

resource "aws_autoscaling_policy" "cpu_target_tracking" {
  name                   = "${var.project_name}-cpu-target-tracking"
  autoscaling_group_name = aws_autoscaling_group.web.name
  policy_type            = "TargetTrackingScaling"

  target_tracking_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ASGAverageCPUUtilization"
    }

    target_value = 60.0
  }
}

resource "aws_cloudwatch_metric_alarm" "high_cpu" {
  alarm_name          = "${var.project_name}-high-cpu"
  alarm_description   = "Alert when average ASG CPU utilization is high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 300
  statistic           = "Average"
  threshold           = 70
  treat_missing_data  = "notBreaching"

  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.web.name
  }
}

resource "aws_cloudwatch_metric_alarm" "low_cpu" {
  alarm_name          = "${var.project_name}-low-cpu"
  alarm_description   = "Alert when average ASG CPU utilization is low"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 300
  statistic           = "Average"
  threshold           = 20
  treat_missing_data  = "notBreaching"

  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.web.name
  }
}