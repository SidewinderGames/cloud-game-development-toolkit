# Tailscale Subnet Router for Sidewinder AWS Infrastructure

> **Status:** Phase A (the subnet router itself) is now codified in
> `studio/phase1-perforce/tailscale.tf` and runs on every Phase 1 apply.
> The only pre-apply prerequisite is the auth-key secret in AWS Secrets
> Manager; see "Pre-apply checklist" below. Phase B (cutting P4 over to
> Tailscale-only by emptying `allowed_p4_cidrs`) and Phase C (Horde
> internal ALB) remain pending and are described later in this doc.

## Pre-apply checklist for Phase A

Before the next Phase 1 run:

1. **Define `tag:subnet-router` and an autoApprover ACL** in the
   Sidewinder tailnet (Tailscale admin -> Access controls). Example
   below. Without `autoApprovers`, the relay's routes will appear in
   the admin console marked "pending approval" until manually
   accepted; with `autoApprovers`, they're auto-accepted on first
   join.

2. **Generate a Tailscale auth key** (Settings -> Keys -> Generate
   auth key):
   - Reusable: no
   - Ephemeral: no
   - Pre-authorized: yes
   - Tags: `tag:subnet-router`
   - Expiration: 90 days

3. **Store the key in AWS Secrets Manager**:
   ```powershell
   aws secretsmanager create-secret `
     --region us-east-1 `
     --name sidewinder/tailscale-auth-key `
     --secret-string "tskey-auth-..."
   ```

4. **(No required TF vars.)** The Phase 1 stack reads the secret by
   name from the default `sidewinder/tailscale-auth-key`. If you want
   to disable the relay or change the advertised routes, optional env
   vars on the Phase 1 stack:
   - `TF_VAR_create_tailscale_relay = false` (skip the relay entirely)
   - `TF_VAR_tailscale_advertise_routes = "10.40.0.0/16"` (default)
   - `TF_VAR_tailscale_auth_key_secret_name = "sidewinder/tailscale-auth-key"` (default)

5. Trigger Phase 1. The plan adds the relay EC2 instance, its SG +
   egress, IAM role + instance profile, and one extra ingress rule on
   the P4 user-access SG allowing 1666 from the relay's SG.

## Goal

Replace the public IP whitelist on the Perforce server (and eventually the
Horde external ALB) with Tailscale-mediated access. Users authenticate
through their Tailscale identity to reach private AWS endpoints, and we
delete the public attack surface.

This document is an investigation and implementation plan, not yet executed.
The current IP-whitelist approach keeps working in parallel during the
migration.

## Why this is worth doing

Today, onboarding a new admin requires:

1. They send their public IP
2. Edit `TF_VAR_allowed_p4_cidrs` on the admin stack
3. Trigger admin stack
4. Trigger Phase 1 stack
5. ~5 minutes elapsed before they can connect

And every time their IP changes (mobile networking, home ISP rotation,
travel, VPN swap) they're locked out until repeat.

Tailscale flips this. The subnet router stays put inside our VPC and
advertises the VPC's CIDR to the Sidewinder tailnet. Members of the
tailnet can route to `10.40.x.x` addresses directly. The P4 server's SG
allows ingress only from the subnet router. The user's public IP becomes
irrelevant.

Onboarding becomes: invite them to the tailnet, hand them their Perforce
credentials, done. No Terraform changes, no Spacelift runs, no waiting.

## Architecture

```
+---------------------+        +------------------------------+
| Developer laptop    |        | sidewinder.dev VPC 10.40/16  |
| Tailscale client    |        |                              |
| 100.x.y.z           |        |  +-----------------------+   |
|                     |        |  | Tailscale subnet      |   |
|  studio.tailnet ----+--------+->| router (small EC2)   |   |
+---------------------+        |  | tailscaled            |   |
                               |  | advertise 10.40.0.0/16|   |
                               |  +----------+------------+   |
                               |             |                |
                               |             | 10.40.1.x      |
                               |             v                |
                               |  +------------------------+  |
                               |  | P4 server EC2          |  |
                               |  | SG: ingress from       |  |
                               |  | subnet-router SG only  |  |
                               |  +------------------------+  |
                               +------------------------------+
