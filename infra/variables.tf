variable "aws_region" {
  description = "Região da AWS. O Learner Lab autoriza apenas us-east-1 e us-west-2."
  type        = string
  default     = "us-east-1"

  validation {
    condition     = contains(["us-east-1", "us-west-2"], var.aws_region)
    error_message = "O AWS Academy Learner Lab só permite us-east-1 ou us-west-2."
  }
}

variable "project_name" {
  description = "Prefixo aplicado ao nome de todos os recursos."
  type        = string
  default     = "taskflow"
}

variable "environment" {
  description = "Identificador do ambiente (dev, hml, prd)."
  type        = string
  default     = "dev"
}

variable "vpc_cidr" {
  description = "Bloco CIDR da VPC."
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidrs" {
  description = "Blocos CIDR das sub-redes públicas, uma por zona de disponibilidade."
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "instance_type" {
  description = "Tipo da instância EC2. O Learner Lab limita a família t até o porte large."
  type        = string
  default     = "t3.micro"

  validation {
    condition     = can(regex("^t[23]\\.(nano|micro|small|medium|large)$", var.instance_type))
    error_message = "Use um tipo permitido pelo Learner Lab (t2/t3 de nano a large)."
  }
}

variable "container_image" {
  description = "Imagem publicada pelo pipeline de CI e executada na instância."
  type        = string
  default     = "ghcr.io/levimbraga/taskflow-api:latest"
}

variable "app_port" {
  description = "Porta em que o contêiner da aplicação escuta."
  type        = number
  default     = 8000
}

variable "ssh_ingress_cidr" {
  description = "CIDR autorizado a abrir SSH. Restrinja ao seu IP; nunca use 0.0.0.0/0."
  type        = string
  default     = "0.0.0.0/0"
}

variable "enable_ssh" {
  description = "Habilita a regra de entrada na porta 22. Mantenha false se não precisar."
  type        = bool
  default     = false
}

variable "key_pair_name" {
  description = "Nome de um key pair já existente na conta. Deixe vazio para não associar."
  type        = string
  default     = ""
}

variable "log_retention_days" {
  description = "Retenção dos logs no CloudWatch, em dias."
  type        = number
  default     = 7
}
