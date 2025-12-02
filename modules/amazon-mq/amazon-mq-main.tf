# Copyright (c) 2025 Hammerspace, Inc
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.
# -----------------------------------------------------------------------------
# main.tf
#
# This file creates and maintains all of the assets for MSK (Kafka) on AWS for
# Project Houston.
# -----------------------------------------------------------------------------

# Run 'terraform init', 'terraform plan', 'terraform apply' to use.

# Needed to fetch the current AWS account details

data "aws_caller_identity" "current" {}

# Load the customer site configs (if they exist)

locals {
  site_configs_dir = "${path.module}/site-configs"

  site_configs = {
    for file in fileset(local.site_configs_dir, "*.json") :
      trimsuffix(file, ".json") => jsondecode(file("${local.site_configs_dir}/${file}"))
  }

  central_amqps_endpoint = aws_mq_broker.rabbitmq.instances[0].endpoints[0]
  central_amqps_host     = replace(local.central_amqps_endpoint, "amqps://", "")
}
      
# VPC

resource "aws_vpc" "main" {
  cidr_block              = var.vpc_cidr
  enable_dns_support      = true
  enable_dns_hostnames    = true

  tags = merge(var.tags, { Name = "${var.project_name}-vpc" })
}

# Subnet 1

resource "aws_subnet" "private_a" {
  vpc_id                 = aws_vpc.main.id
  cidr_block             = var.private_subnet_a_cidr
  availability_zone      = var.subnet_a_az
  map_public_ip_on_launch= false
  tags                   = merge(var.tags, { Name = "${var.project_name}-private-a" })
}

# Subnet 2

resource "aws_subnet" "private_b" {
  vpc_id                 = aws_vpc.main.id
  cidr_block             = var.private_subnet_b_cidr
  availability_zone      = var.subnet_b_az
  map_public_ip_on_launch= false
  tags                   = merge(var.tags, { Name = "${var.project_name}-private-b" })
}

resource "aws_subnet" "public_a" {
  vpc_id                 = aws_vpc.main.id
  cidr_block             = var.public_subnet_a_cidr
  availability_zone      = var.subnet_a_az
  map_public_ip_on_launch= true
  tags                   = merge(var.tags, { Name = "${var.project_name}-public-a" })
}

resource "aws_subnet" "public_b" {
  vpc_id                 = aws_vpc.main.id
  cidr_block             = var.public_subnet_b_cidr
  availability_zone      = var.subnet_b_az
  map_public_ip_on_launch= true
  tags                   = merge(var.tags, { Name = "${var.project_name}-public-b" })
}

# Security Group for Amazon MQ RabbitMQ Broker

resource "aws_security_group" "rabbitmq_sg" {
  name        = "${var.project_name}-rabbitmq-sg"
  description = "Security group for Amazon MQ RabbitMQ broker"
  vpc_id      = aws_vpc.main.id

  # Ingress: AMQP over TLS (5671). For now open to all; tighten to site IPs/VPN later.
  ingress {
    from_port   = 5671
    to_port     = 5671
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Outbound: allow all egress
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, { Name = "${var.project_name}-rabbitmq-sg" })
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id
  tags   = merge(var.tags, { Name = "${var.project_name}-igw" })
}

resource "aws_route_table" "public_a" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }
  tags = merge(var.tags, { Name = "${var.project_name}-rt-public-a" })
}

resource "aws_route_table_association" "public_a_assoc" {
  subnet_id      = aws_subnet.public_a.id
  route_table_id = aws_route_table.public_a.id
}

resource "aws_route_table" "public_b" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }
  tags = merge(var.tags, { Name = "${var.project_name}-rt-public-b" })
}

resource "aws_route_table_association" "public_b_assoc" {
  subnet_id      = aws_subnet.public_b.id
  route_table_id = aws_route_table.public_b.id
}

resource "aws_eip" "nat_a" {
  domain = "vpc"
  tags   = merge(var.tags, { Name = "${var.project_name}-eip-nat-a" })
}

resource "aws_eip" "nat_b" {
  domain = "vpc"
  tags   = merge(var.tags, { Name = "${var.project_name}-eip-nat-b" })
}

resource "aws_nat_gateway" "a" {
  allocation_id = aws_eip.nat_a.id
  subnet_id     = aws_subnet.public_a.id
  depends_on    = [aws_internet_gateway.main]
  tags          = merge(var.tags, { Name = "${var.project_name}-natgw-a" })
}

resource "aws_nat_gateway" "b" {
  allocation_id = aws_eip.nat_b.id
  subnet_id     = aws_subnet.public_b.id
  depends_on    = [aws_internet_gateway.main]
  tags          = merge(var.tags, { Name = "${var.project_name}-natgw-b" })
}

