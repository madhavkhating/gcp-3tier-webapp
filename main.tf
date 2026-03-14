#Create a Project VPC
resource "google_compute_network" "webapp-vpc" {
  name                    = "webapp-vpc"
  auto_create_subnetworks = false
  project                 = var.project_id
  mtu                     = "1460"
  routing_mode            = "REGIONAL"
}

#Create a custom subnet for web tier
resource "google_compute_subnetwork" "webtier-subnet" {
  name          = "webtier-subnet"
  ip_cidr_range = "10.0.1.0/24"
  region        = var.region
  network       = google_compute_network.webapp-vpc.id
  purpose       = "PRIVATE"
  project       = var.project_id
  stack_type    = "IPV4_ONLY"
}

#Configure the load balancer Part 1
#Create a proxy-only subnet for Regional external load balancer
resource "google_compute_subnetwork" "proxy-subnet" {
  name          = "proxy-subnet"
  ip_cidr_range = "10.129.0.0/26"
  region        = var.region
  network       = google_compute_network.webapp-vpc.id
  project       = var.project_id
  purpose       = "REGIONAL_MANAGED_PROXY"
  role          = "ACTIVE"
}

#An ip address for the Regional External load balancer
resource "google_compute_address" "rextlb-ip" {
  name         = "rextlb-ip"
  region       = var.region
  project      = var.project_id
  network_tier = "STANDARD"
}
#An external forwarding rule for the Regional External load balancer
resource "google_compute_forwarding_rule" "rextlb-fr" {
  name                  = "rextlb-fr"
  load_balancing_scheme = "EXTERNAL_MANAGED"
  depends_on            = [google_compute_subnetwork.proxy-subnet]
  ip_protocol           = "TCP"
  port_range            = "80"
  target                = google_compute_region_target_http_proxy.rextlb-http-proxy.id
  ip_address            = google_compute_address.rextlb-ip.id
  network               = google_compute_network.webapp-vpc.id
  network_tier          = "STANDARD"
  region                = var.region
  project               = var.project_id

}

#Target proxy for the Regional External load balancer
resource "google_compute_region_target_http_proxy" "rextlb-http-proxy" {
  name    = "rextlb-http-proxy"
  region  = var.region
  project = var.project_id
  url_map = google_compute_region_url_map.rextlb-url-map.id
}

#A URL map
resource "google_compute_region_url_map" "rextlb-url-map" {
  name            = "rextlb-url-map"
  region          = var.region
  project         = var.project_id
  default_service = google_compute_region_backend_service.rextlb-backend-service.id
}


###################### WebTier instance group and template #####################################

#Backend service with a managed instance group as the backend
resource "google_compute_region_backend_service" "rextlb-backend-service" {
  name                  = "rextlb-backend-service"
  region                = var.region
  protocol              = "HTTP"
  session_affinity      = "NONE"
  timeout_sec           = 30
  project               = var.project_id
  load_balancing_scheme = "EXTERNAL_MANAGED"
  backend {
    group           = google_compute_region_instance_group_manager.webapp-instance-group.instance_group
    balancing_mode  = "UTILIZATION"
    capacity_scaler = 1.0
  }
  health_checks = [google_compute_region_health_check.rextlb-health-check.id]
}

data "google_compute_image" "debian-11" {
  family  = "debian-11"
  project = "debian-cloud"
}

resource "google_compute_region_instance_group_manager" "webapp-instance-group" {
  name               = "webapp-instance-group"
  region             = var.region
  project            = var.project_id
  base_instance_name = "webapp-instance"
  target_size        = 2
  version {
    instance_template = google_compute_instance_template.webapp-instance-template.id
    name              = "webapp-instance-version"
  }

}

resource "google_compute_instance_template" "webapp-instance-template" {
  name_prefix    = "webapp-instance-template-"
  project        = var.project_id
  region         = var.region
  machine_type   = "e2-micro"
  can_ip_forward = false
  tags           = ["webapp-backend", "allow-ssh"]
  network_interface {
    network    = google_compute_network.webapp-vpc.id
    subnetwork = google_compute_subnetwork.webtier-subnet.id
  }
  disk {
    source_image = data.google_compute_image.debian-11.self_link
    auto_delete  = true
    boot         = true
  }

}

