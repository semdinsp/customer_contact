# CustomerContact

Campaign email for Phoenix apps. An admin pastes HTML, previews it in the
app's branded email layout, sends a test to a short list of test people,
approves it, and sends it to everyone or to tagged groups of customers. Each
email is tracked: sent, delivered, bounced, complained, opened, clicked and
unsubscribed.

It's a library, not a service: it runs inside each app, uses the app's own
database, mailer (Amazon SES through Swoosh), Oban queue and admin login, and
reads the app's customers through a small callback module. Used by brla,
shelley_plants, jan_paintings, britonbay and marenumdonation.

**To add it to an app, give that app's Claude Code session
[`INTEGRATION_PROMPT.md`](INTEGRATION_PROMPT.md).** Changes per release are
in [`CHANGELOG.md`](CHANGELOG.md).

## What admins see

The pages live wherever the app mounts them (usually `/admin/contact`). The
header has a home icon back to the app's admin dashboard, and tabs for
Campaigns and Audience. Messages (saved, test sent, why something was
refused) appear at the top of the page and pinned to the bottom corner of the
screen.

* **Campaigns** lists every campaign with its status and, once sent, how many
  were sent, opened and clicked.
* **Campaign editor** has a name, subject, optional preheader (the preview
  line inboxes show after the subject), the HTML, a layout choice and the
  audience. A live preview shows the email as recipients will see it. Beside
  it are the three steps: **1. Send a test**, **2. Approve**, **3. Send**.
* **Report** (after sending) shows totals and rates, then one row per
  recipient (filterable by status) with send time, opens, clicks and any
  bounce or error. It
  refreshes every few seconds while sending, can cancel a send in progress,
  and lists the test sends separately.
* **Audience** shows the segments with recipient counts, the test recipient
  list, the suppression list (add or remove addresses by hand), and, if the
  app doesn't supply its own tags, a table for creating built-in tags and
  ticking which customers have them.

## How a campaign works

```
draft ──(Send test)──> tested ──(type recipient count + Approve)──> approved ──(Send)──> sending ──> sent
  ^                                                                    │
  └──────────── editing content or audience clears approval ───────────┘
```

* **Send test** emails every address on the test list, with `[TEST]` at the
  start of the subject. It records a fingerprint of the subject, preheader,
  HTML and layout; changing any of them needs a new test.
* **Approve** needs a current test, a postal address in the app's brand, and
  the approver typing the exact number of recipients, so a wrong audience is
  caught before anything goes out. One admin may approve their own campaign.
  Changing the content or audience afterwards drops it back to draft.
* **Send** asks for confirmation. Background jobs then create one delivery per
  unique, non-suppressed address and send them through the app's mailer, at
  the rate the Oban queue allows. If the audience size changed since approval,
  nothing is sent and approval is revoked. A retried or duplicated job never
  sends the same person the same email twice.
* **Cancel** (on the report) stops emails that haven't gone yet.
* Only drafts can be edited or deleted.

## Layouts

* **branded** (default): the app's logo, colours and a footer with the
  organisation's name, postal address, website and unsubscribe link.
* **none**: the HTML as pasted, for a complete email designed elsewhere. The
  same footer is added just before `</body>`.

Colours, logo, name, from address, reply-to, postal address and website come
from the host's `brand/0`.

## Merge fields

Usable in the subject and the HTML:

| Field | Value |
|---|---|
| `{{name}}` | the recipient's full name |
| `{{first_name}}` | the first word of the name |
| `{{email}}` | the recipient's address |
| `{{unsubscribe_url}}` | their personal unsubscribe link (the footer has one anyway) |

Add a fallback after `|` for when the value is blank: `Hi {{first_name|there}},`
gives "Hi there," for someone with no name. Values are HTML-escaped. Unknown
fields are left as typed.

## Audience

* The app implements `CustomerContact.Host`:
  * `brand/0` returns the branding above.
  * `list_recipients/0` returns everyone who may be emailed, as
    `%CustomerContact.Recipient{ref, email, name}` (`ref` is the app's own id
    for the person). Leave out anyone the app has blocked.
  * Optionally `list_segments/0` and `recipients_for_segments/1`, if the app
    already has its own tags or groups. Otherwise admins use the built-in tags.
* **Everyone** (`"all"`) is always a segment. A campaign can target several
  segments; recipients in more than one get one email.
* Addresses are trimmed, lower-cased and de-duplicated, and malformed ones are
  skipped.
* The **suppression list** holds unsubscribes, permanent bounces, complaints
  and manual entries. Suppressed addresses are always skipped, and checked
  again just before each email is sent.
* Apps can tag people from code: `Audience.ensure_tag(name, description)`,
  then `Audience.tag_recipient(tag.id, ref)` / `untag_recipient/2`.

## Tracking

