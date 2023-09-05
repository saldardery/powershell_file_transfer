
$hostname = Read-Host -Prompt "Enter the IP/FQDN of the SDDC manager"
$username = Read-Host -Prompt "Enter the username of the SDDC manager"

function sendfile ($filename)
{
scp.exe  $filename $username"@"$hostname":/home/vcf"
}

function sendfolder
{
scp.exe ./testfolder/* $username"@"$hostname":/home/vcf"
}

#$fn= Read-Host -Prompt "Enter filename"
#sendfile($fn)
sendfolder