```

The subnet router is a single small EC2 instance running the Tailscale
daemon. It accepts SSH-equivalent connections via Tailscale's
WireGuard-based mesh and forwards them to the VPC subnets it advertises.
The P4 server has no public IP. The user's laptop sees `p4.studio.sidewinder.dev`
resolve to the P4 server's private 10.40.x.x address (via private DNS or
the existing public DNS pointing at a non-public IP -- both work) and
their Tailscale client routes the connection through the subnet router.

## What changes in our existing infrastructure

Concretely:

- **New EC2 instance** (`sidewinder-tailscale-relay`): t4g.nano in a
  public subnet with `associate_public_ip_address = true` so it can reach
  Tailscale's coordination servers and Internet for package install.
- **Phase 1 P4 server**: drop the public EIP (or keep it during cutover),
  add an SG ingress rule allowing TCP/1666 from the subnet router's SG,
  remove or empty `allowed_p4_cidrs`.
- **DNS for `p4.studio.sidewinder.dev`**: switch from A record pointing at
  the public EIP to A record pointing at the private IP `10.40.1.x`. Public
  resolvers will still answer with the private IP -- that's fine because
  only Tailscale-routed clients can actually reach it. Or use Tailscale's
  MagicDNS and assign the server a stable Tailscale hostname.
- **Phase 2 Horde ALB**: switch `create_external_alb = false` and
  `create_internal_alb = true`. Internal ALB with route53 A ALIAS pointing
  at its private DNS. Same Tailscale routing model.
- **Phase 2 build agents**: still need outbound Internet (Horde enrollment
  is fine via the internal ALB once they're in-VPC; only outbound to
  Amazon Linux package repos and SSM endpoints matters). Either keep
  `associate_public_ip_address = true` on agents or add a NAT gateway
  (~$33/mo). The IGW-with-public-IP route stays cheaper.
- **Spacelift role's external-id pattern**: unchanged. Tailscale is purely
  network-layer; it doesn't affect IAM auth flows.

## Implementation plan

### Phase A: stand up the subnet router (parallel to existing whitelist)

This phase changes nothing about how anyone currently connects. The IP
whitelist keeps working. We just add a new path.

1. **Generate a Tailscale auth key** in the Sidewinder tailnet admin:
   - https://login.tailscale.com/admin/settings/keys
   - Reusable: no (one-shot)
   - Ephemeral: no (we want the node to persist)
   - Pre-authorized: yes (skips manual approval)
   - Tags: `tag:subnet-router` (define this tag in tailnet ACL first)
   - Expiration: 90 days (we'll rotate before then or use a longer-lived
     key if your tailnet plan allows)
   - Store the key in AWS Secrets Manager:
     ```powershell
     aws secretsmanager create-secret `
       --region us-east-1 `
       --name sidewinder/tailscale-auth-key `
       --secret-string "tskey-auth-XXXXXXXXXX-..." `
       --description "Tailscale auth key for the Sidewinder subnet router"
     ```

2. **Add a tailnet ACL entry** so subnet-router-tagged nodes can advertise
   our VPC CIDR and tailnet members can route through it. In Tailscale
   admin -> Access controls -> edit the policy file:
   ```json
   {
     "tagOwners": {
       "tag:subnet-router": ["autogroup:admin"]
     },
     "acls": [
       {
         "action": "accept",
         "src":    ["autogroup:members"],
         "dst":    ["10.40.0.0/16:*"]
       }
     ],
     "autoApprovers": {
       "routes": {
         "10.40.0.0/16": ["tag:subnet-router"]
       }
     }
   }
   ```
   The `autoApprovers` block means routes the subnet router advertises
   are auto-accepted when it joins, no manual approval click required.

3. **New Terraform** at `studio/phase1-perforce/tailscale.tf` (or a new
   sibling stack -- I'd vote for keeping it in Phase 1 since it's
   single-AZ and tightly coupled to the VPC):

   ```hcl
   data "aws_ami" "al2023_arm64" {
     most_recent = true
     owners      = ["amazon"]
     filter { name = "name"; values = ["al2023-ami-2023*-arm64"] }
     filter { name = "architecture"; values = ["arm64"] }
   }

   data "aws_secretsmanager_secret" "tailscale_auth" {
     name = "sidewinder/tailscale-auth-key"
   }

   resource "aws_security_group" "tailscale_relay" {
     name        = "${local.project_prefix}-tailscale-relay"
     description = "Tailscale subnet router. Outbound only; inbound is via WireGuard."
     vpc_id      = aws_vpc.studio.id
   }

   resource "aws_vpc_security_group_egress_rule" "tailscale_all_out" {
     security_group_id = aws_security_group.tailscale_relay.id
     cidr_ipv4         = "0.0.0.0/0"
     ip_protocol       = "-1"
     description       = "Tailscale needs unrestricted egress (UDP 41641 + HTTPS to coordination)."
   }

   resource "aws_iam_role" "tailscale_relay" {
     name               = "${local.project_prefix}-tailscale-relay"
     assume_role_policy = jsonencode({
       Version = "2012-10-17"
       Statement = [{
         Effect    = "Allow"
         Action    = "sts:AssumeRole"
         Principal = { Service = "ec2.amazonaws.com" }
       }]
     })
   }

   resource "aws_iam_role_policy_attachment" "tailscale_ssm" {
     role       = aws_iam_role.tailscale_relay.name
     policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
   }

   resource "aws_iam_role_policy" "tailscale_secret_read" {
     role = aws_iam_role.tailscale_relay.id
     policy = jsonencode({
       Version = "2012-10-17"
       Statement = [{
         Effect   = "Allow"
         Action   = ["secretsmanager:GetSecretValue"]
         Resource = data.aws_secretsmanager_secret.tailscale_auth.arn
       }]
     })
   }

   resource "aws_iam_instance_profile" "tailscale_relay" {
     name = "${local.project_prefix}-tailscale-relay"
     role = aws_iam_role.tailscale_relay.name
   }

   resource "aws_instance" "tailscale_relay" {
     ami                         = data.aws_ami.al2023_arm64.id
     instance_type               = "t4g.nano"
     subnet_id                   = aws_subnet.public[0].id
     vpc_security_group_ids      = [aws_security_group.tailscale_relay.id]
     iam_instance_profile        = aws_iam_instance_profile.tailscale_relay.name
     associate_public_ip_address = true
     ebs_optimized               = true

     metadata_options {
       http_endpoint               = "enabled"
       http_tokens                 = "required"
       http_put_response_hop_limit = 2
       instance_metadata_tags      = "enabled"
     }

     # Required for a subnet router: kernel IP forwarding + Tailscale must
     # be told about each subnet it advertises.
     user_data = base64encode(<<-EOF
       #!/bin/bash
       set -euxo pipefail
       dnf install -y dnf-plugins-core
       dnf config-manager --add-repo https://pkgs.tailscale.com/stable/amazon-linux/2023/tailscale.repo
       dnf install -y tailscale
       systemctl enable --now tailscaled

       echo 'net.ipv4.ip_forward = 1' > /etc/sysctl.d/99-tailscale.conf
       echo 'net.ipv6.conf.all.forwarding = 1' >> /etc/sysctl.d/99-tailscale.conf
       sysctl -p /etc/sysctl.d/99-tailscale.conf

       AUTH=$(aws --region us-east-1 secretsmanager get-secret-value \
         --secret-id sidewinder/tailscale-auth-key \
         --query SecretString --output text)

       tailscale up \
         --authkey="$AUTH" \
         --hostname=sidewinder-aws-relay \
         --advertise-routes=10.40.0.0/16 \
         --advertise-tags=tag:subnet-router \
         --accept-dns=false \
         --ssh
     EOF
     )

     tags = { Name = "${local.project_prefix}-tailscale-relay" }
   }

   output "tailscale_relay_sg_id" {
     value = aws_security_group.tailscale_relay.id
   }

   output "tailscale_relay_private_ip" {
     value = aws_instance.tailscale_relay.private_ip
   }
   ```

4. **Trigger Phase 1**, apply. Verify the new node shows up at
   https://login.tailscale.com/admin/machines as `sidewinder-aws-relay`
   with the route `10.40.0.0/16` already approved.

5. **Test from your workstation** (with Tailscale running):
   ```powershell
   tailscale status     # confirm sidewinder-aws-relay is online
   ping 10.40.1.x       # the P4 server's private IP
   ```
   You should get replies routed through the relay.

### Phase B: cut P4 over to Tailscale-only

Once the relay is healthy, switch the P4 server to private-only access:

1. **Add a new SG ingress rule** on the existing user-access SG to allow
   1666 from the relay SG:
   ```hcl
   resource "aws_vpc_security_group_ingress_rule" "p4_from_tailscale" {
     security_group_id            = aws_security_group.p4_user_access.id
     referenced_security_group_id = aws_security_group.tailscale_relay.id
     ip_protocol                  = "tcp"
     from_port                    = 1666
     to_port                      = 1666
     description                  = "P4 ingress via Tailscale subnet router."
   }
   ```

2. **Test connectivity through Tailscale** -- have a user with Tailscale
   running but NOT in `allowed_p4_cidrs` connect. Confirm it works.

3. **Empty out the IP whitelist** by setting `TF_VAR_allowed_p4_cidrs` to
   `[]` in the admin stack, then triggering Phase 1. The
   `aws_vpc_security_group_ingress_rule` resources for the per-user
   CIDRs get destroyed. P4 is now reachable only via Tailscale.

4. **Optional: drop the EIP** -- in `p4_server_config` set
   `internal = true`. The instance loses its public IP. The DNS A record
   for `p4.studio.sidewinder.dev` needs to be repointed at the private IP
   (or you can switch it to a Route53 private hosted zone that's
   resolvable via Tailscale's MagicDNS forwarder).

### Phase C: extend to Horde

Same model for the Horde ALB:

1. `create_external_alb = false`, `create_internal_alb = true` in the
   Phase 2 module call.
2. The Route53 A ALIAS for `horde.studio.sidewinder.dev` points at the
   internal ALB's DNS name.
3. Users access `https://horde.studio.sidewinder.dev` through their
   Tailscale connection. The ALB has no public IP.

