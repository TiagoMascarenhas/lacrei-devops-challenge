variable "aws_region" {
  default = "us-east-1"
}

variable "project_name" {
  default = "lacrei"
}

variable "instance_type" {
  default = "t2.micro"
}

variable "key_name" {
  description = "Nome do key pair criado na AWS"
  default     = "lacrei-key"
}
