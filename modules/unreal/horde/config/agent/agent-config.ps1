<powershell>
# Enlarge all file systems to fill the EBS volumes
(Get-PSDrive -PSProvider FileSystem).Name | ForEach-Object { Resize-Partition -DriveLetter $_ -Size $(Get-PartitionSupportedSize -DriveLetter $_).SizeMax -ErrorAction SilentlyContinue }

# Install the necessary dotnet runtime
choco install -y --no-progress dotnet-${dotnet_runtime_version}-runtime

# Windows doesn't support RBN so we do it manually
# NetBIOS name max length is 15 bytes so we need to truncate the instance id
$instanceid = @(Get-EC2InstanceMetadata -Category InstanceId)[0].Substring(2, 15)
Rename-Computer $instanceid

# Download and unzip the agent
$hordedir = "C:\Horde"
Invoke-WebRequest -Uri https://${fully_qualified_domain_name}/api/v1/tools/horde-agent?action=Zip -OutFile C:\HordeAgent.zip
Expand-Archive -LiteralPath C:\HordeAgent.zip -DestinationPath $hordedir -Force

# Write the config file
@{
    "Horde" = @{
        "Name" = $instanceid;
        "EnableAwsEc2Support" = $true;
    };
} | ConvertTo-Json -depth 100 | Out-File "$hordedir\appsettings.User.json"

# If necessary, fetch the p4trust file
%{if p4_trust_bucket != null}
Read-S3Object -BucketName ${p4_trust_bucket} -Key agent/.p4trust -File $hordedir\p4trust.txt
[Environment]::SetEnvironmentVariable("P4TRUST", "$hordedir\p4trust.txt", "Machine")
%{endif}

# Configure and start the agent
& "$hordedir\HordeAgent.exe" SetServer -Default -Url="https://${fully_qualified_domain_name}"

# Install AND start the agent service. Previous version used -Start=false +
# a scheduled reboot to apply the Rename-Computer change; the reboot was
# unreliable (script sometimes exited before the shutdown command), so the
# agent service would sit installed-but-stopped indefinitely. Starting it
# now means the agent registers with Horde immediately; the hostname
# rename takes effect on the next routine reboot, which is fine because
# the agent reports its identity via appsettings.User.json "Name", not
# the OS hostname.
& "$hordedir\HordeAgent.exe" Service Install -Start=true

# Give the agent a chance to register and auto-enroll with Horde before
# this script returns. cloud-init signals "done" to AWS as soon as we
# exit, and if the instance is being launched into a warm pool, AWS
# will then stop the OS. Without this wait the registration RPC may
# get cut off mid-flight, the agent never gets a record in Mongo, and
# the warm pool ends up with an unregistered stopped instance that
# doesn't satisfy HasAgents. 90s is enough for the agent's RPC retry
# loop (10s intervals) to complete a successful RegisterAgent and the
# server-side EnrollmentService.AddAsync to auto-approve.
Start-Sleep -Seconds 90
</powershell>
