# Sidewinder Team Onboarding and Offboarding

The studio's goal: a new team member is productive in under 30 minutes,
and an offboarded member loses all access in under 5 minutes. The trick
is using Google Workspace as the identity hub so disabling one account
cascades to every system.

This document describes both the target state and the current state. Some
pieces (Tailscale, Horde OIDC) need one-time configuration before the
"super fast onboarding" story is real -- those steps are in the
[Enablement work](#enablement-work) section.

## Identity model

```
+----------------------+
| Google Workspace     |  one user record per team member
| user@sidewinder.dev  |
+----+--------+--------+
     |        |
     | OIDC   | SSO via Google
     |        |
     v        v
+--------+ +-----------+      +-------------+
| Horde  | | Tailscale |      | Perforce    |
|  + UGS | |  tailnet  |      | (manual user|
| via    | |  member   |      |  creation,  |
| OIDC   | |  group    |      |  per-server)|
+--------+ +-----------+      +-------------+
                                    |
                                    | tailnet routes to
                                    v
                              +-------------+
                              | P4 server   |
                              | (in VPC,    |
                              |  no public  |
                              |  IP)        |
                              +-------------+
```

What this gets us:

- Adding a user to Google Workspace immediately gives them email + the
  studio identity.
- Tailscale's Google Workspace SSO admits them to the tailnet
  automatically (after one-time SSO config in Tailscale admin).
- Horde OIDC + UGS via Horde-issued tokens lets them sign into CI/CD
  with their Google email -- no Horde-specific credential.
- The only system that needs a manual user-create step is Perforce,
  because we explicitly skipped deploying P4Auth (Helix Authentication
  Service) for cost (~$30/mo Fargate). For a 5-person team that step is
  ~30 seconds of admin work; if the team grows past ~10 people, we
  revisit deploying P4Auth so P4 also flows from Google Workspace
  identity.

Offboarding flips the same flow: suspend or delete the Google Workspace
user, Tailscale + Horde access are revoked the next time their session
refreshes, and a single P4 admin command finishes the job.

## Onboarding a new team member

Expected total time: **~15 minutes** for the admin, **~10 minutes** for
the new user to set up their workstation.

### Admin steps

1. **Create the Google Workspace account.**
   admin.google.com -> Users -> Add new user.
   - Email: `firstname.lastname@sidewinder.dev` (or whatever your
     studio's naming convention is)
   - Generate an initial password; the user changes it on first login.

2. **Add them to the `engineers` Workspace group** (or whatever group is
   referenced in Tailscale's ACL and Horde's OIDC admin claim mapping).
   Single click in admin.google.com.

3. **Create their Perforce account** from your admin workstation:

   ```powershell
   $P4 = "ssl:p4.studio.sidewinder.dev:1666"
   $NEW_USER = "firstname.lastname"

   # Create the user record (opens editor; set Email and FullName, save)
   p4 -p $P4 -u ccasteel user -f $NEW_USER

   # Set an initial password (you choose it, share via secure channel)
   p4 -p $P4 -u ccasteel passwd $NEW_USER

   # Add to unlimited_timeout so they don't hit forced password rotation
   p4 -p $P4 -u ccasteel group unlimited_timeout
   # Editor opens; add $NEW_USER to the Users: list, save

   # Add to the dev team group with write access (group must exist;
   # create it once with `p4 group dev_team`)
   p4 -p $P4 -u ccasteel group dev_team
   # Editor opens; add $NEW_USER to the Users: list, save
   ```

   For an admin/super user, also:

   ```powershell
   p4 -p $P4 -u ccasteel protect
   # Editor opens; add: super user $NEW_USER * //...
   # Save
   ```

4. **Send the new user a setup brief** (see "New user setup brief" below).
   Include their P4 username, the initial P4 password, and a link to this
   doc.

That's it on the admin side. No Spacelift run, no IP whitelist edit, no
Tailscale invitation needed (Google Workspace SSO handles the tailnet
membership).

### New user setup brief (send this to them)

Hi <name>, welcome to Sidewinder. Three short steps to get productive:

**1. Install and sign in to Tailscale.**
- Download from https://tailscale.com/download for your platform.
- Sign in with your `<your-email>@sidewinder.dev` Google account.
- Once it shows "Connected" in the system tray, you're on the studio
  tailnet. You can now reach our private servers.

**2. Install Perforce P4V.**
- Download from https://www.perforce.com/downloads/helix-visual-client-p4v.
- During setup, set up a connection:
  - Server: `ssl:p4.studio.sidewinder.dev:1666`
  - User: `<your.p4.username>` (the admin provided this)
  - Workspace: leave blank for now
- First connection prompts you to trust the SSL fingerprint. Accept.
- Log in with the password the admin sent. Change it via
  Connection -> Set Password.

For command-line P4 with multiple servers on one machine, see
the "Client-side P4 isolation" section of the studio README.

**3. Install Unreal Engine + UGS.**
- UE5 install instructions: see the studio's onboarding wiki page (TODO).
- UGS: when prompted to sign in, choose "Sign in with Google" and use
  your sidewinder.dev account. It'll authenticate against Horde
  automatically.

You're now ready. The project lives at `//depot/UnrealProject/...` in
Perforce. Open a P4V workspace there and `p4 sync` to get started.

## Offboarding a team member

Expected total time: **~3 minutes**.

### Admin steps

1. **Suspend the Google Workspace user.**
   admin.google.com -> Users -> find user -> Suspend account (or Delete
   if permanent).
   - Tailscale: the user's tailnet session is invalidated within a few
     minutes (Tailscale revokes on next OIDC token refresh).
   - Horde: same. Their Horde session can't refresh, and any in-flight
     UGS calls return 401.

2. **Delete their P4 user record.** This also invalidates any active
   P4 ticket.

   ```powershell
   $P4 = "ssl:p4.studio.sidewinder.dev:1666"
   $USER = "firstname.lastname"

   # Force a logout of any current sessions
   p4 -p $P4 -u ccasteel logout -a $USER

   # Delete the user (-f because we're deleting someone else's account)
   p4 -p $P4 -u ccasteel user -d -f $USER

   # The user is automatically removed from groups they were in.
   # If they owned any client workspaces, transfer or delete those
   # separately: p4 clients -u $USER, then p4 client -d <client>.
   ```

3. **Audit their workstations.** If the offboarding is involuntary,
   ask them (or their manager) to return any company-issued devices.
   Tailscale's admin console lets you forcibly remove specific node
   records: https://login.tailscale.com/admin/machines.

4. **(Optional) Revoke any GitHub access** they had to the
   SidewinderGames org so they lose access to Spacelift via the GitHub
   App. github.com/orgs/SidewinderGames/people -> remove.

That's the full offboarding loop. Google Workspace handles SSO-driven
revocation; P4 needs the one manual command above; everything else
follows.

## Current state vs. target state

| Capability | Current state | Target state | To enable |
| --- | --- | --- | --- |
| Email + identity | n/a | Google Workspace | Already set up |
| Tailscale tailnet access | Manual invite | Google Workspace SSO -> auto-join | One-time tailnet SSO config |
| Tailscale routing to AWS | Not yet deployed | Subnet router in VPC | See [TAILSCALE.md](./TAILSCALE.md) |
| P4 server access | IP whitelist on Phase 1 SG | Tailscale-routed, SG allows only relay | Phase B of TAILSCALE.md |
| P4 user record | Manual `p4 user -f` | Same | (Could deploy P4Auth for SSO; deferred for cost) |
| Horde web UI | Anonymous (no auth) | Google Workspace OIDC | One-time Horde config (below) |
| UGS | Not yet connected | Sign in via Horde, which uses OIDC | Follows Horde OIDC |
| Spacelift access | Not configured | Google Workspace SSO via SAML | One-time Spacelift SSO config |

## Enablement work

These are one-time setup tasks that turn the "super fast onboarding"
story into reality. Estimated ~3 hours of work total, spread across the
three integrations.

### A. Tailscale + Google Workspace SSO

1. **Upgrade the Sidewinder tailnet to the multi-user Tailscale plan**
   (current plan: check at https://login.tailscale.com/admin/settings/billing).
   The multi-user plan unlocks user-management, group ACLs, and SSO
   provider configuration. ~$6 per user per month at the time of
   writing -- verify current Tailscale pricing.

2. **Configure Google Workspace as Tailscale's identity provider.**
   In Tailscale admin -> Settings -> User management -> SSO. Choose
   Google Workspace; follow the prompts to create an OAuth app in
   Google Cloud Console and paste the client ID/secret back into
   Tailscale.

3. **Define groups in the Tailscale ACL** that map from Google
   Workspace groups:

   ```json
   {
     "groups": {
       "group:engineers": ["alice@sidewinder.dev", "bob@sidewinder.dev"]
     },
     "tagOwners": {
       "tag:subnet-router": ["autogroup:admin"]
     },
     "acls": [{
       "action": "accept",
       "src":    ["group:engineers"],
       "dst":    ["10.40.0.0/16:*"]
     }],
     "autoApprovers": {
       "routes": { "10.40.0.0/16": ["tag:subnet-router"] }
     }
   }
   ```

   On the Business plan and above, group membership can be synced from
   Google Workspace groups directly (`autogroup:member` references a
   Workspace group) rather than maintaining the list manually.

4. **Deploy the subnet router** per [TAILSCALE.md](./TAILSCALE.md)
   Phase A.

### B. Horde OIDC against Google Workspace

The Horde module already has variables for OIDC auth (`auth_method`,
`oidc_authority`, `oidc_audience`, `oidc_client_id`,
`oidc_client_secret`). Currently they're left unset, which yields
`auth_method = "Anonymous"`. To switch:

1. **Create an OAuth 2.0 client in Google Cloud Console** under your
   Sidewinder Google Cloud project:
   - APIs & Services -> Credentials -> Create credentials -> OAuth
     client ID
   - Application type: Web application
   - Authorized JavaScript origins: `https://horde.studio.sidewinder.dev`
   - Authorized redirect URIs:
     `https://horde.studio.sidewinder.dev/signin-oidc`
   - Copy the Client ID and Client Secret.

2. **Store the secret in AWS Secrets Manager**:

   ```powershell
   aws secretsmanager create-secret `
     --region us-east-1 `
     --name sidewinder/horde-oidc-client-secret `
     --secret-string "<paste-the-client-secret>"
   ```

3. **Update the admin stack** so Phase 2 picks up the OIDC env vars.
   In `studio/spacelift/main.tf`, add new env vars on the Phase 2
   stack:

   ```hcl
   resource "spacelift_environment_variable" "phase2_tf_oidc_authority" {
     stack_id = spacelift_stack.phase2_horde.id
     name     = "TF_VAR_horde_oidc_authority"
     value    = "https://accounts.google.com"
   }
   # ...similar for audience, client_id, client_secret_arn
   ```

   Plumb matching variables through `studio/phase2-horde/variables.tf`
   and `main.tf` into the `module "horde"` block. The module already
   wires them into Horde's `appsettings` via the user-data template.

4. **Set `auth_method = "OpenIdConnect"`** when calling the module.

5. **Apply admin stack -> Apply Phase 2.** The Horde host's user-data
   regenerates and re-applies; the Horde container restarts with
   OIDC enabled. Existing users session-revoke; team members sign in
   with their Google account at `https://horde.studio.sidewinder.dev`.

6. **Define an admin claim**. To grant Horde admin (operator)
   privileges to specific Google Workspace users, set
   `admin_claim_type = "email"` and `admin_claim_value =
   "ccasteel@sidewinder.dev"`. Or use a custom OIDC claim mapped from
   a Workspace group via Google's OIDC custom claims feature.

### C. UGS via Horde OIDC

UGS authenticates against Horde for metadata. Once Horde is OIDC, UGS
gets the auth flow for free:

1. Users open UGS, point it at `https://horde.studio.sidewinder.dev`.
2. UGS opens the browser to Horde's `/signin-oidc` endpoint.
3. Google Workspace login.
4. UGS receives a Horde bearer token, uses it for all metadata calls.

P4 sync inside UGS continues to use the user's P4 ticket (independent
of Horde auth). The P4 ticket comes from `p4 login` -- still
username/password, since we haven't deployed P4Auth.

### D. Spacelift SSO via Google Workspace (admin operators only)

For team members who'll trigger or approve Spacelift runs:

1. Spacelift UI -> Organization settings -> SSO.
2. Choose Google Workspace; follow prompts.
3. Map Google Workspace groups to Spacelift Spaces/roles.

This doesn't affect Spacelift -> AWS auth (still our IAM role); it just
gates who can log into the Spacelift UI.

## When to deploy P4Auth

If onboarding pace exceeds ~1 person per week and the manual `p4 user -f`
step becomes a bottleneck, deploy P4Auth (Helix Authentication Service)
to bring Perforce into the Google Workspace SSO fold.

The toolkit's `modules/perforce` module already supports it -- set
`p4_auth_config` in `studio/phase1-perforce/main.tf` instead of leaving
it null. Cost: ~$30/mo Fargate plus a sub-domain for the auth service.

After deploy, configure P4Auth with the same Google Workspace OAuth
client used for Horde (or a separate one). Once enabled, `p4 login`
flows through a browser to Google instead of prompting for a P4-specific
password.

## Recap

For the current state (Tailscale not yet deployed, Horde OIDC not
configured), onboarding looks like:

1. Create Google Workspace user (~30s)
2. Edit `TF_VAR_allowed_p4_cidrs` in Spacelift, trigger admin + Phase 1
   stacks (~5 min)
3. Create P4 user, add to groups, set password (~1 min)
4. Send setup brief to user (~30s composing)

After the enablement work in this doc:

1. Create Google Workspace user (~30s)
2. Create P4 user (~30s)
3. Send setup brief

Phase B of the Tailscale rollout removes step 2 of the current flow.
Phase B also removes the "rebuild when your IP changes" problem entirely.
