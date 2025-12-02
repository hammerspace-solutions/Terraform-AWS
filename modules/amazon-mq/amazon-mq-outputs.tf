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
# outputs.tf
#
# This file shows all of the needed state for MSK on AWS for Project Houston.
# -----------------------------------------------------------------------------

# outputs.tf - Optional outputs for key ARNs/IDs after apply

output "vpc_id" {
  value = aws_vpc.main.id
}

output "private_subnet_ids" {
  value = [aws_subnet.private_a.id, aws_subnet.private_b.id]
}

output "public_subnet_ids" {
  value = [aws_subnet.public_a.id, aws_subnet.public_b.id]
}

output "rabbitmq_broker_id" {
  description = "ID of the Amazon MQ RabbitMQ broker"
  value       = aws_mq_broker.rabbitmq.id
}

output "rabbitmq_broker_arn" {
  description = "ARN of the Amazon MQ RabbitMQ broker"
  value       = aws_mq_broker.rabbitmq.arn
}

output "rabbitmq_security_group_id" {
  description = "Security group ID attached to the RabbitMQ broker"
  value       = aws_security_group.rabbitmq_sg.id
}

# Primary AMQPS endpoint (what your shovels will use)
output "rabbitmq_amqps_endpoint" {
  description = "Primary AMQPS endpoint for the RabbitMQ broker"
  value       = aws_mq_broker.rabbitmq.instances[0].endpoints[0]
}

# (Optional) Web console URL if you want it
output "rabbitmq_console_url" {
  description = "RabbitMQ management console URL"
  value       = aws_mq_broker.rabbitmq.instances[0].console_url
}

output "hosted_zone_id" {
  value = aws_route53_zone.private.id
}

output "test_ec2_id" {
  value = length(aws_instance.test_ec2) > 0 ? aws_instance.test_ec2[0].id : null
}