#Configure the load balancer Part 2
#HTTP health check
resource "google_compute_region_health_check" "rextlb-health-check" {
  name                = "rextlb-health-check"
  region              = var.region
  project             = var.project_id
  check_interval_sec  = 5
  timeout_sec         = 5
  healthy_threshold   = 2
  unhealthy_threshold = 2
  http_health_check {
    port_specification = "USE_SERVING_PORT"
  }

}



#An ingress rule, applicable to the instances being load balanced, that allows all TCP traffic from the Google Cloud health checking systems.
resource "google_compute_firewall" "fw3" {
  name          = "webapp-fw3"
  project       = var.project_id
  network       = google_compute_network.webapp-vpc.id
  direction     = "INGRESS"
  priority      = "1000"
  source_ranges = ["130.211.0.0/22", "35.191.0.0/16"]
  allow {
    protocol = "tcp"
    ports    = ["80", "443", "8080"]
  }
  target_tags = ["webapp-backend"]
}

#An ingress rule, applicable to the instances being load balanced, that allows TCP traffic on ports 80, 443, and 8080 from the regional external Application Load Balancer's managed proxies.
resource "google_compute_firewall" "fw4" {
  name          = "webapp-fw4"
  project       = var.project_id
  network       = google_compute_network.webapp-vpc.id
  direction     = "INGRESS"
  source_ranges = ["10.129.0.0/26"]
  target_tags   = ["webapp-backend"]
  allow {
    protocol = "tcp"
    ports    = ["80"]
  }
  allow {
    protocol = "tcp"
    ports    = ["443"]
  }
  allow {
    protocol = "tcp"
    ports    = ["8080"]
  }
  priority = "1000"
}
#VM has a firewall rule that allows TCP ingress traffic from the IP range 35.235.240.0/20, port: 22
resource "google_compute_firewall" "allow_ssh" {
  name          = "allow-ssh"
  project       = var.project_id
  network       = google_compute_network.webapp-vpc.id
  direction     = "INGRESS"
  source_ranges = ["35.235.240.0/20"]
  allow {
    protocol = "tcp"
    ports    = ["22"]
  }
  target_tags = ["allow-ssh"]
}
#Application Tier 
#Create a subnet for Application tier
resource "google_compute_subnetwork" "apptier-subnet" {
  name          = "apptier-subnet"
  ip_cidr_range = "10.0.2.0/24"
  region        = var.region
  network       = google_compute_network.webapp-vpc.id
  project       = var.project_id
}

