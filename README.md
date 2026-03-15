Runbook For Project of 3 Tier Web App Regional deployment on Compute Engine:
Project Architecture: Regional Multi-Zone deployment

Reference Link: https://docs.cloud.google.com/architecture/regional-deployment-compute-engine#architecture

Cloud Platform: GCP
Project ID: norse-bond-323008
region: asia-south1
	1) VPC: you need a virtual private network for your project to be built in , here I have created this VPC with in asia-south1 region.
webapp-vpc   10.0.0.0/16

#Create a Project VPC
resource "google_compute_network" "webapp-vpc" {
  name                    = "webapp-vpc"
  auto_create_subnetworks = false
  project                 = var.project_id
  mtu                     = "1460"
  routing_mode            = "REGIONAL"
}

	2) Regional External Load Balancer:
The regional external load balancer receives and distributes user requests to the web tier VMs.
The Application Load Balancer is a proxy-based Layer 7 load balancer that lets you run and scale your services. The Application Load Balancer distributes HTTP and HTTPS traffic to backends hosted on a variety of Google Cloud platforms—such as Compute Engine, Google Kubernetes Engine (GKE), Cloud Storage, and Cloud Run—as well as external backends connected over the internet or by using hybrid connectivity.
we will be creating Regional external load balancer.
Architecture:
The following resources are required for an external Application Load Balancer deployment:
For regional external Application Load Balancers only, a proxy-only subnet is used to send connections from the load balancer to the backends.

	Subnets:
	You need proxy only subnet for external load balancer.A proxy-only subnet provides a set of IP addresses that Google uses to run Envoy proxies on your behalf. The proxies terminate connections from the client and create new connections to the backend.
	proxy-only subnet 10.129.0.0/26.
	
	A firewall rule that permits proxy-only subnet traffic flows in your network.
	1)fw-allow-health-check:
	 An ingress rule, applicable to the instances being load balanced, that allows all TCP traffic from the Google Cloud health checking systems (in 130.211.0.0/22 and 35.191.0.0/16). This example uses the target tag "webapp-backend" to identify the VMs that the firewall rule applies to.
	 
	2)fw-allow-proxies:
	 An ingress rule, applicable to the instances being load balanced, that allows TCP traffic on ports 80, 443, and 8080 from the regional external Application Load Balancer's managed proxies. This example uses the target tag "webapp-backend" to identify the VMs that the firewall rule applies to.
	 
	A regional health check that reports the readiness of your backbend's.
	A regional backend service that monitors the usage and health of backbend's.
	A regional URL map that parses the URL of a request and forwards requests to specific backend services based on the host and path of the request URL.
	A regional target HTTP or HTTPS proxy, which receives a request from the user and forwards it to the URL map.
	A forwarding rule, which has the external IP address of your load balancer to forward each incoming request to the target proxy.
	The external IP address that is associated with the forwarding rule.
	
	3) Backend instances (Web tier): Regional managed instance group (MIG) for the web tier
	The web tier of the application is deployed on Compute Engine VMs that are part of a regional MIG. The MIG is the backend for the regional external load balancer.
	The MIG contains Compute Engine VMs in 2 different zones. Each of these VMs hosts an independent instance of the web tier of the application.
	The application's frontend is served by an external Application Load Balancer with instance group backends.Traffic enters from the internet and is proxied from the load balancer to a set of instance group backends in various regions. These backends send HTTP(S) traffic to a set of internal Application Load Balancers.

	Subnet1 - web-subnet 10.0.1.0/24
	Regional MIG - 2 VMs 
	
	4) Regional internal load balancer: The regional internal load balancer distributes traffic from the web tier VMs to the application tier VMs
	
	5) App Tier:
	Regional MIG for the application tier: 
	The application tier is deployed on Compute Engine VMs that are part of a regional MIG, which is the backend for the internal load balancer.
	The MIG contains Compute Engine VMs in three different zones. Each VM hosts an independent instance of the application tier.
	The application's middleware is deployed and scaled by using an internal Application Load Balancer and instance group backends. The load balancers distribute the traffic to middleware instance groups. These middleware instance groups then send the traffic to db layer.
	Subnet2 - app-subnet   10.0.2.0/24
	Regional MIG -2 VMs
	Backend: DB tier db server.

	6) DB Tier: The architecture in this document shows a third-party database (like PostgreSQL) that's deployed on a Compute Engine VM. You can deploy a standby database in another zone. The database replication and failover capabilities depend on the database that you use.
	
	Subnet3 - db-subnet    10.0.3.0/24
	2 DB servers VMs , Active and standby - replication and failover 
	
	Primary VM (asia-south1-a): The writeable instance.
	Standby VM (asia-south1-b): The read-only replica that pulls data from the primary.
	Firewall: Must allow traffic between the two DB VMs for the WAL (Write Ahead Log) shipping.
	Startup Scripts: We'll use these to automate the initial PostgreSQL installation.

	7) NAT Gateway:
	NAT gateway to have internet access to all subnet and their VMs for updates.

	
	===============================================================================================================
	Terraform Code:
	main.tf
	
	#Create a Project VPC
	resource "google_compute_network" "webapp-vpc" {
	  name                    = "webapp-vpc"
	  auto_create_subnetworks = false
	  project                 = var.project_id
	  mtu                     = "1460"
	  routing_mode            = "REGIONAL"
	}
	#Create a custom subnet for web tier
	resource "google_compute_subnetwork" "webtier-subnet" {
	  name          = "webtier-subnet"
	  ip_cidr_range = "10.0.1.0/24"
	  region        = var.region
	  network       = google_compute_network.webapp-vpc.id
	  purpose       = "PRIVATE"
	  project       = var.project_id
	  stack_type    = "IPV4_ONLY"
	}
	#Configure the load balancer Part 1
	#Create a proxy-only subnet for Regional external load balancer
	resource "google_compute_subnetwork" "proxy-subnet" {
	  name          = "proxy-subnet"
	  ip_cidr_range = "10.129.0.0/26"
	  region        = var.region
	  network       = google_compute_network.webapp-vpc.id
	  project       = var.project_id
	  purpose       = "REGIONAL_MANAGED_PROXY"
	  role          = "ACTIVE"
	}
	#An ip address for the Regional External load balancer
	resource "google_compute_address" "rextlb-ip" {
	  name         = "rextlb-ip"
	  region       = var.region
	  project      = var.project_id
	  network_tier = "STANDARD"
	}
	#An external forwarding rule for the Regional External load balancer
	resource "google_compute_forwarding_rule" "rextlb-fr" {
	  name                  = "rextlb-fr"
	  load_balancing_scheme = "EXTERNAL_MANAGED"
	  depends_on            = [google_compute_subnetwork.proxy-subnet]
	  ip_protocol           = "TCP"
	  port_range            = "80"
	  target                = google_compute_region_target_http_proxy.rextlb-http-proxy.id
	  ip_address            = google_compute_address.rextlb-ip.id
	  network               = google_compute_network.webapp-vpc.id
	  network_tier          = "STANDARD"
	  region                = var.region
	  project               = var.project_id
	}
	#Target proxy for the Regional External load balancer
	resource "google_compute_region_target_http_proxy" "rextlb-http-proxy" {
	  name    = "rextlb-http-proxy"
	  region  = var.region
	  project = var.project_id
	  url_map = google_compute_region_url_map.rextlb-url-map.id
	}
	#A URL map
	resource "google_compute_region_url_map" "rextlb-url-map" {
	  name            = "rextlb-url-map"
	  region          = var.region
	  project         = var.project_id
	  default_service = google_compute_region_backend_service.rextlb-backend-service.id
	}
	
	###################### WebTier instance group and template #####################################
	#Backend service with a managed instance group as the backend
	resource "google_compute_region_backend_service" "rextlb-backend-service" {
	  name                  = "rextlb-backend-service"
	  region                = var.region
	  protocol              = "HTTP"
	  session_affinity      = "NONE"
	  timeout_sec           = 30
	  project               = var.project_id
	  load_balancing_scheme = "EXTERNAL_MANAGED"
	  backend {
	    group           = google_compute_region_instance_group_manager.webapp-instance-group.instance_group
	    balancing_mode  = "UTILIZATION"
	    capacity_scaler = 1.0
	  }
	  health_checks = [google_compute_region_health_check.rextlb-health-check.id]
	}
	data "google_compute_image" "debian-11" {
	  family  = "debian-11"
	  project = "debian-cloud"
	}
	resource "google_compute_region_instance_group_manager" "webapp-instance-group" {
	  name               = "webapp-instance-group"
	  region             = var.region
	  project            = var.project_id
	  base_instance_name = "webapp-instance"
	  target_size        = 2
	  version {
	    instance_template = google_compute_instance_template.webapp-instance-template.id
	    name              = "webapp-instance-version"
	  }
	}
	resource "google_compute_instance_template" "webapp-instance-template" {
	  name_prefix    = "webapp-instance-template-"
	  project        = var.project_id
	  region         = var.region
	  machine_type   = "e2-micro"
	  can_ip_forward = false
	  tags           = ["webapp-backend", "allow-ssh"]
	  network_interface {
	    network    = google_compute_network.webapp-vpc.id
	    subnetwork = google_compute_subnetwork.webtier-subnet.id
	  }
	  disk {
	    source_image = data.google_compute_image.debian-11.self_link
	    auto_delete  = true
	    boot         = true
	  }
	}
	#Configure the load balancer Part 2
	#HTTP health check
	resource "google_compute_region_health_check" "rextlb-health-check" {
	  name                = "rextlb-health-check"
	  region              = var.region
	  project             = var.project_id
	  check_interval_sec  = 5
	  timeout_sec         = 5
	  healthy_threshold   = 2
	  unhealthy_threshold = 2
	  http_health_check {
	    port_specification = "USE_SERVING_PORT"
	  }
	}
	
	
	#An ingress rule, applicable to the instances being load balanced, that allows all TCP traffic from the Google Cloud health checking systems.
	resource "google_compute_firewall" "fw3" {
	  name          = "webapp-fw3"
	  project       = var.project_id
	  network       = google_compute_network.webapp-vpc.id
	  direction     = "INGRESS"
	  priority      = "1000"
	  source_ranges = ["130.211.0.0/22", "35.191.0.0/16"]
	  allow {
	    protocol = "tcp"
	    ports    = ["80", "443", "8080"]
	  }
	  target_tags = ["webapp-backend"]
	}
	#An ingress rule, applicable to the instances being load balanced, that allows TCP traffic on ports 80, 443, and 8080 from the regional external Application Load Balancer's managed proxies.
	resource "google_compute_firewall" "fw4" {
	  name          = "webapp-fw4"
	  project       = var.project_id
	  network       = google_compute_network.webapp-vpc.id
	  direction     = "INGRESS"
	  source_ranges = ["10.129.0.0/26"]
	  target_tags   = ["webapp-backend"]
	  allow {
	    protocol = "tcp"
	    ports    = ["80"]
	  }
	  allow {
	    protocol = "tcp"
	    ports    = ["443"]
	  }
	  allow {
	    protocol = "tcp"
	    ports    = ["8080"]
	  }
	  priority = "1000"
	}
	#VM has a firewall rule that allows TCP ingress traffic from the IP range 35.235.240.0/20, port: 22
	resource "google_compute_firewall" "allow_ssh" {
	  name          = "allow-ssh"
	  project       = var.project_id
	  network       = google_compute_network.webapp-vpc.id
	  direction     = "INGRESS"
	  source_ranges = ["35.235.240.0/20"]
	  allow {
	    protocol = "tcp"
	    ports    = ["22"]
	  }
	  target_tags = ["allow-ssh"]
	}
	#Application Tier 
	#Create a subnet for Application tier
	resource "google_compute_subnetwork" "apptier-subnet" {
	  name          = "apptier-subnet"
	  ip_cidr_range = "10.0.2.0/24"
	  region        = var.region
	  network       = google_compute_network.webapp-vpc.id
	  project       = var.project_id
	}
	resource "google_compute_region_instance_group_manager" "apptier-instance-group" {
	  name               = "apptier-instance-group"
	  region             = var.region
	  project            = var.project_id
	  base_instance_name = "apptier-instance"
	  target_size        = 2
	  version {
	    instance_template = google_compute_instance_template.app-tier-instance-template.id
	    name              = "apptier-instance-version"
	  }
	  lifecycle {
	    create_before_destroy = true
	  }
	}
	resource "google_compute_instance_template" "app-tier-instance-template" {
	  name_prefix    = "app-tier-instance-template-"
	  project        = var.project_id
	  region         = var.region
	  machine_type   = "e2-micro"
	  can_ip_forward = false
	  tags           = ["app-tier-backend", "allow-ssh"]
	  network_interface {
	    network    = google_compute_network.webapp-vpc.id
	    subnetwork = google_compute_subnetwork.apptier-subnet.id
	  }
	  disk {
	    source_image = data.google_compute_image.debian-11.self_link
	    auto_delete  = true
	    boot         = true
	  }
	  lifecycle {
	    create_before_destroy = true
	  }
	}
	#Create Regional Internal Load Balancer for Application tier
	resource "google_compute_subnetwork" "proxy-subnet-2" {
	  name          = "proxy-subnet-2"
	  ip_cidr_range = "10.129.1.0/26"
	  region        = var.region
	  network       = google_compute_network.webapp-vpc.id
	  project       = var.project_id
	  purpose       = "PRIVATE"
	  role          = "ACTIVE"
	}
	resource "google_compute_region_health_check" "apptier-health-check" {
	  name    = "apptier-health-check"
	  region  = var.region
	  project = var.project_id
	  http_health_check {
	    port_specification = "USE_SERVING_PORT"
	  }
	}
	resource "google_compute_region_backend_service" "apptier-backend-service" {
	  name                  = "apptier-backend-service"
	  region                = var.region
	  protocol              = "HTTP"
	  timeout_sec           = 30
	  project               = var.project_id
	  load_balancing_scheme = "INTERNAL_MANAGED"
	  health_checks         = [google_compute_region_health_check.apptier-health-check.id]
	  backend {
	    group           = google_compute_region_instance_group_manager.apptier-instance-group.instance_group
	    balancing_mode  = "UTILIZATION"
	    capacity_scaler = 1.0
	  }
	}
	resource "google_compute_region_url_map" "apptier-url-map" {
	  name            = "apptier-url-map"
	  region          = var.region
	  project         = var.project_id
	  default_service = google_compute_region_backend_service.apptier-backend-service.id
	}
	resource "google_compute_region_target_http_proxy" "apptier-http-proxy" {
	  name    = "apptier-http-proxy"
	  project = var.project_id
	  region  = var.region
	  url_map = google_compute_region_url_map.apptier-url-map.id
	}
	resource "google_compute_forwarding_rule" "apptier-fw-rule" {
	  name                  = "apptier-fw-rule"
	  project               = var.project_id
	  region                = var.region
	  load_balancing_scheme = "INTERNAL_MANAGED"
	  ip_protocol           = "TCP"
	  port_range            = "8080"
	  target                = google_compute_region_target_http_proxy.apptier-http-proxy.id
	  network               = google_compute_network.webapp-vpc.id
	  subnetwork            = google_compute_subnetwork.proxy-subnet-2.id
	  depends_on            = [google_compute_subnetwork.proxy-subnet]
	}
	resource "google_compute_firewall" "proxytoapptier-fw" {
	  name          = "proxy-to-apptier-fw"
	  project       = var.project_id
	  network       = google_compute_network.webapp-vpc.id
	  direction     = "INGRESS"
	  source_ranges = ["10.129.1.0/26"]
	  target_tags   = ["app-tier-backend"]
	  allow {
	    protocol = "tcp"
	    ports    = ["8080"]
	  }
	}
	output "ilb_ip" {
	  value = google_compute_forwarding_rule.apptier-fw-rule.ip_address
	}
	resource "google_compute_firewall" "allow_web_to_ilb" {
	  name    = "allow-web-to-ilb"
	  project = var.project_id
	  network = google_compute_network.webapp-vpc.id
	  allow {
	    protocol = "tcp"
	    ports    = ["80", "443", "8080"]
	  }
	  source_ranges = ["10.0.1.0/24"]
	  target_tags   = ["app-tier-backend"]
	}
	#Create a subnetwork for DB tier
	resource "google_compute_subnetwork" "dbtier-subnet" {
	  name          = "dbtier-subnet"
	  ip_cidr_range = "10.0.3.0/24"
	  region        = var.region
	  network       = google_compute_network.webapp-vpc.id
	  project       = var.project_id
	}
	resource "google_compute_firewall" "allow_apptier_to_dbtier" {
	  name    = "allow-apptier-to-dbtier"
	  project = var.project_id
	  network = google_compute_network.webapp-vpc.id
	  allow {
	    protocol = "tcp"
	    ports    = ["5432"]
	  }
	  source_ranges = ["10.0.2.0/24"]
	  target_tags   = ["dbtier-backend"]
	}
	#Create a Primary Database Instance (Zone A)
	resource "google_compute_instance" "db_primary" {
	  name         = "pg-primary"
	  project      = var.project_id
	  zone         = "asia-south1-a"
	  machine_type = "e2-micro"
	  tags         = ["dbtier-backend", "allow-ssh"]
	  boot_disk {
	    initialize_params {
	      image = "debian-cloud/debian-11"
	      size  = 50
	    }
	  }
	  network_interface {
	    subnetwork = google_compute_subnetwork.dbtier-subnet.id
	    network    = google_compute_network.webapp-vpc.id
	  }
	}
	#Create a Standby Database Instance (Zone B)
	resource "google_compute_instance" "db_standby" {
	  name         = "pg-standby"
	  project      = var.project_id
	  zone         = "asia-south1-b"
	  machine_type = "e2-micro"
	  tags         = ["dbtier-secondary", "allow-ssh"]
	  boot_disk {
	    initialize_params {
	      image = "debian-cloud/debian-11"
	      size  = 50
	    }
	  }
	  network_interface {
	    subnetwork = google_compute_subnetwork.dbtier-subnet.id
	    network    = google_compute_network.webapp-vpc.id
	  }
	}
	
	#Create a Firewall Rule: Allow Replication between DB VMs
	resource "google_compute_firewall" "allow_db_replication" {
	  name    = "allow-db-replication"
	  project = var.project_id
	  network = google_compute_network.webapp-vpc.id
	  allow {
	    protocol = "tcp"
	    ports    = ["5432"]
	  }
	  source_ranges = ["10.0.3.0/24"]
	  target_tags   = ["dbtier-secondary"]
	}
	#Create NAT gateway to have internet access to all subnet and their VMs for updates.
	resource "google_compute_router" "nat-router" {
	  name    = "nat-router"
	  project = var.project_id
	  region  = var.region
	  network = google_compute_network.webapp-vpc.id
	}
	resource "google_compute_router_nat" "nat-config" {
	  name                               = "nat-config"
	  project                            = var.project_id
	  region                             = var.region
	  router                             = google_compute_router.nat-router.name
	  nat_ip_allocate_option             = "AUTO_ONLY"
	  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"
	}
	
	#EOF
	-------------------------------------------------------------------------------------------------------------------------------
	Terraform.tf
	
	terraform {
	  required_providers {
	    google = {
	      source  = "hashicorp/google"
	      version = "7.20.0"
	    }
	  }
	}
	#configure the provider with the provider block
	provider "google" {
	  project = "norse-bond-323008"
	  region  = "asia-south1"
	}
	
	#EOF
	--------------------------------------------------------------------------------------------------------------------------
	Variables.tf
	
	#define your project variables in this file
	variable "project_id" {
	  description = "GCP project ID where the resources will be created"
	  type        = string
	  default     = "norse-bond-323008"
	}
	variable "region" {
	  description = "GCP region where the resources will be created"
	  type        = string
	  default     = "asia-south1"
	}
	#EOF
	---------------------------------------------------------------------------------------------------------------------
	
	
	====================================================================================================================================
	Pictures: see the pictures folder 
	
	
	
	
	
	
	















===========================================================================================

