terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }

  # O estado é mantido localmente. No AWS Academy Learner Lab as credenciais são
  # temporárias e a conta é reciclada entre sessões, o que torna um backend
  # remoto (S3 + DynamoDB) instável para este cenário. Em ambiente produtivo o
  # bloco abaixo seria habilitado para permitir trabalho em equipe e bloqueio
  # de estado concorrente:
  #
  # backend "s3" {
  #   bucket         = "taskflow-tfstate"
  #   key            = "fase1/terraform.tfstate"
  #   region         = "us-east-1"
  #   dynamodb_table = "taskflow-tflock"
  #   encrypt        = true
  # }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "Terraform"
      Discipline  = "DevOps na Pratica - PUCRS"
    }
  }
}
