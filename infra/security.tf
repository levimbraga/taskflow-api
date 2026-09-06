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

# ------------------------------------------------------------------------------
# Fase 2 - acesso aos painéis de observabilidade.
#
# Grafana (3000) e Prometheus (9090) expõem dados operacionais e, no caso do
# Grafana, uma tela de login. Nenhum dos dois fica aberto para a internet: as
# duas regras são presas ao mesmo CIDR informado em observability_ingress_cidr,
# cujo padrão (127.0.0.1/32) mantém as portas efetivamente fechadas até que o
# operador declare de qual endereço vai acessar.
# ------------------------------------------------------------------------------

resource "aws_vpc_security_group_ingress_rule" "grafana" {
  security_group_id = aws_security_group.app.id
  description       = "Grafana restrito ao CIDR do operador"
  cidr_ipv4         = var.observability_ingress_cidr
  from_port         = 3000
  to_port           = 3000
  ip_protocol       = "tcp"
}

resource "aws_vpc_security_group_ingress_rule" "prometheus" {
  security_group_id = aws_security_group.app.id
  description       = "Prometheus restrito ao CIDR do operador"
  cidr_ipv4         = var.observability_ingress_cidr
  from_port         = 9090
  to_port           = 9090
  ip_protocol       = "tcp"
}
