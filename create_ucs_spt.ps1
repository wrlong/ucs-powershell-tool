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
#echo $ucsm_ip
#echo $ucsm_user
#echo $ucsm_pw
#echo $config_file
#

# | Get-UcsOrg -Name "HCA" -LimitScope |

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

##
## Create LAN Pools and templates
##

# Iterate through vnics, creating templates and pools
$spt_vnics.Keys | % { 
    $cur_vnic_name = $_
    $cur_vnic_props = $spt_vnics.Item($_)

    ## Create Mac Pool

    $mo = Get-UcsOrg -Level root | Get-UcsOrg -Name $spt_org_name -LimitScope |  Add-UcsMacPool -AssignmentOrder "sequential" -Descr "" -Name $cur_vnic_props.macpool.name -PolicyOwner "local"
    $mo_1 = $mo | Add-UcsMacMemberBlock -From $cur_vnic_props.macpool.range.split("-")[0] -To $cur_vnic_props.macpool.range.split("-")[1] 

    # Create network policy
    #$mo = Get-UcsOrg -Level root | Get-UcsOrg -Name $spt_org_name -LimitScope |  Add-UcsNetworkControlPolicy -Cdp "enabled" -Descr "" -MacRegisterMode "only-native-vlan" -Name $cur_vnic_props.network_policy -PolicyOwner "local" -UplinkFailAction "link-down"
    #$mo_1 = $mo | Add-UcsPortSecurityConfig -ModifyPresent -Descr "" -Forge "allow" -Name "" -PolicyOwner "local"

    # Create QoS policy
    $mo = Get-UcsOrg -Level root | Get-UcsOrg -Name $spt_org_name -LimitScope |  Add-UcsQosPolicy -Descr "" -Name $cur_vnic_props.qos_policy.name -PolicyOwner "local"
    $mo_1 = $mo | Add-UcsVnicEgressPolicy -ModifyPresent -Burst 10240 -HostControl "none" -Name "" -Prio "platinum" -Rate $cur_vnic_props.qos_policy.rate

    # Build vnic template
    $mo = Get-UcsOrg -Level root | Get-UcsOrg -Name $spt_org_name -LimitScope |  Add-UcsVnicTemplate -Descr "" -IdentPoolName $cur_vnic_props.macpool.name -Mtu $cur_vnic_props.mtu -Name $cur_vnic_name -NwCtrlPolicyName $cur_vnic_props.network_policy -PinToGroupName "" -PolicyOwner "local" -QosPolicyName $cur_vnic_props.qos_policy.name -StatsPolicyName "default" -SwitchId $cur_vnic_props.switch_id -TemplType $cur_vnic_props.template_type
    $cur_vlan_count = 1
    foreach ($vlan in $cur_vnic_props.vlans) { 
        if ($cur_vlan_count -eq $cur_vnic_props.vlans.length) {
            $mo_1 = $mo | Add-UcsVnicInterface -ModifyPresent -DefaultNet "yes" -Name $vlan
        }
        else {
            $mo_1 = $mo | Add-UcsVnicInterface -ModifyPresent -DefaultNet "no" -Name $vlan
        }
    $cur_vlan_count += 1
    }
}

##
## Create SAN Pools and templates
##

# Iterate through vhbas, creating templates and pools
$spt_vhbas.Keys | % { 
    $cur_vhba_name = $_
    $cur_vhba_props = $spt_vhbas.Item($_)
    
    ## Create WWPN Pool
    $mo = Get-UcsOrg -Level root | Get-UcsOrg -Name $spt_org_name -LimitScope |  Add-UcsWwnPool -AssignmentOrder "sequential" -Descr "" -Name $cur_vhba_props.wwpnpool.name -PolicyOwner "local" -Purpose "port-wwn-assignment"
$mo_10 = $mo | Add-UcsWwnMemberBlock -From $cur_vhba_props.wwpnpool.range.split("-")[0] -To $cur_vhba_props.wwpnpool.range.split("-")[1]

    # Build vhba template
    $mo = Get-UcsOrg -Level root | Get-UcsOrg -Name $spt_org_name -LimitScope |  Add-UcsVhbaTemplate -Descr "" -IdentPoolName $cur_vhba_props.wwpnpool.name -MaxDataFieldSize 2048 -Name $cur_vhba_name -PinToGroupName "" -PolicyOwner "local" -QosPolicyName "" -StatsPolicyName "default" -SwitchId $cur_vhba_props.switch_id -TemplType $cur_vhba_props.template_type
    $mo_12 = $mo | Add-UcsVhbaInterface -ModifyPresent -Name $cur_vhba_props.vsans[0]
}

# Create boot policy
#
# Boot from SAN

