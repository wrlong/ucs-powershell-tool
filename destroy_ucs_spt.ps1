# Get commmand line parameters, takes:
#   ucsm_ip - UCSM IP
#   ucsm_user - UCSM user
#   ucsm_pw - UCSM password
#   config_file - JSON formatted config file defining SPT template
param (
    [string]$ucsm_ip = $(throw "-ucsm_ip is required."),
    [string]$ucsm_user = $(throw "-ucsm_user is required."),
    [string]$ucsm_pw = $(throw "-ucsm_pw is required."),
    [string]$config_file = $(throw "-config_file is required.")
)

# The UCSM connection requires a PSCredential to login, so we must convert our plain text password to make an object
#$ucsm_pw = ConvertTo-SecureString -String $ucsm_pw -AsPlainText -Force
#$cred = new-object -typename System.Management.Automation.PSCredential -argumentlist $ucsm_user, $ucsm_pw

#$handle = Connect-Ucs $ucsm_ip -Credential $cred
echo $ucsm_ip
echo $ucsm_user
echo $ucsm_pw
echo $config_file

# Get JSON data
$json = Get-Content $config_file | Out-String | ConvertFrom-Json

# Get Service Profile Template org
$spt_org_name = $json.template.org

# Get Service Profile Template name
$spt_name = $json.template.name

# Get SPT Bios Policy name
$spt_bios_policy_name = $json.template.policies.bios.name

# Get SPT Boot Policy name, type, paths, targets
$spt_boot_policy_name = $json.template.policies.boot.name
$spt_boot_policy_type = $json.template.policies.boot.type
$spt_boot_policy_primary_vhba_name = $json.template.policies.boot.paths.vhba_primary.name
$spt_boot_policy_primary_vhba_primary_target = $json.template.policies.boot.paths.vhba_primary.target_primary
$spt_boot_policy_primary_vhba_secondary_target = $json.template.policies.boot.paths.vhba_primary.target_secondary
$spt_boot_policy_secondary_vhba_name = $json.template.policies.boot.paths.vhba_secondary.name
$spt_boot_policy_secondary_vhba_primary_target = $json.template.policies.boot.paths.vhba_secondary.target_primary
$spt_boot_policy_secondary_vhba_secondary_target = $json.template.policies.boot.paths.vhba_secondary.target_secondary

# Get SPT firmware policy name
$spt_firmware_policy_name = $json.template.policies.firmware.name

# Get SPT local disk policy name
$spt_local_disk_policy_name = $json.template.policies.local_disk_config.name

# Get SPT maintenance policy name
$spt_maintenance_policy_name = $json.template.policies.maintenance.name

# Get SPT power policy name
$spt_power_policy_name = $json.template.policies.power_ctrl.name

# Get SPT power policy name
$spt_server_pool_qual_name = $json.template.policies.server_pool_qual.name

# Get SPT Pools
#
# Get SPT server pool
$spt_server_pool_name = $json.template.pools.server.name
$spt_server_pool_chassis_range = $json.template.pools.server.range.chassis
$spt_server_pool_slots_range = $json.template.pools.server.range.slots

# Get SPT UUID pool
$spt_uuid_pool_name = $json.template.pools.uuid.name
$spt_uuid_pool_range = $json.template.pools.uuid.range

# Get SPT WWNN pool
$spt_wwnn_pool_name = $json.template.pools.wwnn.name
$spt_wwnn_pool_range = $json.template.pools.wwnn.range

# Get SPT service profile instance info
$spt_sp_instances = $json.template.service_profiles.instances
$spt_sp_prefix = $json.template.service_profiles.prefix

# Get SPT templates
#
# Get SPT vhba template
$spt_vhbas = @{}
$json.template.templates.vhba.psobject.properties | Foreach { $spt_vhbas[$_.Name] = $_.Value }

# Get SPT vnic template
$spt_vnics = @{}
$json.template.templates.vnic.psobject.properties | Foreach { $spt_vnics[$_.Name] = $_.Value }

# Build UCS Transaction for one API call
Start-UcsTransaction

#$prefix = "svl-cc-"
#$node_name = $prefix + "build"

# Remove everything
#
#

Get-UcsOrg -Level root | Get-UcsOrg -Name $spt_org_name -LimitScope | Get-UcsServiceProfile -Name $spt_name -LimitScope | Remove-UcsServiceProfile -force

$spt_vnics.Keys | % { 
    $cur_vnic_name = $_
    $cur_vnic_props = $spt_vnics.Item($_)

    Get-UcsOrg -Level root | Get-UcsOrg -Name $spt_org_name -LimitScope | Get-UcsVnicTemplate -Name $cur_vnic_name -LimitScope | Remove-UcsVnicTemplate -force
    Get-UcsOrg -Level root | Get-UcsOrg -Name $spt_org_name -LimitScope | Get-UcsMacPool -Name $cur_vnic_props.macpool.name -LimitScope | Remove-UcsMacPool -force
    Get-UcsOrg -Level root | Get-UcsOrg -Name $spt_org_name -LimitScope | Get-UcsQosPolicy -Name $cur_vnic_props.qos_policy.name -LimitScope | Remove-UcsQosPolicy
}

$spt_vhbas.Keys | % { 
    $cur_vhba_name = $_
    $cur_vhba_props = $spt_vhbas.Item($_)

    Get-UcsOrg -Level root | Get-UcsOrg -Name $spt_org_name -LimitScope | Get-UcsVhbaTemplate -Name $cur_vhba_name -LimitScope | Remove-UcsVhbaTemplate -force
    Get-UcsOrg -Level root | Get-UcsOrg -Name $spt_org_name -LimitScope | Get-UcsWwnPool -Name $cur_vhba_props.wwpnpool.name -LimitScope | Remove-UcsWwnPool -force
    
}

Get-UcsOrg -Level root | Get-UcsOrg -Name $spt_org_name -LimitScope | Get-UcsWwnPool -Name $spt_wwnn_pool_name -LimitScope | Remove-UcsWwnPool -force

Get-UcsOrg -Level root | Get-UcsOrg -Name $spt_org_name -LimitScope | Get-UcsUuidSuffixPool -Name $spt_uuid_pool_name -LimitScope | Remove-UcsUuidSuffixPool -force

Get-UcsOrg -Level root | Get-UcsOrg -Name $spt_org_name -LimitScope | Get-UcsBootPolicy -Name $spt_boot_policy_name -LimitScope | Remove-UcsBootPolicy -force

Complete-UcsTransaction