## Cost delta

| Item | Monthly |
| --- | --- |
| `t4g.nano` relay (24/7) | ~$3.50 |
| EBS gp3 root (8 GiB) | ~$0.65 |
| Tailscale (free tier covers up to 100 devices, 3 users on Personal Pro) | $0 |
| Removed: ALB public-side cost | unchanged (still 1 ALB, just internal) |
| Removed: EIP for P4 | -$0 (attached EIPs are free; only unattached cost) |
| **Net additional** | **~$4 to $5/mo** |

For Sidewinder's 5-user team on the Tailscale Personal Pro plan ($5/user/mo
if you want admin features) or the free Personal plan (no SSO, no ACL
groups, fine for a 5-person team): no additional Tailscale-side cost
unless you want SCIM / Okta / Google Workspace SSO integration, in which
case it's Tailscale's Team plan (~$6/user/mo, also gets you better RBAC
which is worth it for a studio).

## Trade-offs and gotchas

1. **Single point of failure**: one subnet router means an outage on that
   EC2 instance cuts off P4/Horde access. Mitigation: for HA, run two
   relays in different AZs (`max_size = 2` ASG or two `aws_instance`
   resources). Doubles relay cost (~$8/mo). At Sidewinder's scale,
   acceptable to start with one and add HA later if reliability becomes
   an issue.