$mo = Get-UcsOrg -Level root | Get-UcsOrg -Name $spt_org_name -LimitScope |  Add-UcsBootPolicy -Descr "" -EnforceVnicName "yes" -Name $spt_boot_policy_name -PolicyOwner "local" -RebootOnUpdate "no"
$mo_17 = $mo | Add-UcsLsbootStorage -ModifyPresent -Order "1"
$mo_17_1 = $mo_17 | Add-UcsLsbootSanImage -Type "primary" -VnicName $spt_boot_policy_primary_vhba_name
$mo_17_1_1 = $mo_17_1 | Add-UcsLsbootSanImagePath -Lun 0 -Type "primary" -Wwn $spt_boot_policy_primary_vhba_primary_target
$mo_17_1_2 = $mo_17_1 | Add-UcsLsbootSanImagePath -Lun 0 -Type "secondary" -Wwn $spt_boot_policy_primary_vhba_secondary_target
$mo_18_2 = $mo_17 | Add-UcsLsbootSanImage -Type "secondary" -VnicName $spt_boot_policy_secondary_vhba_name
$mo_18_2_1 = $mo_18_2 | Add-UcsLsbootSanImagePath -Lun 0 -Type "primary" -Wwn $spt_boot_policy_secondary_vhba_primary_target
$mo_18_2_2 = $mo_18_2 | Add-UcsLsbootSanImagePath -Lun 0 -Type "secondary" -Wwn $spt_boot_policy_secondary_vhba_secondary_target

##
## Create server policies and pools
## 

# Create server pool
#$mo = Get-UcsOrg -Level root | Get-UcsOrg -Name $spt_org_name -LimitScope |  Add-UcsServerPool -Descr "OS_build_svr_pool" -Name "OS_build_servers" -PolicyOwner "local"
#$mo_1 = $mo | Add-UcsComputePooledSlot -ModifyPresent -RackId "1" -SlotId 1

# Create server qual policy
#$mo = Get-UcsOrg -Level root | Get-UcsOrg -Name $spt_org_name -LimitScope |  Add-UcsServerPoolQualification -Descr "" -Name "OS_build_qual_01" -PolicyOwner "local"
#$mo_1 = $mo | Add-UcsRackQualification -MaxId 1 -MinId 1

# create server pool policy
#$mo = Get-UcsOrg -Level root | Get-UcsOrg -Name $spt_org_name -LimitScope |  Add-UcsServerPoolPolicy -Descr "" -Name "OS_build_svr_pol" -PolicyOwner "local" -PoolDn "org-root/compute-pool-OS_build_servers" -Qualifier "OS_build_qual_01"

# Create UUID pool
$mo = Get-UcsOrg -Level root | Get-UcsOrg -Name $spt_org_name -LimitScope |  Add-UcsUuidSuffixPool -AssignmentOrder "sequential" -Descr "" -Name $spt_uuid_pool_name -PolicyOwner "local" -Prefix "derived"
$mo_14 = $mo | Add-UcsUuidSuffixBlock -From $spt_uuid_pool_range.split("=")[0] -To $spt_uuid_pool_range.split("=")[1] 

# Create WWNN pool
$mo = Get-UcsOrg -Level root | Get-UcsOrg -Name $spt_org_name -LimitScope |  Add-UcsWwnPool -AssignmentOrder "sequential" -Descr "" -Name $spt_wwnn_pool_name -PolicyOwner "local" -Purpose "node-wwn-assignment"
$mo_11 = $mo | Add-UcsWwnMemberBlock -From $spt_wwnn_pool_range.split("-")[0]-To $spt_wwnn_pool_range.split("-")[1]

# Create boot policy (PXE)
#$mo = Get-UcsOrg -Level root | Get-UcsOrg -Name $spt_org_name -LimitScope |  Add-UcsBootPolicy -Descr "OS_build_boot_pol" -EnforceVnicName "no" -Name "OS_build_pxe_pol" -PolicyOwner "local" -RebootOnUpdate "no"
#$mo_15 = $mo | Add-UcsLsbootLan -ModifyPresent -Order "2" -Prot "pxe"
#$mo_15_1 = $mo_15 | Add-UcsLsbootLanImagePath -BootIpPolicyName "" -ISCSIVnicName "" -ImgPolicyName "" -ImgSecPolicyName "" -ProvSrvPolicyName "" -Type "primary" -VnicName "eth0"
#$mo_16 = $mo | Add-UcsLsbootVirtualMedia -Access "read-only" -Order "1"

# Complete UCS transaction
#$mo = Get-UcsOrg -Level root | Add-UcsIpPool -AssignmentOrder "sequential" -Descr "OS_build_KVM" -Name "OS_build_kvm_ips" -PolicyOwner "local"
#$mo_1 = $mo | Add-UcsIpPoolBlock -DefGw "172.19.121.1" -From "172.19.121.101" -PrimDns "171.70.168.183" -SecDns "64.102.6.247" -To "172.19.121.101"

## Create Service Profile Template
$mo = Get-UcsOrg -Level root | Get-UcsOrg -Name $spt_org_name -LimitScope |  Add-UcsServiceProfile -type updating-template -Name $spt_name -BootPolicyName $spt_boot_policy_name -HostFwPolicyName $spt_firmware_policy_name -IdentPoolName $spt_uuid_pool_name -ExtIPPoolName "default" -ExtIPState "pooled"
#$mo_0 = $mo | Add-UcsServerPoolAssignment -ModifyPresent -Name "OS_build_blades" 
$spt_vnics.Keys | % { 
    $mo_19 = $mo | Add-UcsVnic -Name $_ -NwTemplName $_
}
$spt_vhbas.Keys | % { 
    $mo_19 = $mo | Add-UcsVhba -Name $_ -NwTemplName $_
}
$mo_20 = $mo | Add-UcsVnicFcNode -IdentPoolName $spt_wwnn_pool_name

Complete-UcsTransaction