| Metric | How |
|---|---|
| Sent | the mailer accepted it (SES message id stored) |
| Delivered / bounced / complaint | SES configuration-set events → SNS → `POST {public_path}/sns` |
| Opened | 1×1 pixel `GET {public_path}/o/:token`; approximate (Apple Mail preloads images; others block them) |
| Clicked | links rewritten to `GET {public_path}/c/:token` → redirect to the original URL; a click also counts as an open |
| Unsubscribed | footer link and the `List-Unsubscribe` one-click header → `{public_path}/u/:token` |

Results are stored in the app's database (`cc_deliveries`, `cc_events`,
`cc_suppressions`), so the app can query them directly or use
`CustomerContact.Campaigns.stats/1` and `list_deliveries/2`.

## Logging

Every step is written to the app's log, so a send can be debugged from the
Fly logs (`fly logs`, or the dashboard) as well as from the report page:

```
[CustomerContact] send started campaign_id=… by=admin@example.com recipients=412
[CustomerContact] dispatching campaign campaign_id=… recipients=412 queued=412
[CustomerContact] sent email campaign_id=… delivery_id=… to=a***@example.com test=false ses_message_id=0100018f…
[CustomerContact] SES Delivery campaign_id=… delivery_id=… to=a***@example.com test=false ses_message_id=0100018f…
[CustomerContact] SES Bounce campaign_id=… delivery_id=… to=b***@example.org test=false ses_message_id=… type=Permanent subtype=General
[CustomerContact] campaign sent campaign_id=… sent=410 failed=0 cancelled=2
```

* Search for `[CustomerContact]` for everything, or for a `campaign_id`,
  `delivery_id` or `ses_message_id` to follow one campaign or email. The SES
  message id is the same one SES shows and the one Swoosh returns.
* Info: test sends, approvals, refused clicks (with the reason), sends started and finished, each email sent,
  each SES delivery, unsubscribes, and SES events for emails that aren't
  campaign deliveries. Warning: retries, bounces, complaints, rejects,
  stopped sends and rejected SNS messages. Error: emails that failed for good.
* Addresses are masked (`a***@example.com`); the full address is on the
  report page. The ids are also Logger metadata (plus `customer_contact:
  true`) for apps that log structured metadata.
* Two lines per recipient at `:info` can be a lot for big lists. To keep only
  problems, add `Logger.put_module_level(CustomerContact.Log, :warning)` to
  the app's `Application.start/2`.

## Setup in an app (summary)

[`INTEGRATION_PROMPT.md`](INTEGRATION_PROMPT.md) has the full steps. In short:

```elixir
# mix.exs
{:customer_contact, github: "semdinsp/customer_contact", tag: "v0.1.4"}

# migration
def up, do: CustomerContact.Migrations.up(version: 1)

# config/config.exs
config :customer_contact,
  repo: MyApp.Repo,
  mailer: MyApp.Mailer,
  host: MyApp.CustomerContactHost,
  endpoint: MyAppWeb.Endpoint,
  public_path: "/cc"

# config/runtime.exs (prod), from environment variables
config :customer_contact,
  ses_configuration_set: System.get_env("CC_SES_CONFIGURATION_SET"),
  sns_topic_arns: String.split(System.get_env("CC_SNS_TOPIC_ARNS", ""), ",", trim: true)

# router.ex
import CustomerContact.Web.Router

forward "/cc", CustomerContact.Web.PublicPlug   # outside CSRF-protected pipelines

scope "/admin" do
  pipe_through [:browser, :require_authenticated_user, :require_admin_user]

  customer_contact_admin "/contact",
    on_mount: [{MyAppWeb.UserAuth, :require_admin}],
    home_path: "/admin"
end
```

Plus an Oban queue named `customer_contact`, `@source
"../../deps/customer_contact/lib";` in `app.css` (the pages use Tailwind and
daisyUI), and the AWS SES/SNS setup in the prompt's checklist.

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
  tab can't edit or revoke a campaign that is already sending. Approve and
  Send are refused if the campaign changed since the admin's page loaded, so
  nobody approves or sends content they haven't seen. Workers refuse
  to send if the content or audience no longer matches what was approved, and
  sending is refused (approval revoked) if the recipient count changed since
  approval.
* SNS messages are accepted only from topics listed in `:sns_topic_arns`,
  signed with a certificate fetched from exactly
  `https://sns.<topic's region>.amazonaws.com/SimpleNotificationService-*.pem`
  (no look-alike hosts such as S3 buckets, no query strings). Anyone can get
  AWS to sign messages for *their own* topic, so the topic allow-list is
  essential. Consider setting the topic's `SignatureVersion` to `2` (SHA-256).
  Messages more than an hour old are refused (no replays), and fetches of
  certificates not yet cached are limited to 10 a minute.
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

Releases are git tags (`v0.1.2`); apps depend on the tag. The package metadata
is ready for Hex (`mix hex.publish`), but publishing isn't required: the repo
is public and the apps' Docker builds already have git.

## Roadmap

* SMS channel (`channel` is already on campaigns and deliveries; add a sender
  in `lib/customer_contact/sender.ex`).
* Saved, reusable templates per app.
