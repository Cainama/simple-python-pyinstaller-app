# Entregable 3
### Virtualización de Sistemas 2023/2024
Manuel Pedrajas Ochoa

# Creación y despliegue de infraestructura

## Creación de imagen de Jenkins
Primero debemos crear una imagen personalizada del contenedor de Jenkins. Para ello, crearemos un archivo dockerfile con el que se construirá la imagen que posteriormente desplegaremos con Terraform. Creamos el dockerfile con el siguiente contenido:
```
FROM jenkins/jenkins:2.426.2-jdk17
USER root
RUN apt-get update && apt-get install -y lsb-release
RUN curl -fsSLo /usr/share/keyrings/docker-archive-keyring.asc \
  https://download.docker.com/linux/debian/gpg
RUN echo "deb [arch=$(dpkg --print-architecture) \
  signed-by=/usr/share/keyrings/docker-archive-keyring.asc] \
  https://download.docker.com/linux/debian \
  $(lsb_release -cs) stable" > /etc/apt/sources.list.d/docker.list
RUN apt-get update && apt-get install -y docker-ce-cli
USER jenkins
RUN jenkins-plugin-cli --plugins "blueocean:1.27.9 docker-workflow:572.v950f58993843"
```
y posteriormente creamos la imagen con  
`docker build -t myjenkins-blueocean .`

![img01](https://github.com/Zixort/simple-python-pyinstaller-app/blob/main/docs/img/img01.png)

## Despliegue de contenedores en Terraform
Primero crearemos nuestro archivo .tf para levantar los contenedores de `dind` y `myjenkins-blueocean` con el siguiente contenido:
```
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
  name = "jenkins-docker"
  image = "docker:dind"
  restart = "unless-stopped"
  privileged = true
  env = [
    "DOCKER_TLS_CERTDIR=/certs"
  ]

  volumes {
    volume_name = docker_volume.jenkins_certs.name
    container_path = "/certs/client"
  }

  volumes {
    volume_name = docker_volume.jenkins_data.name
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
    name = docker_network.jenkins.name
    aliases = [ "docker" ]
  }

  command = ["--storage-driver", "overlay2"]
}

resource "docker_container" "jenkins_blueocean" {
  name = "jenkins-blueocean"
  image = "myjenkins-blueocean"
  restart = "unless-stopped"
  env = [
    "DOCKER_HOST=tcp://docker:2376",
    "DOCKER_CERT_PATH=/certs/client",
    "DOCKER_TLS_VERIFY=1",
  ]

  volumes {
    volume_name = docker_volume.jenkins_certs.name
    container_path = "/certs/client"
    read_only = true
  }

  volumes {
    volume_name = docker_volume.jenkins_data.name
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
```
Posteriormente, ejecutaremos ese archivo con  
`terraform apply`  
y comprobaremos que se ha levantado todo con  
`terraform show`  

![img02](https://github.com/Zixort/simple-python-pyinstaller-app/blob/main/docs/img/img02.png)


# Ejecución del pipeline

## Configuración y acceso a Jenkins
Una vez hayamos levantado la infraestructura, tenemos que acceder al contenedor de Jenkins para poder ejecutar la pipeline. Para ello, primero usaremos  
`docker logs jenkins-blueocean`  
y buscaremos la contraseña de administrador generada automáticamente por Jenkins. Esto nos servirá para acceder a http://localhost:8080 e introducir la contraseña.

![img03](https://github.com/Zixort/simple-python-pyinstaller-app/blob/main/docs/img/img03.png)

![img04](https://github.com/Zixort/simple-python-pyinstaller-app/blob/main/docs/img/img04.png)

Una vez seamos bienvenidos por Jenkins, debemos reiniciar parte de la infraestructura con un  
`terraform apply`  
Con esto reiniciaremos Jenkins y haremos que los plugins recién instalados sean funcionales.  

## Preparación del entorno
Vamos a usar el pipeline para hacer un despliegue desde un Source Control Manager, en este caso, Github. Nos vamos al repositorio que nos indica el tutorial y creamos un fork. No documento tanto esta parte, dado que la hice a través del navegador. Una vez en nuestro fork, creamos una rama `main` y dentro de ella, editamos el archivo `jenkins/Jenkinsfile` con nuestro contenido, en este caso:
```
pipeline {
    agent none
    options {
        skipStagesAfterUnstable()
    }
    stages {
        stage('Build') {
            agent {
                docker {
                    image 'python:3.12.0-alpine3.18'
                }
            }
            steps {
                sh 'python -m py_compile sources/add2vals.py sources/calc.py'
                stash(name: 'compiled-results', includes: 'sources/*.py*')
            }
        }
        stage('Test') {
            agent {
                docker {
                    image 'qnib/pytest'
                }
            }
            steps {
                sh 'py.test --junit-xml test-reports/results.xml sources/test_calc.py'
            }
            post {
                always {
                    junit 'test-reports/results.xml'
                }
            }
        }
        stage('Deliver') { 
            agent any
            environment { 
                VOLUME = '$(pwd)/sources:/src'
                IMAGE = 'cdrx/pyinstaller-linux:python2'
            }
            steps {
                dir(path: env.BUILD_ID) { 
                    unstash(name: 'compiled-results') 
                    sh "docker run --rm -v ${VOLUME} ${IMAGE} 'pyinstaller -F add2vals.py'" 
                }
            }
            post {
                success {
                    archiveArtifacts "${env.BUILD_ID}/sources/dist/add2vals" 
                    sh "docker run --rm -v ${VOLUME} ${IMAGE} 'rm -rf build dist'"
                }
            }
        }
    }
}
```
También arrastramos la carpeta `docs`, que contiene los archivos pedidos: `dockerfile`, `jenkins.tf` y `README.md`. También creo un directorio `docs/img` para las imágenes de `README.md`.

Cada una de estas acciones representará un commit que deberíamos documentar correctamente,
aunque actualmente no haya mucha chicha.

![img06](https://github.com/Zixort/simple-python-pyinstaller-app/blob/main/docs/img/img06.png)

![img07](https://github.com/Zixort/simple-python-pyinstaller-app/blob/main/docs/img/img07.png)

## Creación del pipeline
Una vez tengamos Jenkins operativo y el repositorio listo, pulsamos _Nueva Tarea_, escribimos un nombre para la tarea (en mi caso, "pythonapp") y seleccionamos _Pipeline_. Nos vamos abajo, a la sección de definición y seleccionamos _Pipeline Script from SCM_.
Una vez en él, escribiremos: 
- en _Repository URL_ nuestra URL del repositorio, en mi caso `https://github.com/Zixort/simple-python-pyinstaller-app.git`.
- en _Branch Specifier_ escribiremos `*/main`
- en _Script Path_ escribiremos `jenkins/Jenkinsfile`

Una vez finalizado, pulsamos _Guardar_.

![img08](https://github.com/Zixort/simple-python-pyinstaller-app/blob/main/docs/img/img08.png)

## Construcción del Pipeline

Para construir la pipeline, tan solo tenemos que pulsar _Construir Ahora_ en el panel de la izquierda.

Una vez finalizada, pulsaremos _Open in Blue Ocean_, pulsaremos la pestaña _Pipelines_, seleccionaremos nuestra pipeline y pulsaremos _Iniciar_. Una vez hecho, podremos acceder al resultado pulsando en la fila, que nos mostrará logs más detallados de cada paso de cada etapa.

![img10](https://github.com/Zixort/simple-python-pyinstaller-app/blob/main/docs/img/img10.png)
