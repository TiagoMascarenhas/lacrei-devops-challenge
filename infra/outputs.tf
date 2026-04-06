output "staging_ip" {
  value = aws_eip.staging.public_ip
}

output "production_ip" {
  value = aws_eip.production.public_ip
}

output "ecr_repository_url" {
  value = aws_ecr_repository.lacrei_api.repository_url
}

output "staging_url" {
  value = "http://${aws_eip.staging.public_ip}:3000/status"
}

output "production_url" {
  value = "http://${aws_eip.production.public_ip}:3000/status"
}
