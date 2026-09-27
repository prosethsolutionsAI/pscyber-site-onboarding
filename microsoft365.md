# Microsoft 365 audit logs

Microsoft 365 cannot send logs anywhere. The Wazuh agent on your **site collector
fetches** them from Microsoft every minute - outbound HTTPS 443 only - and sends
them to the Proseth SOC through the collector's encrypted tunnel, like everything
else from your site.

What we then watch: sign-ins and failed sign-ins, new mailbox forwarding and
inbox rules, file downloads and sharing links in SharePoint/OneDrive, admin role
changes, app consents, and (optionally) data loss prevention matches.

## 1. Your Microsoft admin creates an app (5 minutes, once)

1. **Entra admin center** → **App registrations** → **New registration**.
   Name it e.g. `PSCyber SOC log reader`. Single tenant. No redirect URI.
2. **API permissions** → **Add a permission** → **Office 365 Management APIs** →
   **Application permissions** → tick **ActivityFeed.Read**
   (and **ActivityFeed.ReadDlp** if you want DLP events) → **Add**.
   Then press **Grant admin consent for <your organisation>**.
   It is read-only: the app can read audit logs and nothing else.
3. **Certificates & secrets** → **New client secret** → choose an expiry
   (12 or 24 months) → copy the **Value** straight away (it is shown once).
4. **Microsoft Purview** → **Audit**: auditing must be on. It is by default; if
   you see a "Start recording" button, press it.

Send Proseth the **Directory (tenant) ID** and the **Application (client) ID**
(both on the app's Overview page). They are not secret.

**Do not email the secret.** It is typed once, on the collector, by whoever runs
the command in step 2 - your IT or a Proseth engineer on a call with you. It
stays on the collector only.

## 2. Run one command on the site collector

Proseth gives you a one-line command with your IDs filled in. Run it on the
collector as root. It:

- asks for the client secret (typing is hidden);
- checks the collector can reach Microsoft, signs in with the secret and checks
  the permission - **before changing anything** - and tells you exactly what to
  fix if one of those fails;
- stores the secret in a file only Wazuh can read, adds the Office 365 settings to
  the agent, restarts it, and puts the old settings back if the agent does not
  start.

The first events arrive within about 15 minutes (Microsoft publishes audit logs
with a delay). Only new activity is collected - nothing older.

## Firewall

The collector needs **outbound TCP 443** to:

| Cloud | Hosts |
|---|---|
| Normal Microsoft 365 | `login.microsoftonline.com`, `manage.office.com` |
| US Government GCC | `login.microsoftonline.com`, `manage-gcc.office.com` |
| US Government GCC High | `login.microsoftonline.us`, `manage.office365.us` |

Nothing inbound.

## Later

- **Secret expires:** create a new one in the same app and run the same command
  again - it replaces the old one.
- **Stop collecting:** run the command with `PSCYBER_O365_REMOVE=1` instead (Proseth
  gives you that one too). It removes the settings and deletes the secret from the
  collector. Then delete the secret, or the app, in Entra ID.
