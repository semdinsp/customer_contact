# CustomerContact

Campaign email for Phoenix apps. Paste HTML, preview it in your app's branded
layout, send a test, approve, then send to tagged recipients — with delivery,
bounce, complaint, open, click and unsubscribe tracking.

Used by brla, shelley_plants, jan_paintings, britonbay and marenumdonation.
**To add it to an app, give that app's Claude Code session
[`INTEGRATION_PROMPT.md`](INTEGRATION_PROMPT.md).**

## How a campaign works

```
draft ──(Send test)──> tested ──(type recipient count + Approve)──> approved ──(Send)──> sending ──> sent
  ^                                                                    │
  └──────────── editing content or audience clears approval ───────────┘
```

* **Test send** goes to every address on the Audience page's test list, with
  `[TEST]` in the subject. It records a hash of the subject, preheader, HTML
  and layout; changing any of them requires a new test.
* **Approve** needs a current test and the approver typing the exact number of
  recipients. One admin may approve their own campaign. Changing content or
  audience afterwards drops the campaign back to draft.
* **Send** asks for confirmation, then an Oban job creates one delivery per
  unique, non-suppressed address and sends them through the app's Swoosh
  mailer. Each delivery is claimed atomically, so a retried or duplicated job
  never sends the same email twice. Sending can be cancelled from the report.

## Audience

* The host app implements `CustomerContact.Host` and returns its recipients.
* Segments are either the host's own tags (implement `list_segments/0` and
  `recipients_for_segments/1`) or CustomerContact's built-in tags, managed on
  the Audience page. `"all"` (Everyone) is always available.
* Addresses are lower-cased and de-duplicated. The suppression list
  (unsubscribes, permanent bounces, complaints, manual entries) is always
  skipped, and is checked again just before each email is sent.

## Tracking

| Metric | How |
|---|---|
| Sent | the mailer accepted it (SES message id stored) |
| Delivered / bounced / complaint | SES configuration-set events → SNS → `POST {public_path}/sns` |
| Opened | 1×1 pixel `GET {public_path}/o/:token`; approximate (Apple Mail preloads images; others block them) |
| Clicked | links rewritten to `GET {public_path}/c/:token` → 302 to the original URL; a click also counts as an open |
| Unsubscribed | footer link + `List-Unsubscribe` one-click header → `{public_path}/u/:token` |

All tokens are signed with the host endpoint's `secret_key_base`. Click tokens
embed the destination, so the redirector can't be used as an open redirect.

## Merge fields

`{{name}}`, `{{first_name}}`, `{{email}}`, `{{unsubscribe_url}}` — in the
subject and HTML. Values are HTML-escaped. Every email also gets a footer with
the organisation name, postal address and unsubscribe link (required for bulk
mail under CAN-SPAM and Canada's CASL).

## Security notes

* The admin pages can email every customer. `customer_contact_admin` refuses
  to compile without an `on_mount`, and that `on_mount` **must** enforce the
  host's admin check. Also put the route inside a scope that pipes through the
  host's admin plug.
* The HTML preview renders in an `<iframe sandbox="">` (no scripts, no
  same-origin access), so pasted HTML can't act on the admin's session.
  (`<script>` blocks are also dropped from outgoing mail as a courtesy; this
  is not a sanitizer, since only admins author campaign HTML.)
* Every workflow step re-reads and row-locks the campaign, so a stale browser
  tab can't edit or revoke a campaign that is already sending. Workers refuse
  to send if the content or audience no longer matches what was approved, and
  sending is refused (approval revoked) if the recipient count changed since
  approval.
* SNS messages are accepted only from topics listed in `:sns_topic_arns`,
  signed with a certificate fetched from exactly
  `https://sns.<topic's region>.amazonaws.com/SimpleNotificationService-*.pem`
  (no look-alike hosts such as S3 buckets, no query strings). Anyone can get
  AWS to sign messages for *their own* topic, so the topic allow-list is
  essential. Consider setting the topic's `SignatureVersion` to `2` (SHA-256).
* Tracking tokens never contain email addresses. Replaying a pixel or link
  increments counters but doesn't add event rows.
* Unsubscribe `GET` only shows a confirmation; the change happens on `POST`, so
  link scanners can't unsubscribe people.
* Recipient addresses that aren't well-formed are skipped.
* No credentials live in this library. AWS keys, configuration-set names and
  topic ARNs come from the host's runtime environment.

## Development

```
mix deps.get
mix test        # needs a local Postgres; creates customer_contact_test
```

Install from GitHub with a tag:

```elixir
{:customer_contact, github: "semdinsp/customer_contact", tag: "v0.1.0"}
```

The package metadata is ready for Hex (`mix hex.publish`), but publishing
isn't required: the repo is public and the apps' Docker builds already have
git.

## Roadmap

* SMS channel (`channel` is already on campaigns and deliveries; add a sender
  in `lib/customer_contact/sender.ex`).
* Saved, reusable templates per app.
