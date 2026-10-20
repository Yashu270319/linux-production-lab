output "network" {
  value = docker_network.production.name
}

output "nginx_ip" {
  value = docker_container.nginx.network_data[0].ip_address
}

output "app1_ip" {
  value = docker_container.app1.network_data[0].ip_address
}

output "app2_ip" {
  value = docker_container.app2.network_data[0].ip_address
}

output "database_ip" {
  value = docker_container.database.network_data[0].ip_address
}
