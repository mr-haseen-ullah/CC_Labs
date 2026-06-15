variable "aws_region" {
  type        = string
  description = "The AWS region to deploy resources in"
  default     = "us-east-1"
}

variable "student_name" {
  type        = string
  description = "Name of the student"
  default     = "Haseen Ullah"
}

variable "student_reg_number" {
  type        = string
  description = "Registration number of the student"
  default     = "22MDSWE238"
}

variable "course_code" {
  type        = string
  description = "Course Code"
  default     = "SE-409L"
}
