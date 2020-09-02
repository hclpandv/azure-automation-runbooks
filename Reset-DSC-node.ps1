param (
    [parameter(Mandatory=$false)]
    [string]$resourceGroupName = 'RG_Vikas.Pandey',
    [string]$automationAccountName = 'auto-viki-dev-01',
    [parameter(Mandatory=$true)]
    [string]$nodeName,
    [string]$nodeConfig = 'viki_testconfig.localhost'
)

$connectionName = "AzureRunAsConnection"
$servicePrincipalConnection = Get-AutomationConnection -Name 'AzureRunAsConnection' 
try {     
    "Logging in to Azure..."
    Connect-AzAccount `
        -ServicePrincipal `
        -TenantId $servicePrincipalConnection.TenantId `
        -ApplicationId $servicePrincipalConnection.ApplicationId `
        -CertificateThumbprint $servicePrincipalConnection.CertificateThumbprint 
}
catch {
    if (!$servicePrincipalConnection) {
        $ErrorMessage = "Connection $connectionName not found."
        throw $ErrorMessage
    }
    else {
        Write-Error -Message $_.Exception
        throw $_.Exception
    }
}


# DSC Node details
Write-Output "Checking DSC node details"
Get-AzAutomationDscNode -ResourceGroupName $resourceGroupName -AutomationAccountName $automationAccountName | ft -wrap

# Check if the node is up and running
$VmPowerStatus = ((get-azvm -ResourceGroupName $resourceGroupName -Name $nodeName -Status).Statuses | where{$_.code -like "*PowerState*"}).displaystatus
if($VmPowerStatus -eq "VM running"){
    Write-Output "Node $nodeName is running, status '$VmPowerStatus'"
}
else{
    Write-Output "Node $nodeName is not running and current state is '$VmPowerStatus', please troubleshoot further, exiting"
    exit
}

# Check if the node status failing
$nodeStatus =  (Get-AzAutomationDscNode -ResourceGroupName $resourceGroupName -AutomationAccountName $automationAccountName -Name $nodeName).Status
$nodeID = (Get-AzAutomationDscNode -ResourceGroupName $resourceGroupName -AutomationAccountName $automationAccountName -Name $nodeName).Id

if($nodeStatus -eq "Failed"){
    Write-Output "DSC status for the node $nodeName is 'Failed'"
    Write-Output "STEP1: Unregister the node"
    Unregister-AzAutomationDscNode -ResourceGroupName $resourceGroupName `
                                   -AutomationAccountName $automationAccountName `
                                   -Id $nodeID `
                                   -Verbose -Force
    if($?){Write-Output "DSC Node $nodeName unregistered. operation successful"}

    Write-Output "STEP2: Uninstall the DSC VM Extension"
    Get-AzVMExtension -ResourceGroupName $resourceGroupName -VMName $nodeName `
    | Where-Object {$_.Name -eq "Microsoft.Powershell.DSC"} `
    | Remove-AzVMExtension -Force
    if($?){Write-Output "DSC VM Extemsion removal successful"}

    #Write-Output "STEP3: Reboot the Node VM"
    #Get-AzVM -ResourceGroupName $resourceGroupName -Name $nodeName | Restart-AzVM -Verbose


    Write-Output "STEP3: Re-Register the DSC Node"
    Register-AzAutomationDscNode -AutomationAccountName $automationAccountName `
                                 -AzureVMName $nodeName `
                                 -ResourceGroupName $resourceGroupName `
                                 -NodeConfigurationName $nodeConfig `
                                 -ConfigurationMode 'ApplyAndAutocorrect' `
                                 -RebootNodeIfNeeded $true
    if($?){Write-Output "DSC node $nodeName registered again with config $nodeConfig"}
}
else{
    Write-Output "DSC status for the node $nodeName is NOT 'Failed',no need for re-register, please troubleshoot it further, exiting"
    exit
}
