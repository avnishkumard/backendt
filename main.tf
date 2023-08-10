provider "aws" {
  region = "us-west-2"  # Replace with your desired AWS region
}
variable "ecs_service_name" {
  description = "Name of the ecs_service_name"
}
variable "ecs_cluster" {
  description = "Name of the ecs_cluster"
}
variable "task_host_header_domain" {
  description = "Name of task_host_header_domain"
}
variable "env_name" {
  description = "Name of env_name"
}
locals {
service_name = "${var.ecs_cluster$}-{var.ecs_service_name}-ecs-service"
}
locals {
  subnet_ids = var.env_name == "prod" ? "subnet-0ee4f9325bf6b6e00" : "subnet-0ef8b2338c6558f58"
}
locals {
  vpc_id = var.env_name == "prod" ? "vpc-065652c243d05599f" : "vpc-00b2f03fc8424e62c"
}
locals {
  lb_arn = var.env_name == "prod" ? "Production-1288100872.us-west-2.elb.amazonaws.com" : "Non-Production-1546516192.us-west-2.elb.amazonaws.com"
}
locals {
  listener_arn = var.env_name == "prod" ? "arn:aws:elasticloadbalancing:us-west-2:670015515275:loadbalancer/app/Production/609f806d98f51888" : "arn:aws:elasticloadbalancing:us-west-2:670015515275:listener/app/Non-Production/b0146169d825fc87/2bbb8a1721a1a531"
}
locals {
  sg_grp = var.env_name == "prod" ? "sg-026b709c6b20648f7" : "sg-06b4f64530a19cea1"
}
resource "aws_ecs_service" "task_service" {
  name            = local.service_name
  cluster         = var.ecs_cluster
  task_definition = aws_ecs_task_definition.ab_task.arn
  launch_type     = "FARGATE"
  desired_count   = 1

  network_configuration {
    subnets          = [local.subnet_ids]
    security_groups  = [aws_security_group.ecs_sec_group.id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.example_tg.arn
    container_name   = local.service_name
    container_port   = 80
  }

  lifecycle {
    ignore_changes = [desired_count]
  }
}

resource "aws_lb_target_group" "example_tg" {
  name     = local.service_name
  port     = 80
  protocol = "HTTP"
  vpc_id   = local.vpc_id

  target_type = "ip"  # Set the target type to "ip" for Fargate launch type
}

resource "aws_lb_listener_rule" "example_listener_rule" {
  listener_arn = local.listener_arn

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.example_tg.arn
  }

  condition {
    host_header {
      values = ["${var.task_host_header_domain}.centrae.com"]
    }
  }
}

resource "aws_security_group" "ecs_sec_group" {
  name        = local.service_name
  description = "Allow http inbound traffic from ALB"

  vpc_id = local.vpc_id
  ingress {
    description     = "TLS from VPC"
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [local.sg_grp]
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
  family                   = local.service_name
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  execution_role_arn       = "arn:aws:iam::670015515275:role/ecsTaskstagingRole"
 
  container_definitions = jsonencode([
    {

      name         = local.service_name
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
        command =["/bin/sh","-c","ls -lah && php artisan vendor:publish --all && php artisan key:generate && php artisan jwt:secret && php artisan migrate && apache2-foreground"]
    }
  ])
}

resource "aws_ecr_repository" "ecr-repo" {
  name                 = "${local.service_name}-repo"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }
}


resource "aws_ecr_lifecycle_policy" "ecr-repo-policy" {
  repository = aws_ecr_repository.ecr-repo.name

  policy = jsonencode({
    rules = [
      {
        rulePriority: 1,
        description: "Keep last 30 images",
        selection: {
          tagStatus: "tagged",
          tagPrefixList: ["latest"],
          countType: "imageCountMoreThan",
          countNumber: 20,
        },
        action: {
          type: "expire",
        },
      },
      {
        rulePriority: 2,
        description: "Expire untagged images older than 14 days",
        selection: {
          tagStatus: "untagged",
          countType: "sinceImagePushed",
          countUnit: "days",
          countNumber: 14,
        },
        action: {
          type: "expire",
        },
      },
    ],
  })
}
resource "aws_route53_record" "loadbalancer_cname" {
  zone_id = "Z0919146131B5POBHJLN9"
  name    = var.task_host_header_domain
  type    = "CNAME"
  ttl     = "300"
  records = [local.lb_arn]
}
