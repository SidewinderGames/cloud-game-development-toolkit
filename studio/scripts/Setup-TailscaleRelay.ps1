<#
.SYNOPSIS
  Bootstrap the Sidewinder tailnet for the AWS subnet router and provision
  the auth key the relay will use to join.

.DESCRIPTION
  - Merges tag:subnet-router (owned by autogroup:admin), an autoApprover for
    the VPC CIDR, and a Tailscale SSH rule into the existing tailnet ACL.
  - Generates a non-reusable, pre-authorized, 90-day auth key bound to
    tag:subnet-router.
  - Stores the auth key in AWS Secrets Manager (creates the secret if it
    doesn't exist; updates the value if it does).

  Idempotent: re-running merges the same tag/autoApprover entries without
  duplicating them. The auth key is always freshly generated, and the SM
  secret is updated to the new value (the prior key is left valid in
  Tailscale until manually revoked).

.PARAMETER ApiToken
  Tailscale API access token. Generate one at:
  https://login.tailscale.com/admin/settings/keys -> Generate access token.
  Needed scopes: policy_file write + auth_keys write (the default scope on a
  personal access token covers both).

.PARAMETER Tailnet
  Tailnet identifier as it appears in admin URL. Defaults to sidewinder.games.

.PARAMETER VpcCidr
  Studio VPC CIDR to advertise. Must match var.tailscale_advertise_routes
  in studio/phase1-perforce.

.PARAMETER AwsRegion
  AWS region for the Secrets Manager secret. Defaults to us-east-1.

.PARAMETER SecretName
  Name of the secret to create/update. Must match the value Phase 1's
  var.tailscale_auth_key_secret_name expects.

.PARAMETER RouterTag
  Tailnet tag the relay node is assigned. Must match
  var.tailscale_relay_tags in Phase 1.

.EXAMPLE
  .\Setup-TailscaleRelay.ps1 -ApiToken (Read-Host -Prompt 'Tailscale API token' -AsSecureString | ConvertFrom-SecureString -AsPlainText)
#>

[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)]
  [string]$ApiToken,

  [string]$Tailnet     = "sidewinder.games",
  [string]$VpcCidr     = "10.40.0.0/16",
  [string]$AwsRegion   = "us-east-1",
  [string]$SecretName  = "sidewinder/tailscale-auth-key",
  [string]$RouterTag   = "tag:subnet-router"
)

$ErrorActionPreference = "Stop"

$headers = @{
  Authorization = "Bearer $ApiToken"
  Accept        = "application/json"
}
$base = "https://api.tailscale.com/api/v2/tailnet/$Tailnet"

Write-Host "==> Fetching current ACL for tailnet '$Tailnet'..."
$resp = Invoke-WebRequest -Uri "$base/acl" -Headers $headers -Method Get
# -AsHashtable so we can mutate keys reliably; required for PS7+ behavior.
$acl  = $resp.Content | ConvertFrom-Json -AsHashtable -Depth 50

# Ensure top-level keys exist as plain hashtables / arrays.
if (-not $acl.ContainsKey("tagOwners"))     { $acl["tagOwners"]     = @{} }
if (-not $acl.ContainsKey("autoApprovers")) { $acl["autoApprovers"] = @{} }
if (-not $acl.ContainsKey("ssh"))           { $acl["ssh"]           = @() }
if (-not $acl["autoApprovers"].ContainsKey("routes")) {
  $acl["autoApprovers"]["routes"] = @{}
}

Write-Host "==> Merging $RouterTag tagOwner + autoApprover + SSH rule..."

# tagOwners
$acl["tagOwners"][$RouterTag] = @("autogroup:admin")

# autoApprovers.routes
$acl["autoApprovers"]["routes"][$VpcCidr] = @($RouterTag)

# SSH rule (admin -> relay, idempotent: skip if equivalent rule already present)
$existingSsh = @($acl["ssh"]) | Where-Object {
  ($_.dst -contains $RouterTag) -and ($_.src -contains "autogroup:admin")
}
if (-not $existingSsh) {
  $newRule = @{
    action = "accept"
    src    = @("autogroup:admin")
    dst    = @($RouterTag)
    users  = @("root", "ec2-user")
  }
  $acl["ssh"] = @($acl["ssh"]) + $newRule
}

$body = $acl | ConvertTo-Json -Depth 50

Write-Host "==> Posting merged ACL..."
$putHeaders = $headers.Clone()
$putHeaders["Content-Type"] = "application/json"
Invoke-WebRequest -Uri "$base/acl" -Headers $putHeaders -Method Post -Body $body | Out-Null

Write-Host "==> Generating auth key (90 days, pre-authorized, tagged $RouterTag)..."
$keyBody = @{
  capabilities = @{
    devices = @{
      create = @{
        reusable      = $false
        ephemeral     = $false
        preauthorized = $true
        tags          = @($RouterTag)
      }
    }
  }
  expirySeconds = 7776000  # 90 days
} | ConvertTo-Json -Depth 10

$keyResp = Invoke-WebRequest -Uri "$base/keys" -Headers $putHeaders -Method Post -Body $keyBody
$keyData = $keyResp.Content | ConvertFrom-Json
$authKey = $keyData.key

if (-not $authKey) {
  throw "Auth key response did not contain a 'key' field. Raw: $($keyResp.Content)"
}

Write-Host "    Auth key id: $($keyData.id)"

Write-Host "==> Storing auth key in AWS Secrets Manager ($SecretName)..."
$existing = aws secretsmanager describe-secret --region $AwsRegion --secret-id $SecretName 2>&1
if ($LASTEXITCODE -eq 0) {
  aws secretsmanager put-secret-value `
    --region $AwsRegion `
    --secret-id $SecretName `
    --secret-string $authKey | Out-Null
  Write-Host "    Updated existing secret."
} else {
  aws secretsmanager create-secret `
    --region $AwsRegion `
    --name $SecretName `
    --secret-string $authKey `
    --description "Tailscale auth key for the Sidewinder subnet router" | Out-Null
  Write-Host "    Created secret."
}

Write-Host ""
Write-Host "DONE."
Write-Host "  ACL: tagOwners[$RouterTag], autoApprovers.routes[$VpcCidr] = [$RouterTag], SSH for admins"
Write-Host "  Auth key: stored in Secrets Manager (region=${AwsRegion}, name=${SecretName})"
Write-Host ""
Write-Host "Next: trigger the Phase 1 stack in Spacelift. The relay's user-data"
Write-Host "will read the auth key from Secrets Manager on boot and join the tailnet."
