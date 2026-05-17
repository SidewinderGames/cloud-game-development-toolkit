<powershell>
# Enlarge root file system to fill the EBS volume.
(Get-PSDrive -PSProvider FileSystem).Name | ForEach-Object { Resize-Partition -DriveLetter $_ -Size $(Get-PartitionSupportedSize -DriveLetter $_).SizeMax -ErrorAction SilentlyContinue }

# Wait for, format if needed, and mount the per-pool data volume that the
# Horde server's AwsAsgWithDataVolumes fleet strategy attaches via the ASG
# launching lifecycle hook. The hook holds the instance in Pending:Wait
# until the volume is attached, so this loop usually finds the disk on the
# first iteration. Idempotent: if the volume was previously formatted, we
# skip the format step and just assign the drive letter.
$dataDeviceTimeoutSec = 300
$workspaceDrive = "D"
$workspaceLabel = "HordeData"
$elapsed = 0
$disk = $null
while ($elapsed -lt $dataDeviceTimeoutSec) {
    Update-HostStorageCache
    # Pick the first non-boot non-system disk - on Windows, the EBS data
    # volume that AWS attached after the root volume will be Disk 1+.
    $disk = Get-Disk | Where-Object { $_.Number -gt 0 -and $_.BusType -ne 'USB' -and $_.IsBoot -eq $false -and $_.IsSystem -eq $false } | Select-Object -First 1
    if ($disk) { break }
    Start-Sleep -Seconds 2
    $elapsed += 2
}
if ($disk) {
    if ($disk.PartitionStyle -eq 'RAW') {
        Initialize-Disk -Number $disk.Number -PartitionStyle GPT -Confirm:$false
        New-Partition -DiskNumber $disk.Number -UseMaximumSize -DriveLetter $workspaceDrive |
            Format-Volume -FileSystem NTFS -NewFileSystemLabel $workspaceLabel -Confirm:$false -Force | Out-Null
    } else {
        # Existing partition from a previous run / a snapshot-restored volume.
        # Re-assign D: in case the previous owner kept a different letter.
        $part = Get-Partition -DiskNumber $disk.Number | Where-Object { $_.Type -ne 'Reserved' } | Select-Object -First 1
        if ($part -and -not $part.DriveLetter) {
            $part | Set-Partition -NewDriveLetter $workspaceDrive
        }
    }
}

# Install the necessary dotnet runtime
choco install -y --no-progress dotnet-${dotnet_runtime_version}-runtime

# Windows doesn't support RBN so we do it manually
# NetBIOS name max length is 15 bytes so we need to truncate the instance id
$instanceid = @(Get-EC2InstanceMetadata -Category InstanceId)[0].Substring(2, 15)
Rename-Computer $instanceid

# Install Horde agent onto the persistent data volume when available so a
# subsequent boot can short-circuit reinstall. Falls back to C: when no data
# volume is attached (legacy plain-ASG path).
if (Test-Path ("$($workspaceDrive):\")) {
    $hordedir = "$($workspaceDrive):\Horde"
} else {
    $hordedir = "C:\Horde"
}
if (-not (Test-Path $hordedir)) {
    New-Item -ItemType Directory -Path $hordedir | Out-Null
}

Invoke-WebRequest -Uri https://${fully_qualified_domain_name}/api/v1/tools/horde-agent?action=Zip -OutFile C:\HordeAgent.zip
Expand-Archive -LiteralPath C:\HordeAgent.zip -DestinationPath $hordedir -Force

@{
    "Horde" = @{
        "Name" = $instanceid;
        "EnableAwsEc2Support" = $true;
        "WorkingDir" = "$($workspaceDrive):\HordeWork";
        "Ephemeral" = $true;
    };
} | ConvertTo-Json -depth 100 | Out-File "$hordedir\appsettings.User.json"

%{if p4_trust_bucket != null}
Read-S3Object -BucketName ${p4_trust_bucket} -Key agent/.p4trust -File $hordedir\p4trust.txt
[Environment]::SetEnvironmentVariable("P4TRUST", "$hordedir\p4trust.txt", "Machine")
%{endif}

& "$hordedir\HordeAgent.exe" SetServer -Default -Url="https://${fully_qualified_domain_name}"
& "$hordedir\HordeAgent.exe" Service Install -Start=true
</powershell>
