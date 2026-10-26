# Changelog

## v0.1.5

* **Sent page.** A new **Sent** tab lists every campaign email, newest
  first: date, recipient, campaign (linked to the email and its report),
  status, opens and clicks. Search by full or partial address to see
  everything one person was sent, and filter by campaign, status, or test
  sends. Filters are kept in the URL (`/sent?email=…`), so a search can be
  bookmarked.
* **Help on every page.** A help icon (?) at the right of the header opens a
  short guide to the page: how to write, test, approve and send a campaign,
  what the audience sections do, and how to read a report.
* **One-click unsubscribe.** The people table on the Audience page has an
  Unsubscribe button beside each person. It adds them to the suppression
  list (reason `manual`, noting which admin did it) after a confirmation.
  People already suppressed show an "unsubscribed" badge instead. The table
  only appears when the app uses CustomerContact's built-in tags. Otherwise,
  add the address to the suppression list.

## v0.1.4

* **Messages you can't miss.** Admin messages (e.g. "Add a subject first.")
  also appear pinned to the bottom corner of the screen, with a dismiss
  button, so they're visible however far down the page the admin clicked.
  They still appear at the top as before.
* **Refusals are logged.** A refused test send, approval or send logs
  `[CustomerContact] <action> refused campaign_id=… by=… reason=…` at info.

## v0.1.3

* **Logging.** Campaign steps (test send, approve, send started, dispatch,
  stopped, cancelled, finished), every email sent, retried or failed, every
  SES delivery, bounce, complaint and reject, and unsubscribes are logged.
  Lines start with `[CustomerContact]` and include `campaign_id`,
  `delivery_id` and `ses_message_id`. Recipient addresses are masked
  (`a***@example.com`). See "Logging" in the README.

* Require `plug_crypto` 2.2.1 or later, which fixes advisory
  EEF-CVE-2026-105963 (the secret key base could appear in stack traces).
  Apps can also update it directly: `mix deps.update plug_crypto`.
* Upgrade note for v0.1.2: `import_deps` only stops `mix format` adding
  brackets to `customer_contact_admin`. Brackets already in the router line
  must be removed by hand.

## v0.1.2

* **Home icon.** The admin header has a home icon. Set where it goes with the
  router option `home_path:` (usually the app's admin dashboard; default `/`).
* **Merge-field fallbacks.** `{{first_name|there}}` gives "there" when the
  recipient has no name. Works for every merge field, in the subject and HTML.
* **Postal address required.** Campaigns can't be approved or sent while the
  host's `brand/0` has no `postal_address` (CAN-SPAM, CASL). The campaign page
  shows a warning.
* **`Audience.ensure_tag/2`** returns a built-in tag by name, creating it if
  needed, for apps that tag recipients automatically.
* **Formatter.** The library exports `locals_without_parens` for
  `customer_contact_admin`. Add `:customer_contact` to the app's
  `.formatter.exs` `import_deps` so `mix format` stops adding parentheses.
* **Security hardening** (from a review after the first deployments; no high
  or medium issues were found):
  * SNS messages more than an hour old are refused, so captured ones can't be
    replayed.
  * Fetching not-yet-cached SNS signing certificates is limited to 10 a
    minute with short timeouts; temporary failures return 503 so SNS retries.
  * Approve and Send are refused if another admin or window changed the
    campaign since the page was loaded.
  * Test recipient addresses get the same strict check as audience addresses.

Upgrading: change the dependency tag to `v0.1.2`, add `home_path:` to the
`customer_contact_admin` call, and make sure `brand/0` has a postal address.
If the router line has brackets, `customer_contact_admin(...)`, remove them by
hand; `mix format` won't. No new migration.

## v0.1.1

* Send test and other secondary buttons use a visible button style.
* Integration prompt notes that existing Oban `testing:` modes work.

## v0.1.0

* First release: campaigns with test send, typed-count approval and Oban
  sending; built-in tags; suppression list; SES/SNS delivery, bounce and
  complaint events; open, click and unsubscribe tracking.