resource "aws_route_table" "private_a" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.a.id
  }
  tags = merge(var.tags, { Name = "${var.project_name}-rt-private-a" })
}

resource "aws_route_table_association" "private_a_assoc" {
  subnet_id      = aws_subnet.private_a.id
  route_table_id = aws_route_table.private_a.id
}

resource "aws_route_table" "private_b" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.b.id
  }
  tags = merge(var.tags, { Name = "${var.project_name}-rt-private-b" })
}

resource "aws_route_table_association" "private_b_assoc" {
  subnet_id      = aws_subnet.private_b.id
  route_table_id = aws_route_table.private_b.id
}

# Optional Route 53 Private Hosted Zone

resource "aws_route53_zone" "private" {
  name = var.hosted_zone_name
  vpc {
    vpc_id = aws_vpc.main.id
  }

  tags = merge(var.tags, { Name = "${var.project_name}-dns" })
}

# The following is for adding SSM Role Permissions so that any test instance
# can be created and we can talk to it with SSM. This is needed because all
# test instances would be on a private network and we don't have a way to ssh
# from outside of AWS due to a lack of VPN in anything but us-west-2.

# IAM Role for SSM (with AmazonSSMManagedInstanceCore for EC2 Session Manager access)

data "aws_iam_policy_document" "ssm_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ssm_role" {
  name               = "${var.project_name}-ssm-role"
  assume_role_policy = data.aws_iam_policy_document.ssm_assume_role.json

  tags = merge(var.tags, { Name = "${var.project_name}-ssm-role" })
}

