variable "network_name" {
  description = "Private network for the Linux production lab"
  type        = string
  default     = "production-net"
}

variable "subnet" {
  description = "Private subnet used by the lab"
  type        = string
  default     = "10.10.0.0/24"
}

variable "gateway" {
  description = "Gateway for the private lab network"
  type        = string
  default     = "10.10.0.1"
}