resource "google_compute_region_instance_group_manager" "apptier-instance-group" {
  name               = "apptier-instance-group"
  region             = var.region
  project            = var.project_id
  base_instance_name = "apptier-instance"
  target_size        = 2
  version {
    instance_template = google_compute_instance_template.app-tier-instance-template.id
    name              = "apptier-instance-version"
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "google_compute_instance_template" "app-tier-instance-template" {
  name_prefix    = "app-tier-instance-template-"
  project        = var.project_id
  region         = var.region
  machine_type   = "e2-micro"
  can_ip_forward = false
  tags           = ["app-tier-backend", "allow-ssh"]
  network_interface {
    network    = google_compute_network.webapp-vpc.id
    subnetwork = google_compute_subnetwork.apptier-subnet.id
  }
  disk {
    source_image = data.google_compute_image.debian-11.self_link
    auto_delete  = true
    boot         = true
  }

  lifecycle {
    create_before_destroy = true
  }
}

#Create Regional Internal Load Balancer for Application tier
resource "google_compute_subnetwork" "proxy-subnet-2" {
  name          = "proxy-subnet-2"
  ip_cidr_range = "10.129.1.0/26"
  region        = var.region
  network       = google_compute_network.webapp-vpc.id
  project       = var.project_id
  purpose       = "PRIVATE"
  role          = "ACTIVE"

}

resource "google_compute_region_health_check" "apptier-health-check" {
  name    = "apptier-health-check"
  region  = var.region
  project = var.project_id
  http_health_check {
    port_specification = "USE_SERVING_PORT"
  }

}

resource "google_compute_region_backend_service" "apptier-backend-service" {
  name                  = "apptier-backend-service"
  region                = var.region
  protocol              = "HTTP"
  timeout_sec           = 30
  project               = var.project_id
  load_balancing_scheme = "INTERNAL_MANAGED"
  health_checks         = [google_compute_region_health_check.apptier-health-check.id]
  backend {
    group           = google_compute_region_instance_group_manager.apptier-instance-group.instance_group
    balancing_mode  = "UTILIZATION"
    capacity_scaler = 1.0
  }
}

resource "google_compute_region_url_map" "apptier-url-map" {
  name            = "apptier-url-map"
  region          = var.region
  project         = var.project_id
  default_service = google_compute_region_backend_service.apptier-backend-service.id
}

resource "google_compute_region_target_http_proxy" "apptier-http-proxy" {
  name    = "apptier-http-proxy"
  project = var.project_id
  region  = var.region
  url_map = google_compute_region_url_map.apptier-url-map.id
}

resource "google_compute_forwarding_rule" "apptier-fw-rule" {
  name                  = "apptier-fw-rule"
  project               = var.project_id
  region                = var.region
  load_balancing_scheme = "INTERNAL_MANAGED"
  ip_protocol           = "TCP"
  port_range            = "8080"
  target                = google_compute_region_target_http_proxy.apptier-http-proxy.id
  network               = google_compute_network.webapp-vpc.id
  subnetwork            = google_compute_subnetwork.proxy-subnet-2.id
  depends_on            = [google_compute_subnetwork.proxy-subnet]

}

resource "google_compute_firewall" "proxytoapptier-fw" {
  name          = "proxy-to-apptier-fw"
  project       = var.project_id
  network       = google_compute_network.webapp-vpc.id
  direction     = "INGRESS"
  source_ranges = ["10.129.1.0/26"]
  target_tags   = ["app-tier-backend"]
  allow {
    protocol = "tcp"
    ports    = ["8080"]
  }
}

output "ilb_ip" {
  value = google_compute_forwarding_rule.apptier-fw-rule.ip_address
}

resource "google_compute_firewall" "allow_web_to_ilb" {
  name    = "allow-web-to-ilb"
  project = var.project_id
  network = google_compute_network.webapp-vpc.id
  allow {
    protocol = "tcp"
    ports    = ["80", "443", "8080"]
  }
  source_ranges = ["10.0.1.0/24"]
  target_tags   = ["app-tier-backend"]

}

#Create a subnetwork for DB tier
resource "google_compute_subnetwork" "dbtier-subnet" {
  name          = "dbtier-subnet"
  ip_cidr_range = "10.0.3.0/24"
  region        = var.region
  network       = google_compute_network.webapp-vpc.id
  project       = var.project_id
}

resource "google_compute_firewall" "allow_apptier_to_dbtier" {
  name    = "allow-apptier-to-dbtier"
  project = var.project_id
  network = google_compute_network.webapp-vpc.id
  allow {
    protocol = "tcp"
    ports    = ["5432"]
  }
  source_ranges = ["10.0.2.0/24"]
  target_tags   = ["dbtier-backend"]
}

#Create a Primary Database Instance (Zone A)
resource "google_compute_instance" "db_primary" {
  name         = "pg-primary"
  project      = var.project_id
  zone         = "asia-south1-a"
  machine_type = "e2-micro"
  tags         = ["dbtier-backend", "allow-ssh"]
  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-11"
      size  = 50
    }
  }
  network_interface {
    subnetwork = google_compute_subnetwork.dbtier-subnet.id
    network    = google_compute_network.webapp-vpc.id
  }

}

#Create a Standby Database Instance (Zone B)
resource "google_compute_instance" "db_standby" {
  name         = "pg-standby"
  project      = var.project_id
  zone         = "asia-south1-b"
  machine_type = "e2-micro"
  tags         = ["dbtier-secondary", "allow-ssh"]
  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-11"
      size  = 50
    }
  }
  network_interface {
    subnetwork = google_compute_subnetwork.dbtier-subnet.id
    network    = google_compute_network.webapp-vpc.id
  }
}


#Create a Firewall Rule: Allow Replication between DB VMs
resource "google_compute_firewall" "allow_db_replication" {
  name    = "allow-db-replication"
  project = var.project_id
  network = google_compute_network.webapp-vpc.id
  allow {
    protocol = "tcp"
    ports    = ["5432"]
  }
  source_ranges = ["10.0.3.0/24"]
  target_tags   = ["dbtier-secondary"]
}

#Create NAT gateway to have internet access to all subnet and their VMs for updates.
resource "google_compute_router" "nat-router" {
  name    = "nat-router"
  project = var.project_id
  region  = var.region
  network = google_compute_network.webapp-vpc.id
}

resource "google_compute_router_nat" "nat-config" {
  name                               = "nat-config"
  project                            = var.project_id
  region                             = var.region
  router                             = google_compute_router.nat-router.name
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"
}







