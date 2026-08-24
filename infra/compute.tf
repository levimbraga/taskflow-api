# ------------------------------------------------------------------------------
# Camada de computação: uma instância EC2 executando o contêiner publicado
# pelo pipeline de CI.
#
# IMPORTANTE (AWS Academy Learner Lab): a conta do laboratório não permite
# criar IAM roles. Por isso o perfil de instância NÃO é criado aqui - o código
# apenas referencia a "LabInstanceProfile", que já vem provisionada na conta e
# concede as permissões necessárias ao CloudWatch e ao S3.
# ------------------------------------------------------------------------------

data "aws_iam_instance_profile" "lab" {
  name = "LabInstanceProfile"
}

# AMI mais recente do Amazon Linux 2023, resolvida em tempo de plan para que a
# infraestrutura não fique presa a um ID de imagem que muda a cada região.
data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

resource "aws_cloudwatch_log_group" "app" {
  name              = "/${var.project_name}/${var.environment}/app"
  retention_in_days = var.log_retention_days
}

resource "aws_instance" "app" {
  ami                    = data.aws_ami.amazon_linux.id
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.public[0].id
  vpc_security_group_ids = [aws_security_group.app.id]
  iam_instance_profile   = data.aws_iam_instance_profile.lab.name
  key_name               = var.key_pair_name != "" ? var.key_pair_name : null

  user_data_replace_on_change = true
  user_data = templatefile("${path.module}/user_data.sh.tftpl", {
    container_image = var.container_image
    app_port        = var.app_port
    log_group       = aws_cloudwatch_log_group.app.name
    aws_region      = var.aws_region
  })

  root_block_device {
    volume_size           = 8
    volume_type           = "gp3"
    encrypted             = true
    delete_on_termination = true
  }

  metadata_options {
    http_tokens   = "required" # exige IMDSv2
    http_endpoint = "enabled"
  }

  tags = {
    Name = "${var.project_name}-app"
    Role = "api"
  }
}

resource "aws_eip" "app" {
  instance = aws_instance.app.id
  domain   = "vpc"

  tags = {
    Name = "${var.project_name}-eip"
  }

  depends_on = [aws_internet_gateway.main]
}
