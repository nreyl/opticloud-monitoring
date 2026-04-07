# ***************** Universidad de los Andes ***********************
# ****** Departamento de Ingeniería de Sistemas y Computación ******
# ********** Arquitectura y diseño de Software - ISIS2503 **********
#
# Infraestructura para Sprint 3 - OptiCloud Monitoring
#
# ASR-1 Escalabilidad : 12.000 usuarios concurrentes en ventanas de 10 min
# ASR-2 Latencia      : Consultas de reportes <= 100ms con 5.000 usuarios
#
# Elementos a desplegar en AWS:
# 1. Grupos de seguridad:
#    - opticloud-traffic-ssh   (puerto 22)
#    - opticloud-traffic-http  (puerto 8080)
#    - opticloud-traffic-db    (puerto 5432)
#    - opticloud-traffic-lb    (puerto 80)
#    - opticloud-traffic-rabbit (puertos 5672, 15672)
#
# 2. Instancias EC2:
#    - opticloud-bd-server     (PostgreSQL instalado y configurado)
#    - opticloud-rabbitmq      (RabbitMQ instalado y configurado)
#    - opticloud-web-server-a  (Django + report_worker)
#    - opticloud-web-server-b  (Django + report_worker)
#    - opticloud-web-server-c  (Django + report_worker)
#
# 3. Application Load Balancer:
#    - opticloud-alb           (HTTP:80 -> web servers HTTP:8080)
# ******************************************************************

# Variable. Define la región de AWS donde se desplegará la infraestructura.
variable "region" {
  description = "AWS region for deployment"
  type        = string
  default     = "us-east-1"
}

# Variable. Define el prefijo usado para nombrar los recursos en AWS.
variable "project_prefix" {
  description = "Prefix used for naming AWS resources"
  type        = string
  default     = "opticloud"
}

# Variable. Define el tipo de instancia EC2.
variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t3.micro"
}

# Variable. URL del repositorio del proyecto.
variable "repository" {
  description = "GitHub repository URL"
  type        = string
  default     = "https://github.com/nreyl/opticloud-monitoring.git"
}

# Proveedor. Define el proveedor de infraestructura (AWS) y la región.
provider "aws" {
  region = var.region
}

# Variables locales usadas en la configuración de Terraform.
locals {
  project_name = "${var.project_prefix}-monitoring"
  branch       = "Load-Balancer"

  common_tags = {
    Project   = local.project_name
    ManagedBy = "Terraform"
  }
}

# Data Source. Busca la AMI más reciente de Ubuntu 24.04.
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"]

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# ──────────────────────────────────────────────
# SECURITY GROUPS
# ──────────────────────────────────────────────

