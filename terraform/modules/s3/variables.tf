variable "bucket_name" {}
variable "versioning" {
  type    = string
  default = "Disabled"
}

variable "force_destroy" {
  type = bool
  default = null
}