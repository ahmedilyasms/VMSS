$resourceGroup = 'epsimagesrg'
$vmName = 'AIDF179DF'
$diskSizeGb = 127
$adminUsername = 'ahmedilyas'
$adminPassword = '<I don't think so!>'
$imageName = 'AIDFCITest179.vmss.img'
$scaleSetName = 'DevFabricP0Emph.vmss'
$vmSku = 'Standard_DS3_v2'

$storageAccount = 'epsimages'
$vhdUrl = 'https://epsimages.blob.core.windows.net/vhds/MMS.VSTS.179.DevFabric.2.vhd'
$osType = 'Windows'

#az login --use-device-code
#az account show
#az account set --subscription 1bc2a10c-15c1-4470-9b54-9c8cf0878947

#Write-Host "Creating the vm..."
#az vm create --resource-group $resourceGroup --name $vmName --image $vhdUrl --os-type $osType --os-disk-size-gb $diskSizeGb --use-unmanaged-disk --admin-username $adminUsername --admin-password $adminPassword --storage-account $storageAccount --size $vmSku

#Write-Host "Stopping the vm..."
#az vm stop --resource-group $resourceGroup --name $vmName

#Write-Host "Deallocating the vm..."
#az vm deallocate --resource-group $resourceGroup --name $vmName

#Write-Host "Converting the vm..."
#az vm convert --resource-group $resourceGroup --name $vmName

#Write-Host "Starting the vm..."
#az vm start --resource-group $resourceGroup --name $vmName

#RDP in and extend the disk
#diskpart 
#list vol
#select vol 1
#extend size 132000

#Install any additional software on the VM
#Run the provisioner script

# For warmup: write to c:\warmup.ps1

#shutdown /r

#C:\windows\system32\sysprep\sysprep.exe /generalize /oobe /shutdown

#wait until VM has stopped

#Write-Host "Deallocating VM"
#az vm deallocate --resource-group $resourceGroup --name $vmName

#Write-Host "generalizing VM"
#az vm generalize --resource-group $resourceGroup --name $vmName

#Write-Host "Creating VM image"
#az image create --resource-group $resourceGroup --name $imageName --source $vmName

#Don't delete. This takes a long time sometimes and can hang.
<#Write-Host "Deleting VM Image"
az vm delete --resource-group $resourceGroup --name $vmName#>

#Write-Host "VMSS creation..."
#az vmss create --resource-group $resourceGroup --name $scaleSetName --image $imageName --admin-username $adminUsername --admin-password $adminPassword --vm-sku $vmSku --instance-count 16 --disable-overprovision --upgrade-policy-mode manual --load-balancer '""' --ephemeral-os-disk true --os-disk-caching readonly

#az vmss extension set --vmss-name $scaleSetName --resource-group $resourceGroup --name CustomScriptExtension --version 1.9  --publisher Microsoft.Compute --settings '{ \"FileUris\":[\"https://raw.githubusercontent.com/ahmedilyasms/VMSS/master/imagewarmuperror.ps1\"], \"commandToExecute\": \"Powershell.exe -ExecutionPolicy Unrestricted -File imagewarmuperror.ps1\" }'
#Write-Host "Complete"