resource "aws_iam_role_policy_attachment" "ssm_core" {
  role       = aws_iam_role.ssm_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# Instance Profile to attach to EC2 instances

resource "aws_iam_instance_profile" "ssm_profile" {
  name = "${var.project_name}-ssm-profile"
  role = aws_iam_role.ssm_role.name
}

resource "aws_instance" "test_ec2" {
  count = var.create_test_ec2 ? 1 : 0
  
  ami                  = "ami-0cae6d6fe6048ca2c" # AL2023 AMI for your region
  instance_type        = "t3.micro"
  subnet_id            = aws_subnet.private_a.id
  iam_instance_profile = aws_iam_instance_profile.ssm_profile.name

  tags = merge(var.tags, { Name = "${var.project_name}-test-ec2" })

  root_block_device {
    volume_size           = 50
    volume_type           = "gp2"
    delete_on_termination = true
  }
}

# Amazon MQ RabbitMQ Broker (central site)

resource "aws_mq_broker" "rabbitmq" {
  broker_name        = "${var.project_name}-rabbitmq"
  engine_type        = "RabbitMQ"
  engine_version     = var.rabbitmq_engine_version
  host_instance_type = var.rabbitmq_instance_type

  # Multi-AZ RabbitMQ cluster across your two private subnets
  deployment_mode            = "CLUSTER_MULTI_AZ"

  publicly_accessible        = true
  auto_minor_version_upgrade = true
  apply_immediately          = true

  logs {
    general = true
  }

  # Initial admin user for RabbitMQ management + shovels
  user {
    username       = var.rabbitmq_admin_username
    password       = var.rabbitmq_admin_password
    console_access = true
  }

  tags = merge(var.tags, { Name = "${var.project_name}-rabbitmq" })
}

# Build the definitions files for each site

resource "null_resource" "configure_rabbitmq_sites" {
  for_each = local.site_configs

  # Make it crystal clear: don't run until the broker exists
  depends_on = [aws_mq_broker.rabbitmq]
  
  # So Terraform reruns when config changes
  triggers = {
    config_hash = sha1(jsonencode(each.value))
  }

  provisioner "local-exec" {
    command = <<EOT
${path.module}/scripts/configure_rabbitmq.sh \
  --base-url ${aws_mq_broker.rabbitmq.instances[0].console_url} \
  --user ${var.rabbitmq_admin_username} \
  --password '${var.rabbitmq_admin_password}' \
  --config-b64 '${base64encode(jsonencode(each.value))}'
EOT
  }
}

# Generate the local site_definitions files

resource "local_file" "site_definitions" {
  for_each = local.site_configs

  filename = "${path.module}/dist/${each.key}-definitions.json"

  content = jsonencode({
    vhosts = [
      { name = "/" }
    ]

    users = [
      {
        name              = "admin"
        password_hash     = var.site_admin_password_hash
        hashing_algorithm = "rabbit_password_hashing_sha256"
        tags              = ["administrator"]
      }
    ]

    permissions = [
      {
        user      = "admin"
        vhost     = "/"
        configure = ".*"
        write     = ".*"
        read      = ".*"
      }
    ]

    # exchanges/queues/bindings from per-site config
    exchanges = [
      for name, cfg in each.value :
      {
        name        = cfg.exchange
        vhost       = "/"
        type        = "topic"
        durable     = true
        auto_delete = false
        internal    = false
        arguments   = {}
      } if name != "vhost"
    ]

    queues = [
      for name, cfg in each.value :
      {
        name        = cfg.queue
        vhost       = "/"
        durable     = true
        auto_delete = false
        arguments   = {}
      } if name != "vhost"
    ]

    bindings = [
      for name, cfg in each.value :
      {
        source           = cfg.exchange
        vhost            = "/"
        destination      = cfg.queue
        destination_type = "queue"
        routing_key      = cfg.routing_key
        arguments        = {}
      } if name != "vhost"
    ]

    # Four shovels per site:
    #   telemetry_to_aws, events_to_aws, performance_to_aws  (remote -> central)
    #   commands_from_aws                                    (central -> remote)
    parameters = [
      {
        vhost     = "/"
        component = "shovel"
        name      = "telemetry_to_aws"
        value = {
          "src-uri"          = "amqp://${urlencode(var.site_admin_username)}:${urlencode(var.site_admin_password)}@localhost:5672/%2F"
          "src-queue"        = each.value.telemetry.queue

          "dest-uri"         = "amqps://${urlencode(var.rabbitmq_admin_username)}:${urlencode(var.rabbitmq_admin_password)}@${local.central_amqps_host}/${urlencode(each.value.vhost)}?verify=verify_none"
          "dest-exchange"    = each.value.telemetry.exchange
          "dest-exchange-key"= each.value.telemetry.routing_key

          "ack-mode"         = "on-confirm"
          "reconnect-delay"  = 5
        }
      },
      {
        vhost     = "/"
        component = "shovel"
        name      = "events_to_aws"
        value = {
          "src-uri"          = "amqp://${urlencode(var.site_admin_username)}:${urlencode(var.site_admin_password)}@localhost:5672/%2F"
          "src-queue"        = each.value.events.queue

          "dest-uri"         = "amqps://${urlencode(var.rabbitmq_admin_username)}:${urlencode(var.rabbitmq_admin_password)}@${local.central_amqps_host}/${urlencode(each.value.vhost)}?verify=verify_none"
          "dest-exchange"    = each.value.events.exchange
          "dest-exchange-key"= each.value.events.routing_key

          "ack-mode"         = "on-confirm"
          "reconnect-delay"  = 5
        }
      },
      {
        vhost     = "/"
        component = "shovel"
        name      = "performance_to_aws"
        value = {
          "src-uri"          = "amqp://${urlencode(var.site_admin_username)}:${urlencode(var.site_admin_password)}@localhost:5672/%2F"
          "src-queue"        = each.value.performance.queue

          "dest-uri"         = "amqps://${urlencode(var.rabbitmq_admin_username)}:${urlencode(var.rabbitmq_admin_password)}@${local.central_amqps_host}/${urlencode(each.value.vhost)}?verify=verify_none"
          "dest-exchange"    = each.value.performance.exchange
          "dest-exchange-key"= each.value.performance.routing_key

          "ack-mode"         = "on-confirm"
          "reconnect-delay"  = 5
        }
      },
      {
        vhost     = "/"
        component = "shovel"
        name      = "commands_from_aws"
        value = {
          # Source is the central AWS broker, commands exchange in the site's vhost
          "src-uri"          = "amqps://${urlencode(var.rabbitmq_admin_username)}:${urlencode(var.rabbitmq_admin_password)}@${local.central_amqps_host}/${urlencode(each.value.vhost)}?verify=verify_none"
          "src-exchange"     = each.value.commands.exchange
          "src-exchange-key" = each.value.commands.routing_key

          # Destination is the local site broker, commands.from-aws queue on /
          "dest-uri"         = "amqp://${urlencode(var.site_admin_username)}:${urlencode(var.site_admin_password)}@localhost:5672/%2F"
          "dest-queue"       = each.value.commands.queue

          "ack-mode"         = "on-confirm"
          "reconnect-delay"  = 5
        }
      }
    ]
  })
}

resource "null_resource" "pretty_print_definitions" {
  depends_on = [local_file.site_definitions]

  provisioner "local-exec" {
    working_dir = path.module
    command = <<EOT
for f in dist/*-definitions.json; do
  python3 -m json.tool "$${f}" > "$${f}.tmp" && mv "$${f}.tmp" "$${f}"
done
EOT
  }
}
