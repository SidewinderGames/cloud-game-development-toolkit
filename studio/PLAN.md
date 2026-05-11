# Sidewinder Games CGD Toolkit Deployment Plan

This document describes how Sidewinder Games deploys a pared-down Perforce + Unreal Horde stack
on AWS using a fork of the AWS Cloud Game Development Toolkit. It targets a 5-person studio
working on a 256 GB Unreal Engine project, with monthly cost in the $130 to $200 range.

## Studio Parameters

| Setting | Value |
| --- | --- |
| Studio | Sidewinder Games |
| Root domain | sidewinder.dev (delegated NS records at registrar) |
| Delegated Route53 zone | studio.sidewinder.dev |
| Perforce server URL | p4.studio.sidewinder.dev (A record to P4 EIP) |
| Horde server URL | horde.studio.sidewinder.dev (A ALIAS to Horde ALB) |
| Wildcard ACM cert | *.studio.sidewinder.dev (DNS-validated) |
| Toolkit fork | github.com/SidewinderGames/cloud-game-development-toolkit |
| Working branch | sidewinder |
| AWS region | TBD by deployer (us-east-1 recommended) |
| Phase 1 root config | studio/phase1-perforce/ |
| Phase 2 root config | studio/phase2-horde/ |

## Architecture Summary

### Phase 1: Perforce P4 Server only

Stock perforce module with all optional services disabled.

- Single t4g.medium arm64 EC2 instance, public subnet, Elastic IP
- 500 GiB gp3 depot, 32 GiB metadata, 32 GiB logs
- Built from the existing arm64 Packer AMI template at
  assets/packer/perforce/p4-server/perforce_arm64.pkr.hcl
- No Network Load Balancer, no Application Load Balancer, no ECS cluster
- No P4 Code Review (Swarm), no P4Auth (Helix Authentication Service)
- Clients connect directly: p4 -p ssl:p4.studio.sidewinder.dev:1666

### Phase 2: Unreal Horde all-in-one fork

Significant edits to modules/unreal/horde/ to replace managed DocumentDB and ElastiCache with
self-hosted Mongo and Redis on the same EC2 host that runs Horde Server, via Docker Compose.

- Single t4g.medium arm64 EC2 host running three containers
  - ghcr.io/epicgames/horde-server:latest-bundled with network_mode host
  - mongo:7.0 bound to 127.0.0.1:27017
  - redis:7.2-alpine bound to 127.0.0.1:6379
- 30 GiB gp3 data volume for Mongo and Redis state (Horde artifacts live in S3)
- External ALB only (internal ALB removed) terminating HTTPS and gRPC
- S3 bucket for Horde artifacts and logs with aggressive 7-day lifecycle
  - Standard at 0-6 days, Standard-IA at 7-29 days, Glacier IR at 30-89 days, expire at 90 days
  - Logs expire at 30 days
- Dynamic build agents via Auto Scaling Group with mixed_instances_policy
  - 100% Spot, capacity-optimized, instance overrides c7a.xlarge / c7i.xlarge / c6a.xlarge
  - 1 TiB gp3 workspace volume per agent
  - min_size = 0 by default (defer warm AMI)
  - Horde server pool config selects AwsAsg fleet manager (the toolkit's existing
    Horde_Autoscale_Pool tag on launch templates is what AwsAsg keys on)

## Deferred Warm AMI Strategy

The user has chosen to skip the warm AMI snapshot day 1 to save ~$50/mo. Consequences:

- First agent launched into a new instance does a cold incremental p4 sync of the 256 GB project,
  taking roughly 30 to 45 minutes. Subsequent jobs on the same agent reuse the workspace.
- Each scale-out event into a brand new instance repeats the cold sync.
- Add the warm AMI later when build cadence grows. The procedure is documented in section
  "Warm AMI workflow" below; nothing in the Terraform locks us out of it.

## DNS Delegation Procedure

Before the first terraform apply:

1. In AWS Console -> Route 53 -> Hosted Zones -> Create hosted zone.
   Name: studio.sidewinder.dev, Public hosted zone.
2. Capture the 4 NS records Route53 creates.
3. At sidewinder.dev's registrar, add 4 NS records for host "studio" pointing at those 4 names.
4. Verify with: dig +short NS studio.sidewinder.dev @1.1.1.1
   Propagation is typically 10 to 30 minutes, up to 24 hours worst case.
