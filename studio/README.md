# Sidewinder Studio Infrastructure

This folder is Sidewinder Games' operator guide and Terraform root for the
studio's AWS infrastructure: Perforce (Helix Core) for source control and
Unreal Horde for CI/CD.

For the original architectural decisions and cost analysis, see
[PLAN.md](./PLAN.md). For the Tailscale investigation that will eventually
replace the IP whitelist below, see [TAILSCALE.md](./TAILSCALE.md).

## Architecture at a glance

| Component | Where | Notes |
| --- | --- | --- |
| Perforce server (p4d 2025.2) | EC2 t4g.medium, us-east-1a | Public EIP, port 1666 gated by IP whitelist |
| P4 server URL | p4.studio.sidewinder.dev | A record to EIP, ACM wildcard cert for ssl |
| Horde server | EC2 t4g.medium + Mongo + Redis via Docker Compose | Behind external ALB on horde.studio.sidewinder.dev |
| Horde build agents | ASG, Spot c7a.xlarge family, min 0 max 3 | AwsAsg fleet manager scales on demand |
| Horde artifact storage | S3 with 7-day Standard then Glacier-IR lifecycle | |
| IaC | This repo, branch `sidewinder` | Spacelift-managed, OpenTofu 1.10 |
| Spacelift account | sidewinder-games.app.us.spacelift.io | |
| AWS account | 622709063820, us-east-1 | |

Four Terraform stacks, three of them in this folder:

| Stack | Folder | Purpose |
| --- | --- | --- |
| (manual local) | `spacelift-bootstrap/` | Creates the IAM role Spacelift assumes. Apply once locally. |
| Sidewinder Admin | `spacelift/` | Spacelift admin stack: creates and configures the other two stacks. |
| Sidewinder Phase 1 - Perforce | `phase1-perforce/` | P4 server, VPC, DNS, ACM cert. |
| Sidewinder Phase 2 - Horde | `phase2-horde/` | Horde host, S3 storage, ALB, agent ASG. |

## Onboarding and offboarding

See [ONBOARDING.md](./ONBOARDING.md) for the full user lifecycle
(Google Workspace + Tailscale + Horde OIDC + Perforce), including the
target state where adding a Google Workspace account is most of the
work and offboarding cascades from suspending it.

The very short version, current state:

1. **IP whitelist** (going away once the Tailscale relay is in place):
   edit `TF_VAR_allowed_p4_cidrs` on the admin stack in Spacelift,
   trigger admin then Phase 1.
2. **P4 user**:
   ```powershell
   $P4 = "ssl:p4.studio.sidewinder.dev:1666"
   p4 -p $P4 -u ccasteel user -f firstname.lastname
   p4 -p $P4 -u ccasteel passwd firstname.lastname
   p4 -p $P4 -u ccasteel group unlimited_timeout   # add them in editor
   p4 -p $P4 -u ccasteel group dev_team            # add them in editor
   ```

Offboarding:
```powershell
p4 -p $P4 -u ccasteel logout -a firstname.lastname
p4 -p $P4 -u ccasteel user -d -f firstname.lastname
```

For their workstation setup, send them the "New user setup brief"
section of ONBOARDING.md.

For their per-server P4 client setup on their machine, point them at the
client-isolation guide section below.

## Client-side P4 isolation (multiple servers on one machine)

If a user runs P4 against multiple servers on one workstation, isolate
Sidewinder using `P4CONFIG` so its credentials don't clobber the others.

One-time, machine-wide:

```powershell
p4 set P4CONFIG=.p4config
```

In each project root, drop a `.p4config` file. For Sidewinder:

```
P4PORT=ssl:p4.studio.sidewinder.dev:1666
P4USER=<their-p4-username>
P4TRUST=C:\Users\<them>\.p4trust.sidewinder
P4TICKETS=C:\Users\<them>\.p4tickets.sidewinder
P4CLIENT=<their-username>_<machine>_<project>
```

`P4TRUST` and `P4TICKETS` overrides keep Sidewinder's SSL fingerprint and
login ticket separate from any other server's. After `cd`ing in:

```powershell
p4 trust -y
p4 login
p4 client       # opens editor; set Root to a local path, save
```

## Common operations

### Trigger a stack from your terminal (instead of clicking in Spacelift UI)

Spacelift's API can trigger runs:

```powershell
$env:Path = [Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [Environment]::GetEnvironmentVariable("Path","User")
# Set SPACELIFT_API_KEY_ID/SECRET from a personal API key in Spacelift's UI
spacectl stack trigger --id sidewinder-phase1-perforce
```

Most of the time the Spacelift UI is faster.

### Retrieve a secret from AWS Secrets Manager

