variable "ecs_service_name" {
  description = "Name of the ecs_service_name"
}
variable "ecs_cluster" {
  description = "Name of the ecs_cluster"
}
variable "prod_subnet_ids" {
  description = "Name of the ecs_cluster"
}
variable "task_host_header_domain" {
  description = "Name of task_host_header_domain"
}
variable "env_name" {
  description = "Name of env_name"
}

locals {
  subnet_ids = var.env_name == "prod" ? 'subnet-0ee4f9325bf6b6e00' : 'subnet-0ef8b2338c6558f58'
}
locals {
  vpc_id = var.env_name == "prod" ? 'vpc-065652c243d05599f' : 'vpc-00b2f03fc8424e62c'
}

resource "aws_ecs_service" "task_service" {
  name            = var.ecs_service_name
  cluster         = var.ecs_cluster
  task_definition = aws_ecs_task_definition.ab_task.arn
  launch_type     = "FARGATE"
  desired_count   = 1

  network_configuration {

    subnets          = [local.subnet_ids]
    security_groups  = [aws_security_group.ecs_sec_group.id]
    assign_public_ip = false
  }
  #iam_role        = local.ecsTaskExecutionRole_arn
  depends_on = [local.ecsTaskExecutionRole_name]


  load_balancer {
    target_group_arn =  aws_lb_target_group.example_tg.arn
    container_name   = var.ecs_service_name
    container_port   = 80
  }

  lifecycle {
    ignore_changes = [desired_count]
  }

}
resource "aws_lb_target_group" "example_tg" {
  name     = "var.ecs_service_name"
  port     = 443
  protocol = "HTTPS"
  vpc_id   = local.vpc_id
}

resource "aws_lb_listener_rule" "example_listener_rule" {
  listener_arn = "arn:aws:elasticloadbalancing:us-west-2:670015515275:listener/app/Non-Production/b0146169d825fc87/2bbb8a1721a1a531"
  priority     = 100

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.example_tg.arn
  }   
condition {
        host_header {
            values = ["${var.task_host_header_domain}"]
        }
}
}
resource "aws_security_group" "ecs_sec_group" {
  name        = var.sec_group_name
  description = "Allow http inbound traffic from ALB"

  vpc_id = local.vpc_id
  ingress {
    description     = "TLS from VPC"
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [local.vpc_id]

    #cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }


}

resource "aws_ecs_task_definition" "ab_task" {
  cpu                      = 1024
  memory                   = 2048
  family                   = ecs_service_name
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  execution_role_arn       = local.ecsTaskExecutionRole_arn
 
  container_definitions = jsonencode([
    {

      name         = var.ecs_service_name
      image        = "${aws_ecr_repository.ecr-repo.repository_url}:latest"
      cpu          = 512
      memory       = 1024
      essential    = true
      portMappings = [{
                        containerPort = 80
                        hostPort      = 80
                        }]
        logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = "aws_cloudwatch_log_group.ab_log_group.name"
          awslogs-region        = "us-west-2"
          awslogs-stream-prefix = "ecs"
        }
      }
    }
  ])
}

resource "aws_ecr_repository" "ecr-repo" {
  name                 = '${var.ecs_service_name}-repo'
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }
}

resource "aws_ecr_lifecycle_policy" "ecr-repo-policy" {
  repository = aws_ecr_repository.ecr-repo.name

  policy = <<EOF
{
    "rules": [
        {
            "rulePriority": 1,
            "description": "Keep last 30 images",
            "selection": {
                "tagStatus": "tagged",
                "tagPrefixList": ["latest"],
                "countType": "imageCountMoreThan",
                "countNumber": "20"
            },
            "action": {
                "type": "expire"
            }
        },
        {
            "rulePriority": 2,
            "description": "Expire untagged images older than 14 days",
            "selection": {
                "tagStatus": "untagged",
                "countType": "sinceImagePushed",
                "countUnit": "days",
                "countNumber": "14"
            },
            "action": {
                "type": "expire"
            }
        }
    ]
    }
EOF
}
