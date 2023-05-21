provider "aws" {
  region     = "us-east-2"
#  access_key = var.access_key
#  secret_key = var.secret_key
}

data "aws_availability_zones" "AZ" {}

output "az" {
  value = data.aws_availability_zones.AZ.names
}

resource "aws_vpc" "MyVPC" {
  cidr_block = "10.0.0.0/16"
  tags = {
    Name = "Devops_VPC"
  }
}

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.MyVPC.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = data.aws_availability_zones.AZ.names[0]
  map_public_ip_on_launch = true
  tags = {
    Name = "Public1"
  }
}

resource "aws_subnet" "public2" {
  vpc_id                  = aws_vpc.MyVPC.id
  cidr_block              = "10.0.2.0/24"
  availability_zone       = data.aws_availability_zones.AZ.names[2]
  map_public_ip_on_launch = true
  tags = {
    Name = "Public2"
  }
}

resource "aws_subnet" "private" {
  vpc_id            = aws_vpc.MyVPC.id
  cidr_block        = "10.0.3.0/24"
  availability_zone = data.aws_availability_zones.AZ.names[1]
}

resource "aws_subnet" "private2" {
  vpc_id            = aws_vpc.MyVPC.id
  cidr_block        = "10.0.4.0/24"
  availability_zone = data.aws_availability_zones.AZ.names[2]
}

resource "aws_internet_gateway" "IGW" {
  vpc_id = aws_vpc.MyVPC.id
}

resource "aws_route_table" "main" {
  vpc_id = aws_vpc.MyVPC.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.IGW.id
  }
  tags = {
    Name = "DevOps_main"
  }
}

resource "aws_route_table_association" "M" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.main.id
}

resource "aws_route_table_association" "M1" {
  subnet_id      = aws_subnet.public2.id
  route_table_id = aws_route_table.main.id
}

resource "aws_eip" "elasticIP" {
  vpc        = true
  depends_on = [aws_internet_gateway.IGW]
}

resource "aws_nat_gateway" "NGW" {
  depends_on    = [aws_subnet.public]
  subnet_id     = aws_subnet.public.id
  allocation_id = aws_eip.elasticIP.id
  tags = {
    Name = "NatGW"
  }
}

resource "aws_ecs_cluster" "Cluster" {
  name = "terraform_cluster"
}

data "aws_ecr_image" "service_image" {
  repository_name = "myapp"
  image_tag       = "latest"
}

# output "ec" {
#     value = data.aws_ecr_image.service_image.
# }

# resource "aws_ecs_task_definition" "ecstask" {
#   family                   = "sevice"
#   network_mode             = "awsvpc"
#   requires_compatibilities = ["FARGATE"]
#   container_definitions = jsonencode([{
#     name      = "HelloWorld"
#     image     = "545758899836.dkr.ecr.us-east-2.amazonaws.com/myapp:latest"
#     cpu       = 10
#     memory    = 512
#     essential = true
#     portMappings = [
#       {
#         containerPort = 80
#         hostPort      = 80
#       }
#     ]
#   }])
# }


resource "aws_ecs_task_definition" "example" {
  family                   = "service"
  execution_role_arn       = "arn:aws:iam::545758899836:role/ecsTaskExecutionRole"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "1024"
  memory                   = "2048"

  container_definitions = <<DEFINITION
    [
      {
        "name": "HelloWorld",
        "image": "545758899836.dkr.ecr.us-east-2.amazonaws.com/myapp:latest",
        "cpu": 256,
        "memory": 512,
        "essential": true,
             "portMappings": [
        {
          "containerPort": 80,
          "hostPort": 80
        }
      ]
      }
    ]
  DEFINITION
}


resource "aws_security_group" "ecsSG" {
  name   = "ECS_SG"
  vpc_id = aws_vpc.MyVPC.id
  ingress {
    from_port   = "8080"
    to_port     = "8080"
    cidr_blocks = ["0.0.0.0/0"]
    protocol    = "tcp"
  }
  ingress {
    from_port   = "80"
    to_port     = "80"
    cidr_blocks = ["0.0.0.0/0"]
    protocol    = "tcp"
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "Lb-SG" {
  name   = "LoadBalancerSecurityGRP"
  vpc_id = aws_vpc.MyVPC.id
  ingress {
    from_port   = "80"
    to_port     = "80"
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "traffic from internet to LB"
  }

  egress {
    from_port   = "0"
    to_port     = "0"
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_ecs_service" "Service" {
  name                 = "terraform_service"
  cluster              = aws_ecs_cluster.Cluster.id
  task_definition      = aws_ecs_task_definition.example.family
  launch_type          = "FARGATE"
  desired_count        = 1
  force_new_deployment = true
  network_configuration {
    subnets          = ["${aws_subnet.public.id}"]
    assign_public_ip = true
    security_groups  = ["${aws_security_group.ecsSG.id}"]
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.TG.arn
    container_name   = "HelloWorld"
    container_port   = 80
  }
}

resource "aws_lb" "ALB" {
  name               = "ALB"
  load_balancer_type = "application"
  subnets            = [aws_subnet.public.id, aws_subnet.public2.id]
  security_groups    = [aws_security_group.Lb-SG.id]

  tags = {
    Name = "Terraform_ALB"
  }
}

resource "aws_lb_target_group" "TG" {
  name        = "TG"
  port        = 80
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = aws_vpc.MyVPC.id

  health_check {
    path              = "/"
    interval          = 30
    timeout           = 10
    healthy_threshold = 3
    matcher           = 200
  }

}

resource "aws_lb_listener" "example" {
  load_balancer_arn = aws_lb.ALB.arn
  port              = 80
  protocol          = "HTTP"
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.TG.arn
  }
}
