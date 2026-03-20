variable "name" {}
variable "vpc_id" {}

variable "ingress" {
  type = list(object({
    from_port       = number
    to_port         = number
    protocol        = string
    cidr_blocks     = optional(list(string))
    security_groups = optional(list(string))
  }))

  validation {
    condition = alltrue([
      for rule in var.ingress :
      (contains(keys(rule), "cidr_blocks") || contains(keys(rule), "security_groups"))
    ])
    error_message = "Each ingress rule must have either cidr_blocks or security_groups."
  }
}

variable "egress" {
  type = list(object({
    from_port   = number
    to_port     = number
    protocol    = string
    cidr_blocks = list(string)
  }))
}