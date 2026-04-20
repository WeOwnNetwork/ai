# burnedout-xyz - Monitoring Alerts

resource "digitalocean_monitor_alert" "cpu" {
  alerts {
    email = [var.alert_email]
  }
  window      = "5m"
  type        = "v1/insights/droplet/cpu"
  compare     = "GreaterThan"
  value       = 80
  enabled     = true
  entities    = [digitalocean_droplet.web.id]
  description = "burnedout-xyz: CPU usage above 80% for 5 min"
}

resource "digitalocean_monitor_alert" "memory" {
  alerts {
    email = [var.alert_email]
  }
  window      = "5m"
  type        = "v1/insights/droplet/memory_utilization_percent"
  compare     = "GreaterThan"
  value       = 90
  enabled     = true
  entities    = [digitalocean_droplet.web.id]
  description = "burnedout-xyz: Memory usage above 90% for 5 min"
}

resource "digitalocean_monitor_alert" "disk" {
  alerts {
    email = [var.alert_email]
  }
  window      = "5m"
  type        = "v1/insights/droplet/disk_utilization_percent"
  compare     = "GreaterThan"
  value       = 85
  enabled     = true
  entities    = [digitalocean_droplet.web.id]
  description = "burnedout-xyz: Disk usage above 85% for 5 min"
}

resource "digitalocean_monitor_alert" "load_5" {
  alerts {
    email = [var.alert_email]
  }
  window      = "5m"
  type        = "v1/insights/droplet/load_5"
  compare     = "GreaterThan"
  value       = 4
  enabled     = true
  entities    = [digitalocean_droplet.web.id]
  description = "burnedout-xyz: 5-min load average above 4 (2× vCPUs)"
}
