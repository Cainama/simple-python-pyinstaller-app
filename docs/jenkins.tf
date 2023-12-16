terraform {
  required_providers {
    docker = {
      source  = "kreuzwerker/docker"
      version = "~> 3.0.1"
    }
  }
}

provider "docker" {}

resource "docker_network" "jenkins" {
  name = "jenkins-network"
}

resource "docker_volume" "jenkins_certs" {
  name = "jenkins-docker-certs"
}

resource "docker_volume" "jenkins_data" {
  name = "jenkins-data"
}

resource "docker_container" "jenkins_docker" {
  name       = "jenkins-docker"
  image      = "docker:dind"
  restart    = "unless-stopped"
  privileged = true
  env = [
    "DOCKER_TLS_CERTDIR=/certs"
  ]

  volumes {
    volume_name    = docker_volume.jenkins_certs.name
    container_path = "/certs/client"
  }

  volumes {
    volume_name    = docker_volume.jenkins_data.name
    container_path = "/var/jenkins_home"
  }

  ports {
    internal = 2376
    external = 2376
  }

  ports {
    internal = 3000
    external = 3000
  }

  ports {
    internal = 5000
    external = 5000
  }

  networks_advanced {
    name    = docker_network.jenkins.name
    aliases = ["docker"]
  }

  command = ["--storage-driver", "overlay2"]
}

resource "docker_container" "jenkins_blueocean" {
  name    = "jenkins-blueocean"
  image   = "myjenkins-blueocean"
  restart = "unless-stopped"
  env = [
    "DOCKER_HOST=tcp://docker:2376",
    "DOCKER_CERT_PATH=/certs/client",
    "DOCKER_TLS_VERIFY=1",
  ]

  volumes {
    volume_name    = docker_volume.jenkins_certs.name
    container_path = "/certs/client"
    read_only      = true
  }

  volumes {
    volume_name    = docker_volume.jenkins_data.name
    container_path = "/var/jenkins_home"
  }

  ports {
    internal = 8080
    external = 8080
  }

  ports {
    internal = 50000
    external = 50000
  }

  networks_advanced {
    name = docker_network.jenkins.name
  }
}