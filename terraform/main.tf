terraform {
  required_providers {
    docker = {
      source  = "kreuzwerker/docker"
      version = "~> 3.6"
    }
  }
}

provider "docker" {}

resource "docker_network" "production" {
  name   = var.network_name
  driver = "bridge"

  ipam_config {
    subnet  = var.subnet
    gateway = var.gateway
  }
}

resource "docker_image" "server" {
  name         = "linux-production-server:1.3"
  keep_locally = true
}

resource "docker_container" "nginx" {
  name     = "nginx-01"
  hostname = "nginx-01"
  image    = docker_image.server.image_id

  privileged = true

  command = ["/sbin/init"]
  restart = "unless-stopped"

  networks_advanced {
    name         = docker_network.production.name
    ipv4_address = "10.10.0.10"
  }
}

resource "docker_container" "app1" {
  name     = "app-01"
  hostname = "app-01"
  image    = docker_image.server.image_id

  privileged = true

  command = ["/sbin/init"]
  restart = "unless-stopped"
  networks_advanced {
    name         = docker_network.production.name
    ipv4_address = "10.10.0.11"
  }
}

resource "docker_container" "app2" {
  name     = "app-02"
  hostname = "app-02"
  image    = docker_image.server.image_id

  privileged = true

  command = ["/sbin/init"]
  restart = "unless-stopped"
  networks_advanced {
    name         = docker_network.production.name
    ipv4_address = "10.10.0.12"
  }
}

resource "docker_container" "database" {
  name     = "db-01"
  hostname = "db-01"
  image    = docker_image.server.image_id

  privileged = true

  command = ["/sbin/init"]
  restart = "unless-stopped"
  networks_advanced {
    name         = docker_network.production.name
    ipv4_address = "10.10.0.20"
  }
}


resource "docker_container" "monitoring" {
  name       = "monitoring-01"
  hostname   = "monitoring-01"
  image      = docker_image.server.image_id
  privileged = true
  command    = ["/sbin/init"]
  restart    = "unless-stopped"
  volumes {
    host_path      = "${path.root}/../data/grafana"
    container_path = "/var/lib/grafana"
  }

  volumes {
    host_path      = "${path.root}/../data/prometheus"
    container_path = "/var/lib/prometheus/metrics2"
  }
  ports {
    internal = 3000
    external = 3000
  }

  ports {
    internal = 9090
    external = 9090
  }

  networks_advanced {
    name         = docker_network.production.name
    ipv4_address = "10.10.0.30"
  }
}
