# ---------------------------------------------------------------------------
# DNS: the app's names point at the static IP above.
# The zone itself belongs to the infra-aks/dns project (shared with the voting
# app), so it is only READ here as a data source. `terraform destroy` in this
# folder removes these two records, never the zone or the voting app's records.
# Records and IP live in the same never-destroyed layer, so a cluster rebuild
# never changes what the names resolve to, and the HTTP-01 check for the
# HTTPS certificate never meets a stale record.
# ---------------------------------------------------------------------------
data "azurerm_dns_zone" "aks" {
  name                = var.dns_zone_name
  resource_group_name = var.dns_zone_resource_group
}

resource "azurerm_dns_a_record" "app" {
  for_each = toset(var.dns_hostnames)

  name                = each.value
  zone_name           = data.azurerm_dns_zone.aks.name
  resource_group_name = data.azurerm_dns_zone.aks.resource_group_name
  ttl                 = 300
  records             = [azurerm_public_ip.gateway.ip_address]
  tags                = local.common_tags
}