2. **Tailscale auth key expiration**: standard non-reusable keys expire
   in 90 days. If the relay reboots or its node key expires past that
   point, it needs a new auth key to re-register. Options:
   - Rotate the secret in Secrets Manager + recreate the relay every
     ~80 days via Terraform taint.
   - Use a long-lived `ephemeral = false; reusable = false; expires =
     180d` key.
   - On Tailscale Team/Enterprise plans, use OAuth client credentials
     instead of auth keys (no expiration when the OAuth client is
     active).

3. **Tailnet ACL access**: by default `autogroup:members` in the ACL
   above lets every tailnet member route through to `10.40.0.0/16`. If
   you have contractors or other less-trusted people in the tailnet,
   restrict by tag or group:
   ```json
   {
     "groups": { "group:sidewinder-eng": ["alice@sidewinder.dev", ...] },
     "acls": [{
       "action": "accept",
       "src":    ["group:sidewinder-eng"],
       "dst":    ["10.40.0.0/16:*"]
     }]
   }
   ```

4. **DNS resolution**: `p4.studio.sidewinder.dev` currently resolves
   publicly to the EIP. After cutover, public resolvers should return
   the private IP `10.40.1.x` (which is fine -- non-Tailscale traffic
   gets nowhere). Alternative: use Tailscale's MagicDNS with a
   `*.sidewinder` magic hostname pattern, then the public DNS doesn't
   need to change at all and only tailnet members can resolve.

5. **Build agents in Phase 2**: agents are inside the VPC and reach
   Horde via the internal ALB. They don't need Tailscale -- they're
   already on the right network. The only Tailscale-side concern is
   that AwsAsg-scaled instances should NOT join the tailnet (no
   advertise routes, no node identity). The ASG's launch template
   doesn't install Tailscale, so this is the default and correct.

6. **MTU**: Tailscale's WireGuard wraps packets with ~80 bytes of
   overhead. Large p4 transfers should still work fine inside a VPC's
   9001 MTU, but if you're routing high-throughput sync over a
   constrained ISP link, MTU mismatches occasionally cause weird
   stalls. Tailscale's default MTU of 1280 inside the tunnel is
   conservative and almost always works.

7. **Tailscale on Spacelift runners**: irrelevant. Spacelift runners
   reach AWS via the IAM role and our infra-management APIs (no need
   to hit the P4 or Horde data plane). Spacelift continues to apply
   without Tailscale.

## Recommendation

Do Phase A as soon as the current production setup stabilizes (a week
or two of P4/Horde running cleanly). It's small, additive, and the
$4-5/mo cost is justified by the onboarding friction it removes.

Do Phase B (cut P4 over to Tailscale-only) the same day, after one
person verifies they can reach P4 over Tailscale. Empty the IP
whitelist last.

Defer Phase C (Horde internal ALB) until Phase B is stable. The Horde
UI is less-frequently accessed and the ALB rewrite has more moving
parts (target group changes, etc.).

## Open questions to resolve before Phase A

- What tailnet plan is the Sidewinder account on? Affects whether ACL
  tags + `autogroup:members` are available (Personal plan is limited).
- Are admins expected to manage Tailscale via SSO against Google
  Workspace? Affects whether to upgrade to the Team plan now.
- For the eventual HA decision: are there blackout windows where P4
  must stay reachable? If yes, plan for two relays.
