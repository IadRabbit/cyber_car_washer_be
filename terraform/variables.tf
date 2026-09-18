variable "aws_region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "eu-west-1"
}

variable "project_name" {
  description = "Name prefix used for all resources"
  type        = string
  default     = "cyber-car-washer"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for the public subnets (one per AZ)"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "lambda_architecture" {
  description = "Lambda instruction set architecture (x86_64 or arm64)"
  type        = string
  default     = "arm64"

  validation {
    condition     = contains(["x86_64", "arm64"], var.lambda_architecture)
    error_message = "lambda_architecture must be either \"x86_64\" or \"arm64\"."
  }
}

variable "lambda_python_version" {
  description = "Python runtime version for the Lambda function (must match a Lambda-managed python3.x runtime)"
  type        = string
  default     = "3.13"
}

variable "lambda_memory_size" {
  description = "Lambda memory size in MB"
  type        = number
  default     = 128
}

variable "lambda_timeout" {
  description = "Lambda timeout in seconds"
  type        = number
  default     = 10
}

variable "api_key" {
  description = "Shared secret required in the X-Api-Key header for requests to reach the Lambda; all other requests get a 404"
  type        = string
  sensitive   = true
}