5. Do NOT run terraform apply on Phase 1 before NS resolves; ACM DNS validation will hang.

## Phase 1 Operational Steps

1. Build the arm64 P4 Server AMI with Packer
   - Working directory: D:\Sidewinder\cloud-game-development-toolkit
   - Create assets/packer/perforce/p4-server/sidewinder.pkrvars.hcl with region, vpc_id, subnet_id
   - packer init   assets/packer/perforce/p4-server/perforce_arm64.pkr.hcl
   - packer validate -var-file=...sidewinder.pkrvars.hcl assets/packer/perforce/p4-server/perforce_arm64.pkr.hcl
   - packer build    -var-file=...sidewinder.pkrvars.hcl assets/packer/perforce/p4-server/perforce_arm64.pkr.hcl
   - Build takes 10 to 15 minutes. The Terraform config looks up the AMI by p4_al2023 prefix.

2. Apply Phase 1 Terraform
   - cd studio/phase1-perforce
   - terraform init
   - terraform plan -out=phase1.tfplan
   - terraform apply phase1.tfplan
   - Expected resources: 1 VPC, 2 public subnets, 1 IGW, 1 route table + associations,
     1 ACM wildcard cert + DNS validation records, 1 A record at p4.studio.sidewinder.dev,
     1 EC2 instance, 1 EIP, 3 EBS volumes, 1 user SG, 3 Secrets Manager secrets.

3. Post-apply setup
   - Wait 5 to 10 minutes for cloud-init / p4_configure.sh to finish (watch via SSM Session Manager).
   - Retrieve admin password from Secrets Manager.
   - From a workstation in the allowed CIDRs:
     p4 -p ssl:p4.studio.sidewinder.dev:1666 trust -y
     p4 -p ssl:p4.studio.sidewinder.dev:1666 -u perforce login
     p4 info
   - Create the 5 user accounts (p4 user -f <name>; p4 passwd <name>).
   - Create the project depot (p4 depot UnrealProject).
   - Push a smoke-test commit.

## Phase 2 Operational Steps

1. Pre-flight
   - Confirm Epic Games GitHub org membership and accept the Unreal Engine EULA.
   - Create a Classic PAT with read:packages scope on a GitHub account in the EpicGames org.
   - Store as a Secrets Manager secret in the target region with JSON shape:
     {"username":"<gh-handle>","password":"<PAT>"}
     Capture the secret ARN.

2. Apply Phase 2 Terraform
   - cd studio/phase2-horde
   - terraform init
   - terraform plan -out=phase2.tfplan
   - terraform apply phase2.tfplan
   - Expected resources: 1 EC2 Horde host, 1 EBS data volume, 1 external ALB,
     2 target groups, listeners + rules, 1 launch template, 1 ASG (min 0 max 2),
     1 S3 artifact bucket with lifecycle, 1 ANS playbook S3 bucket,
     IAM roles + policies, 1 SSM document and association,
     Route53 A ALIAS at horde.studio.sidewinder.dev.

3. Post-apply setup
   - SSH or SSM into the Horde host to verify docker compose ps shows three healthy services.
   - Browse to https://horde.studio.sidewinder.dev. Verify the Horde UI loads.
   - In Horde UI, define a pool named "linux-ue-builder" if not auto-created from server.json.
   - Trigger an empty test build to confirm an agent launches, enrolls, runs, and is recycled.
   - Optional: create a horde-agent-build Perforce user with read access to the UE depot.

## Cost Expectation

Costs are estimates for us-east-1 in May 2026 pricing. Active assumes ~4 hours of build agent
runtime per day and modest data egress.

| Component | Spec | Idle $/mo | Active $/mo |
| --- | --- | --- | --- |
| Phase 1 P4 server EC2 | t4g.medium, 24/7 | 25 | 25 |
| P4 depot EBS gp3 | 500 GiB | 40 | 40 |
| P4 metadata + logs + root | 94 GiB total | 8 | 8 |
| Route53 zone + ACM + Secrets + logs | n/a | 5 | 5 |
| **Phase 1 subtotal** |  | **78** | **78** |
| Phase 2 Horde host EC2 | t4g.medium, 24/7 | 25 | 25 |
| Horde data + root EBS | 60 GiB total | 5 | 5 |
| External ALB | 1 ALB, low traffic | 18 | 22 |
| S3 artifacts + logs (7-day lifecycle) | depends on builds | 2 | 8 |
| Build agents (Spot c7a.xlarge, ~60 hr/mo) | n/a | 0 | 4 |
| Build agent workspace EBS (ephemeral) | 1 TiB during job | 0 | 4 |
| **Phase 2 subtotal** |  | **50** | **68** |
| Data egress | small | 1 | 8 |
| **Total** |  | **~$129** | **~$154** |

