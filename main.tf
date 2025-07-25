terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.100"
    }
  }

  required_version = ">= 1.3.0"
}

provider "azurerm" {
  features {}
}

#======================================
# Common Variables
#======================================
locals {
  location     = "westus3"
  hub_rg_name  = "rg-crev-dp-hub-krs-01"
  prod_rg_name = "rg-crev-dp-prod-krs-01"
}

#======================================
# Resource Groups
#======================================
resource "azurerm_resource_group" "hub" {
  name     = local.hub_rg_name
  location = local.location
}

resource "azurerm_resource_group" "prod" {
  name     = local.prod_rg_name
  location = local.location
}

#======================================
# Virtual Networks and Subnets
#======================================
resource "azurerm_virtual_network" "hub_vnet" {
  name                = "vnet-crev-dp-hub-krs-01"
  location            = local.location
  resource_group_name = azurerm_resource_group.hub.name
  address_space       = ["10.231.16.0/21"]
}

resource "azurerm_subnet" "gateway_subnet" {
  name                 = "GatewaySubnet"
  resource_group_name  = azurerm_resource_group.hub.name
  virtual_network_name = azurerm_virtual_network.hub_vnet.name
  address_prefixes     = ["10.231.16.0/27"]
}

resource "azurerm_virtual_network" "prod_vnet" {
  name                = "vnet-crev-dp-prod-krs-01"
  location            = local.location
  resource_group_name = azurerm_resource_group.prod.name
  address_space       = ["10.231.24.0/21"]
}

resource "azurerm_subnet" "vm_subnet_1" {
  name                 = "snet-crev-dp-prod-krs-sqlmi-01"
  resource_group_name  = azurerm_resource_group.prod.name
  virtual_network_name = azurerm_virtual_network.prod_vnet.name
  address_prefixes     = ["10.231.24.0/23"]
}

resource "azurerm_subnet" "vm_subnet_2" {
  name                 = "snet-crev-dp-prod-krs-dgw-01"
  resource_group_name  = azurerm_resource_group.prod.name
  virtual_network_name = azurerm_virtual_network.prod_vnet.name
  address_prefixes     = ["10.231.26.0/24"]
}

#======================================
# VPN Gateway in Hub VNet
#======================================
resource "azurerm_public_ip" "pip1" {
  name                = "pip1-vgw-crev-dp-hub-krs-01"
  location            = local.location
  resource_group_name = azurerm_resource_group.hub.name
  allocation_method   = "Static"
  sku                 = "Standard"
}

resource "azurerm_public_ip" "pip2" {
  name                = "pip2-vgw-crev-dp-hub-krs-01"
  location            = local.location
  resource_group_name = azurerm_resource_group.hub.name
  allocation_method   = "Static"
  sku                 = "Standard"
}

resource "azurerm_virtual_network_gateway" "hub_vpn_gw" {
  name                = "vgw-crev-dp-hub-krs-01"
  location            = local.location
  resource_group_name = azurerm_resource_group.hub.name
  type                = "Vpn"
  vpn_type            = "RouteBased"
  active_active       = true
  enable_bgp          = false
  sku                 = "VpnGw2"

  ip_configuration {
    name                          = "vnetGatewayConfig1"
    public_ip_address_id          = azurerm_public_ip.pip1.id
    subnet_id                     = azurerm_subnet.gateway_subnet.id
    private_ip_address_allocation = "Dynamic"
  }

  ip_configuration {
    name                          = "vnetGatewayConfig2"
    public_ip_address_id          = azurerm_public_ip.pip2.id
    subnet_id                     = azurerm_subnet.gateway_subnet.id
    private_ip_address_allocation = "Dynamic"
  }
}

#======================================
# Local Network Gateway (On-Prem)
#======================================
resource "azurerm_local_network_gateway" "prod_lng" {
  name                = "lgw-crev-dp-hub-krs-01"
  location            = local.location
  resource_group_name = azurerm_resource_group.hub.name
  gateway_address     = "4.155.48.2"
  address_space       = ["192.168.0.0/16"]
}

#======================================
# VPN Connection
#======================================
resource "azurerm_virtual_network_gateway_connection" "vpn_conn" {
  name                               = "conn-onprem-to-hub-krs"
  location                           = local.location
  resource_group_name                = azurerm_resource_group.hub.name
  virtual_network_gateway_id         = azurerm_virtual_network_gateway.hub_vpn_gw.id
  local_network_gateway_id           = azurerm_local_network_gateway.prod_lng.id
  type                               = "IPsec"
  shared_key                         = "MyS3cr3tKey123!"
  enable_bgp                         = false
  use_policy_based_traffic_selectors = false
}

#======================================
# VNet Peering
#======================================
resource "azurerm_virtual_network_peering" "hub_to_prod" {
  name                      = "peer-hub-to-prod"
  resource_group_name       = azurerm_resource_group.hub.name
  virtual_network_name      = azurerm_virtual_network.hub_vnet.name
  remote_virtual_network_id = azurerm_virtual_network.prod_vnet.id
  allow_forwarded_traffic   = true
  allow_gateway_transit     = true
  use_remote_gateways       = false
}

resource "azurerm_virtual_network_peering" "prod_to_hub" {
  name                      = "peer-prod-to-hub"
  resource_group_name       = azurerm_resource_group.prod.name
  virtual_network_name      = azurerm_virtual_network.prod_vnet.name
  remote_virtual_network_id = azurerm_virtual_network.hub_vnet.id
  allow_forwarded_traffic   = true
  allow_gateway_transit     = false
  use_remote_gateways       = true
}

#======================================
# Windows VM in Prod VNet
#======================================
resource "azurerm_public_ip" "vm_pip" {
  name                = "pip-vm-crev-dp-prod-krs-dgw-01"
  location            = local.location
  resource_group_name = azurerm_resource_group.prod.name
  allocation_method   = "Static"
  sku                 = "Standard"
}

resource "azurerm_network_interface" "vm_nic" {
  name                = "nic-vm-crev-dp-prod-krs-dgw-01"
  location            = local.location
  resource_group_name = azurerm_resource_group.prod.name

  ip_configuration {
    name                          = "ipconfig1"
    subnet_id                     = azurerm_subnet.vm_subnet_2.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.vm_pip.id
  }
}

resource "azurerm_windows_virtual_machine" "vm" {
  name                  = "dgw-krs-01"
  location              = local.location
  resource_group_name   = azurerm_resource_group.prod.name
  size                  = "Standard_D2_v4"
  admin_username        = "azureuser"
  admin_password        = "P@ssw0rd1234!"
  network_interface_ids = [azurerm_network_interface.vm_nic.id]
  computer_name         = "dgw-krs-01"

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
    name                 = "osdisk-dgw-krs-01"
  }

  source_image_reference {
    publisher = "MicrosoftWindowsServer"
    offer     = "WindowsServer"
    sku       = "2022-datacenter"
    version   = "latest"
  }
}