# SG: SSH (puerto 22)
resource "aws_security_group" "traffic_ssh" {
  name        = "${var.project_prefix}-traffic-ssh"
  description = "Allow SSH access"

  ingress {
    description = "SSH desde cualquier lugar"
    from_port   = 22
    to_port     = 22
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

  tags = merge(local.common_tags, { Name = "${var.project_prefix}-traffic-ssh" })
}

# SG: HTTP para web servers (puerto 8080)
resource "aws_security_group" "traffic_http" {
  name        = "${var.project_prefix}-traffic-http"
  description = "Allow HTTP traffic on port 8080"

  ingress {
    description = "HTTP acceso a la aplicación Django"
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, { Name = "${var.project_prefix}-traffic-http" })
}

# SG: Load Balancer (puerto 80)
resource "aws_security_group" "traffic_lb" {
  name        = "${var.project_prefix}-traffic-lb"
  description = "Allow HTTP traffic on port 80 for ALB"

  ingress {
    description = "HTTP desde Internet al ALB"
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

  tags = merge(local.common_tags, { Name = "${var.project_prefix}-traffic-lb" })
}

# SG: Base de datos PostgreSQL (puerto 5432)
resource "aws_security_group" "traffic_db" {
  name        = "${var.project_prefix}-traffic-db"
  description = "Allow PostgreSQL access on port 5432"

  ingress {
    description = "PostgreSQL desde cualquier lugar dentro de la VPC"
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, { Name = "${var.project_prefix}-traffic-db" })
}

# SG: RabbitMQ (puertos 5672 y 15672)
resource "aws_security_group" "traffic_rabbit" {
  name        = "${var.project_prefix}-traffic-rabbit"
  description = "Allow RabbitMQ traffic on ports 5672 and 15672"

  ingress {
    description = "AMQP para mensajería RabbitMQ"
    from_port   = 5672
    to_port     = 5672
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "RabbitMQ Management UI"
    from_port   = 15672
    to_port     = 15672
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, { Name = "${var.project_prefix}-traffic-rabbit" })
}

# ──────────────────────────────────────────────
# BD-SERVER (PostgreSQL)
# ──────────────────────────────────────────────

# Recurso. Instancia EC2 para la base de datos PostgreSQL.
# El script de inicio instala PostgreSQL, crea el usuario y la base de datos,
# y configura el acceso remoto desde la VPC.
resource "aws_instance" "bd_server" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = var.instance_type
  associate_public_ip_address = true
  vpc_security_group_ids      = [aws_security_group.traffic_db.id, aws_security_group.traffic_ssh.id]

  user_data = <<-EOT
              #!/bin/bash

              sudo apt-get update -y
              sudo apt-get install -y postgresql postgresql-contrib

              sudo -u postgres psql -c "CREATE USER monitoring_user WITH PASSWORD 'isis2503';"
              sudo -u postgres createdb -O monitoring_user monitoring_db
              sudo -u postgres psql -d monitoring_db -c "GRANT ALL ON SCHEMA public TO monitoring_user;"
              sudo -u postgres psql -d monitoring_db -c "ALTER SCHEMA public OWNER TO monitoring_user;"
              echo "host all all 0.0.0.0/0 md5" | sudo tee -a /etc/postgresql/16/main/pg_hba.conf
              echo "listen_addresses='*'" | sudo tee -a /etc/postgresql/16/main/postgresql.conf
              sudo systemctl restart postgresql
              EOT

  tags = merge(local.common_tags, {
    Name = "${var.project_prefix}-bd-server"
    Role = "database"
  })
}

# ──────────────────────────────────────────────
# RABBITMQ-SERVER
# ──────────────────────────────────────────────

# Recurso. Instancia EC2 para RabbitMQ.
# El script de inicio instala RabbitMQ, habilita el plugin de gestión
# y crea el usuario monitoring_user.
resource "aws_instance" "rabbitmq_server" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = var.instance_type
  associate_public_ip_address = true
  vpc_security_group_ids      = [aws_security_group.traffic_rabbit.id, aws_security_group.traffic_ssh.id]

  user_data = <<-EOT
              #!/bin/bash

              sudo apt-get update -y
              sudo apt-get install -y rabbitmq-server

              sudo systemctl enable rabbitmq-server
              sudo systemctl start rabbitmq-server

              sudo rabbitmq-plugins enable rabbitmq_management

              sudo rabbitmqctl add_user monitoring_user isis2503
              sudo rabbitmqctl set_permissions -p / monitoring_user ".*" ".*" ".*"
              sudo rabbitmqctl set_user_tags monitoring_user administrator

              sudo systemctl restart rabbitmq-server
              EOT

  tags = merge(local.common_tags, {
    Name = "${var.project_prefix}-rabbitmq-server"
    Role = "message-broker"
  })
}

# ──────────────────────────────────────────────
# WEB SERVERS (Django + report_worker)
# ──────────────────────────────────────────────

