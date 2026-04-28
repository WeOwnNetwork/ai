
# ${var.project_name}: - Monitoring Alerts

resource "digitalocean_monitor_alert" "cpu" {
  alerts {
    email = [var.alert_email]
  }
  window      = "5m"
  type        = "v1/insights/droplet/cpu"
  compare     = "GreaterThan"
  value       = var.cpu_alert_threshold
  enabled     = true
  entities    = [digitalocean_droplet.web.id]
  description = "${var.project_name}:: CPU usage above ${var.cpu_alert_threshold}% for 5 min"
}

resource "digitalocean_monitor_alert" "memory" {
  alerts {
    email = [var.alert_email]
  }
  window      = "5m"
  type        = "v1/insights/droplet/memory_utilization_percent"
  compare     = "GreaterThan"
  value       = var.memory_alert_threshold
  enabled     = true
  entities    = [digitalocean_droplet.web.id]
  description = "${var.project_name}:: Memory usage above ${var.memory_alert_threshold}% for 5 min"
}

resource "digitalocean_monitor_alert" "disk" {
  alerts {
    email = [var.alert_email]
  }
  window      = "5m"
  type        = "v1/insights/droplet/disk_utilization_percent"
  compare     = "GreaterThan"
  value       = var.disk_alert_threshold
  enabled     = true
  entities    = [digitalocean_droplet.web.id]
  description = "${var.project_name}:: Disk usage above ${var.disk_alert_threshold}% for 5 min"
}

resource "digitalocean_monitor_alert" "load_5" {
  alerts {
    email = [var.alert_email]
  }
  window      = "5m"
  type        = "v1/insights/droplet/load_5"
  compare     = "GreaterThan"
  value       = 4 # 2× vCPUs for default droplet size
  enabled     = true
  entities    = [digitalocean_droplet.web.id]
  description = "${var.project_name}:: 5-min load average above 4 (2× vCPUs)"
}