Reintroducing the warm AMI snapshot adds ~$51/mo standing. Switching depot from gp3 to st1
saves ~$22/mo at the cost of slower cold syncs.

## Warm AMI Workflow (deferred but documented)

When build cadence grows:

1. Add a seed entry to var.agents in studio/phase2-horde/main.tf with min_size = 1,
   create_asg = false (a single one-shot instance).
2. SSM into the seed, install p4 CLI, p4 trust, log in as horde-agent-build user.
3. Create workspace at /mnt/horde-workspace, p4 sync to populate.
4. aws ec2 stop-instances --instance-ids <id>.
5. aws ec2 create-image --instance-id <id> --name "horde-agent-warm-$(date +%Y%m%d)" --no-reboot.
6. Update the agent launch template to point at the new AMI; future scale-out uses the warm image.
7. Automate weekly refresh with EventBridge + SSM RunCommand.

## Backups and Operations

- P4 checkpoints: SDP daily_backup.sh and weekly_backup.sh are auto-installed by the Packer
  AMI's p4_configure.sh. Add an EventBridge schedule + SSM RunCommand to aws s3 sync
  /hxdepots/p4/1/checkpoints/ to S3 nightly. Lifecycle: STANDARD_IA at 30 days,
  Glacier Deep Archive at 30 days, expire at 365.
- Horde Mongo: daily mongodump from the host via SSM, push to S3. The Mongo dataset is small
  because artifacts live in S3.
- Horde host data volume: EBS snapshots nightly via AWS Backup. 14 dailies, 4 weeklies.
- Horde server upgrades: bump image digest in modules/unreal/horde/templates/docker-compose.yml.tftpl,
  terraform apply (no-op on infrastructure), then ssm send-command "docker compose pull && docker compose up -d horde".

## Risk Register

1. t4g.medium (4 GiB RAM) for Horde + Mongo + Redis is tight. Mitigation: pin Mongo
   --wiredTigerCacheSizeGB 1.0, Redis --maxmemory 512mb. Promote to t4g.large (~$50/mo step up)
   if MemoryUtilization stays above 85%.
2. Cold p4 sync of 256 GB on a brand-new agent is slow (30 to 45 min). Mitigation: warm AMI
   workflow (deferred). Until then, accept first-launch latency, or keep min_size = 1.
3. NS propagation delay blocks ACM validation. Mitigation: verify dig before running terraform apply.
4. GHCR rate limits on Horde image pulls. Mitigation: pin to a specific digest in the compose
   template; consider mirroring to ECR Private once steady.
5. Single-AZ Phase 1 design. Acceptable for 5-person scale; rely on S3-replicated checkpoints
   for DR. Upgrading to multi-AZ roughly doubles P4 cost.
6. Spot interruption mid-build. Mitigation: Horde detects the 2-minute warning and retries the
   job on another agent. Set max_size high enough to absorb retries.

## Forked Module Change Inventory

Files modified or deleted in modules/unreal/horde/ on the sidewinder branch:

- docdb.tf - DELETED
- elasticache.tf - DELETED
- ecs.tf - DELETED
- local.tf - rewritten (Mongo+Redis on localhost)
- ec2.tf - NEW (Horde host, EBS data volume, IAM instance profile, user-data template)
- s3.tf - NEW (artifact + logs bucket with 7-day lifecycle)
- asg.tf - rewritten (mixed_instances_policy Spot, gp3, no ECS depends_on)
- alb.tf - rewritten (target_type=instance, internal ALB removed)
- iam.tf - rewritten (EC2 trust on default role, no ECS task execution role, S3 storage policy)
- sg.tf - rewritten (DocDB/ElastiCache/internal-ALB SGs removed, host SG repurposed)
- variables.tf - significant variable surface changes
- outputs.tf - removed internal_alb outputs, added horde_host_* outputs
- examples/complete/main.tf - rewritten for the new variable surface
- templates/horde_host_user_data.sh.tftpl - NEW
- templates/docker-compose.yml.tftpl - NEW
- templates/server.json.tftpl - NEW (Horde server config with pools, S3 storage)
- README.md - architecture description rewritten