# Recurso. Define las 3 instancias EC2 para los web servers Django.
# Cada instancia clona el repositorio, instala dependencias,
# y arranca el servidor Django y el report_worker en background.
resource "aws_instance" "web_server" {
  for_each = toset(["a", "b", "c"])

  ami                         = data.aws_ami.ubuntu.id
  instance_type               = var.instance_type
  associate_public_ip_address = true
  vpc_security_group_ids      = [aws_security_group.traffic_http.id, aws_security_group.traffic_ssh.id]

  user_data = <<-EOT
              #!/bin/bash

              export DB_HOST=${aws_instance.bd_server.private_ip}
              export RABBITMQ_HOST=${aws_instance.rabbitmq_server.private_ip}

              sudo apt-get update -y
              sudo apt-get install -y python3-pip python3-venv git

              mkdir -p /labs
              cd /labs

              git clone ${var.repository}
              cd opticloud-monitoring
              git checkout ${local.branch}

              python3 -m venv venv
              source venv/bin/activate
              pip install -r requirements.txt

              sed -i "s/'name_db'/'monitoring_db'/" monitoring/settings.py
              sed -i "s/'user_db'/'monitoring_user'/" monitoring/settings.py
              sed -i "s/'user_password'/'isis2503'/" monitoring/settings.py

              nohup python3 manage.py runserver 0.0.0.0:8080 > /labs/django.log 2>&1 &

              RABBITMQ_HOST=$RABBITMQ_HOST RABBITMQ_USER=monitoring_user RABBITMQ_PASSWORD=isis2503 \
              nohup python3 report_worker.py > /labs/worker.log 2>&1 &
              EOT

  tags = merge(local.common_tags, {
    Name = "${var.project_prefix}-web-server-${each.key}"
    Role = "web-server"
  })

  depends_on = [aws_instance.bd_server, aws_instance.rabbitmq_server]
}

# ──────────────────────────────────────────────
# APPLICATION LOAD BALANCER
# ──────────────────────────────────────────────

# Data Source. Obtiene la VPC por defecto.
data "aws_vpc" "default" {
  default = true
}

# Data Source. Obtiene todas las subnets de la VPC por defecto.
data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

# Recurso. Application Load Balancer.
resource "aws_lb" "opticloud_alb" {
  name               = "${var.project_prefix}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.traffic_lb.id]
  subnets            = data.aws_subnets.default.ids

  tags = merge(local.common_tags, { Name = "${var.project_prefix}-alb" })
}

# Recurso. Target Group para los web servers.
resource "aws_lb_target_group" "web_tg" {
  name     = "${var.project_prefix}-web-tg"
  port     = 8080
  protocol = "HTTP"
  vpc_id   = data.aws_vpc.default.id

  health_check {
    path                = "/health/"
    port                = "8080"
    protocol            = "HTTP"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
    matcher             = "200"
  }

  tags = merge(local.common_tags, { Name = "${var.project_prefix}-web-tg" })
}

# Recurso. Listener del ALB en puerto 80.
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.opticloud_alb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.web_tg.arn
  }
}

# Recurso. Registra los 3 web servers en el target group.
resource "aws_lb_target_group_attachment" "web_servers" {
  for_each = aws_instance.web_server

  target_group_arn = aws_lb_target_group.web_tg.arn
  target_id        = each.value.id
  port             = 8080
}

# ──────────────────────────────────────────────
# OUTPUTS
# ──────────────────────────────────────────────

output "alb_dns_name" {
  description = "DNS del ALB - usar en JMeter como host destino"
  value       = aws_lb.opticloud_alb.dns_name
}

output "bd_server_private_ip" {
  description = "IP privada del bd-server (PostgreSQL)"
  value       = aws_instance.bd_server.private_ip
}

output "rabbitmq_private_ip" {
  description = "IP privada del rabbitmq-server"
  value       = aws_instance.rabbitmq_server.private_ip
}

output "web_servers_public_ips" {
  description = "IPs públicas de los web servers"
  value       = { for k, v in aws_instance.web_server : k => v.public_ip }
}
