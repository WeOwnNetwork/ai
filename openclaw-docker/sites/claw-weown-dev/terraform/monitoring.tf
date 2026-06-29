# claw-weown-dev - Monitoring Configuration
# Managed by OpenTofu


resource "digitalocean_monitor_alert" "cpu" {
  count = var.enable_monitoring ? 1 : 0
  alerts {
    email = [var.alert_email]
  }
  window      = "5m"
  type        = "v1/insights/droplet/cpu"
  compare     = "GreaterThan"
  value       = var.cpu_alert_threshold
  enabled     = true
  entities    = [digitalocean_droplet.openclaw.id]
  description = "claw-weown-dev: CPU usage above ${var.cpu_alert_threshold}% for 5 min"
}

resource "digitalocean_monitor_alert" "memory" {
  count = var.enable_monitoring ? 1 : 0
  alerts {
    email = [var.alert_email]
  }
  window      = "5m"
  type        = "v1/insights/droplet/memory_utilization_percent"
  compare     = "GreaterThan"
  value       = var.memory_alert_threshold
  enabled     = true
  entities    = [digitalocean_droplet.openclaw.id]
  description = "claw-weown-dev: Memory usage above ${var.memory_alert_threshold}% for 5 min"
}

resource "digitalocean_monitor_alert" "disk" {
  count = var.enable_monitoring ? 1 : 0
  alerts {
    email = [var.alert_email]
  }
  window      = "5m"
  type        = "v1/insights/droplet/disk_utilization_percent"
  compare     = "GreaterThan"
  value       = var.disk_alert_threshold
  enabled     = true
  entities    = [digitalocean_droplet.openclaw.id]
  description = "claw-weown-dev: Disk usage above ${var.disk_alert_threshold}% for 5 min"
}
