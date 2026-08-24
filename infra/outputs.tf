output "app_url" {
  description = "URL pública da TaskFlow API."
  value       = "http://${aws_eip.app.public_ip}"
}

output "health_check_url" {
  description = "Endpoint usado para validar o deploy."
  value       = "http://${aws_eip.app.public_ip}/health"
}

output "swagger_url" {
  description = "Documentação interativa gerada pelo FastAPI."
  value       = "http://${aws_eip.app.public_ip}/docs"
}

output "instance_id" {
  description = "Identificador da instância EC2."
  value       = aws_instance.app.id
}

output "vpc_id" {
  description = "Identificador da VPC criada."
  value       = aws_vpc.main.id
}

output "artifacts_bucket" {
  description = "Bucket S3 de artefatos do pipeline."
  value       = aws_s3_bucket.artifacts.bucket
}

output "log_group_name" {
  description = "Grupo de logs da aplicação no CloudWatch."
  value       = aws_cloudwatch_log_group.app.name
}
