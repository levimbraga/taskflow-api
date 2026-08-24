# ------------------------------------------------------------------------------
# Grupo de segurança da aplicação. As regras são declaradas como recursos
# separados (e não inline) para que o Terraform consiga alterá-las sem
# recriar o grupo inteiro.
# ------------------------------------------------------------------------------

resource "aws_security_group" "app" {
  name        = "${var.project_name}-app-sg"
  description = "Permite trafego HTTP publico para a TaskFlow API"
  vpc_id      = aws_vpc.main.id

  tags = {
    Name = "${var.project_name}-app-sg"
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_vpc_security_group_ingress_rule" "http" {
  security_group_id = aws_security_group.app.id
  description       = "HTTP publico"
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 80
  to_port           = 80
  ip_protocol       = "tcp"
}

# Criada apenas quando enable_ssh = true, e restrita ao CIDR informado.
resource "aws_vpc_security_group_ingress_rule" "ssh" {
  count = var.enable_ssh ? 1 : 0

  security_group_id = aws_security_group.app.id
  description       = "SSH administrativo restrito"
  cidr_ipv4         = var.ssh_ingress_cidr
  from_port         = 22
  to_port           = 22
  ip_protocol       = "tcp"
}

resource "aws_vpc_security_group_egress_rule" "all" {
  security_group_id = aws_security_group.app.id
  description       = "Saida liberada para download de pacotes e imagens"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}
