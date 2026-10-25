# Email setup: Resend, from no-reply@firstlineeph.com

Owner decision 2026-10-18. These steps are for the owner: they involve accounts, DNS and secret keys, which
Claude doesn't create or enter. Once they're done, Claude deploys the `send-invitation` function (with your OK)
and tests it.

**Why it's needed.** Supabase's built-in sender only delivers to members of the Supabase account's own team, at
about 2 emails an hour. New officers registering, and anyone resetting a password, don't get their emails until
custom email is set up. Invitations aren't emailed at all yet.

**What gets sent to Resend.** The recipient's email address, the email's wording (council name, role, the
inviter's email address, and the one-time link). No case or surveillance data. Check Resend's data processing
agreement and add Resend to your record of processing before going live.

## 1. Resend account and domain

1. Create a Resend account (free plan: 100 emails a day, 3,000 a month).
2. **Domains → Add domain**: `firstlineeph.com`. If Resend offers a region, choose the European one (Ireland).
3. Resend shows DNS records to add. They're usually:
   - an **MX** record and a **TXT** (SPF) record on a `send` subdomain (so your normal email isn't affected);
   - a **TXT** record for DKIM, named `resend._domainkey`.
4. Optional but recommended, if you don't already have one: a **TXT** record named `_dmarc` with
   `v=DMARC1; p=none;` (you can tighten it later).

## 2. GoDaddy DNS

1. GoDaddy → My Products → `firstlineeph.com` → **DNS**.
2. Add each record exactly as Resend shows it (type, name, value). Don't change or delete existing records,
   especially existing MX records if you already receive email at this domain.
3. Back in Resend, press **Verify**. It can take from minutes to a few hours.

## 3. API key

1. Resend → **API keys → Create**: name it "First Line production", permission **Sending access**, limited to
   `firstlineeph.com`.
2. Copy it once and keep it safe. It's used in steps 4 and 6. Don't send it in chat or email.

## 4. Supabase: send sign-in emails through Resend

Supabase dashboard → project → **Authentication → Emails → SMTP settings** → enable custom SMTP:

| Setting | Value |
|---|---|
| Sender email | `no-reply@firstlineeph.com` |
| Sender name | `First Line` |
| Host | `smtp.resend.com` |
| Port | `465` |
| Username | `resend` |
| Password | the API key from step 3 |

Then **Authentication → Rate limits**: set "emails per hour" to suit (for example 60).

## 5. Supabase: links and wording

1. **Authentication → URL configuration**:
   - Site URL: the address people use for First Line (see "Open question" below).
   - Redirect URLs: add `<site address>/app**` and `<site address>/reset-password`.
2. **Authentication → Emails → Templates**: paste the HTML from this folder:
   - Confirm signup → `confirm-signup.html` (subject: "Confirm your email address for First Line")
   - Reset password → `reset-password.html` (subject: "Reset your First Line password")
   - Change email address → `change-email.html` (subject: "Confirm your new email address for First Line")

## 6. Supabase: secrets for the invitation function

**Edge Functions → Secrets** → add:

| Name | Value |
|---|---|
| `RESEND_API_KEY` | the API key from step 3 |
| `EMAIL_FROM` | `First Line <no-reply@firstlineeph.com>` |
| `APP_URL` | the site address, starting `https://`, with no slash at the end |

## 7. Tell Claude

Claude then (with your OK) applies database update 28, deploys `send-invitation`, and sends a test invitation
to an address you choose.

## Open question: the site address

Emails link to the live site, so `APP_URL` and the Site URL need the address people will use. That depends on the
hosting decision (Lovable or another host, and whether to use a name like `app.firstlineeph.com`). Until then the
current published address works, and can be changed later in steps 5 and 6.
