# Changelog

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

Upgrading: change the dependency tag to `v0.1.2`, add `home_path:` to the
`customer_contact_admin` call, and make sure `brand/0` has a postal address.
No new migration.

## v0.1.1

* Send test and other secondary buttons use a visible button style.
* Integration prompt notes that existing Oban `testing:` modes work.

## v0.1.0

* First release: campaigns with test send, typed-count approval and Oban
  sending; built-in tags; suppression list; SES/SNS delivery, bounce and
  complaint events; open, click and unsubscribe tracking.