```powershell
aws secretsmanager get-secret-value `
  --region us-east-1 `
  --secret-id cgd-p4-server-AdminPassword `
  --query SecretString --output text
```

Secrets created by the stacks:

| Secret name | Holds |
| --- | --- |
| `cgd-p4-server-AdminUsername` | Currently `ccasteel`; documents who the admin is |
| `cgd-p4-server-AdminPassword` | Password for the admin user |
| `cgd-p4-server-ServiceAccountPassword` | Password for the `super` SDP service account |
| `sidewinder/ghcr-credentials` | GitHub PAT (read:packages) for pulling the Horde server image from ghcr.io |
| `sidewinder-unreal-horde-mongo-password-*` | Auto-generated Mongo root password used by the Horde host |

### SSM into the P4 or Horde host

Either via the AWS Console (EC2 -> Instances -> Connect -> Session Manager)
or via the CLI:

```powershell
$INST = aws ec2 describe-instances `
  --region us-east-1 `
  --filters "Name=tag:Name,Values=cgd-p4-server*" "Name=instance-state-name,Values=running" `
  --query 'Reservations[0].Instances[0].InstanceId' --output text
aws ssm start-session --target $INST --region us-east-1
```

Replace the tag filter with `sidewinder-unreal-horde-host*` for the Horde
host.

### Run a script on the P4 server as the perforce OS user

P4 commands need the SDP environment. From inside an SSM session:

```bash
sudo -u perforce bash -c "source /p4/common/bin/p4_vars 1 && p4 users"
```

Note: `p4 login` from a fresh SSM session needs to read/write
`/p4/1/.p4tickets`, which is owned by `perforce:perforce`. If you ever see
"Permission denied" on `.p4tickets`, check ownership.

### Inspect what's in the agent ASG

```powershell
aws autoscaling describe-auto-scaling-groups `
  --region us-east-1 `
  --query 'AutoScalingGroups[?contains(AutoScalingGroupName, `horde_agents`)].{Name:AutoScalingGroupName,Desired:DesiredCapacity,Min:MinSize,Max:MaxSize,Instances:length(Instances)}' `
  --output table
```

## Spacelift workflow

- Pushes to the `sidewinder` branch on
  `github.com/SidewinderGames/cloud-game-development-toolkit` trigger any
  stack whose `project_root` path was touched in the commit.
- Stacks default to `autodeploy = false`, so runs wait at "Unconfirmed"
  until a human clicks Confirm in the UI.
- The admin stack creates and configures the two child stacks. Editing
  `studio/spacelift/main.tf` and pushing is how you add new env vars,
  rename a stack, change Terraform version, etc.
- Phase 2's TF_VAR_vpc_id, TF_VAR_public_subnet_ids, TF_VAR_certificate_arn,
  TF_VAR_p4_super_user_*_secret_arn come from Phase 1's outputs via
  `spacelift_stack_dependency_reference`. No copy-paste between stacks.
- State lives in Spacelift's managed backend (no S3 + DynamoDB to set up).

## Where state goes when things go wrong

- **Spacelift run fails** -> click into the run, scroll to the error in
  the streaming log. Most failures are AWS API errors with descriptive
  messages.
- **Cloud-init fails on EC2** -> SSM into the instance, check
  `/var/log/cloud-init-output.log`.
- **Horde container won't start** -> SSM into the Horde host, run
  `sudo docker compose -f /etc/horde/docker-compose.yml logs --tail=200`.
- **Agent doesn't enroll** -> check the SSM RunCommand association in the
  AWS Console (Systems Manager -> Run Command -> Command history), filter
  to the `*-AnsibleRun` document; failed runs include the Ansible output.

## Roadmap

In rough priority order:

1. **Tailscale subnet router to replace IP whitelist** -- see
   [TAILSCALE.md](./TAILSCALE.md). Largest immediate quality-of-life win.
2. **Daily P4 checkpoint backup to S3** with Glacier Deep Archive
   lifecycle after 30 days.
3. **Mongo dump cron on the Horde host** writing nightly to the Horde S3
   storage bucket.
4. **Horde authentication** -- replace `Anonymous` with OIDC against the
   studio's Google Workspace.
5. **Warm-AMI workflow for build agents** if cold p4 sync of the 256 GB
   project becomes painful. Procedure documented in PLAN.md section 7.
6. **Tighten the Spacelift role's trust policy** -- swap
   `sidewinder-games@*` for explicit
   `sidewinder-games@<integration-id>@<stack-slug>@*` patterns.
7. **Move off AWS root credentials** -- set up IAM Identity Center / SSO
   for human operators. Root keys should never be in daily use.
