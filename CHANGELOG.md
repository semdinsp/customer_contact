# Changelog

## Unreleased

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
