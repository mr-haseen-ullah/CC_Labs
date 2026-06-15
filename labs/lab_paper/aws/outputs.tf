output "ec2_public_ip" {
  description = "The public IP address of the EC2 instance hosting the application"
  value       = aws_instance.web_server.public_ip
}

output "application_url" {
  description = "The url structure (for reference)"
  value       = "http://${aws_instance.web_server.public_ip}"
}

output "s3_bucket_name" {
  description = "Name of the created S3 bucket"
  value       = aws_s3_bucket.finalterm_bucket.id
}

output "ssh_private_key" {
  description = "Private key for SSH access to the EC2 instance"
  value       = tls_private_key.web_server_key.private_key_pem
  sensitive   = true
}
