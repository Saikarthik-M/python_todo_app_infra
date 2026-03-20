output "kops_bucket_name" {
  value = module.kops_s3.bucket_name
}

output "vpc_id" {
  value = module.vpc.vpc_id
}

output "private_subnet_ids" {
  value = module.vpc.private_subnet_ids
}