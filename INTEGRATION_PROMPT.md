# Prompt: add CustomerContact campaign email to this app

> Paste everything below into this app's Claude Code session. It is
> self-contained. The library lives at
> https://github.com/semdinsp/customer_contact (local copy:
> `../customer_contact`). Read its `README.md` and `lib/` for details. Do **not**
> edit the library from this app. If it needs a change, write up what's needed
> and give it to the user for the customer_contact session.

---

## Goal

Add the shared **CustomerContact** library so admins can paste HTML, preview it
in this app's branded layout, send a test to a list of test recipients, approve
it by typing the recipient count, and send it to tagged customers. Delivery,
bounce, complaint, open, click and unsubscribe tracking come with it.

Follow this repo's CLAUDE.md git workflow: work on a new branch
`claude/add-customer-contact`, make small commits, run `mix test` and
`mix compile --warnings-as-errors`, push the branch, and don't merge.

## 1. Dependency

```elixir
# mix.exs
{:customer_contact, github: "semdinsp/customer_contact", tag: "v0.1.9"},
```

Add `:customer_contact` to `import_deps` in `.formatter.exs` so `mix format`
leaves the `customer_contact_admin` router call without parentheses. This only
stops `mix format` adding them: if the router already has
`customer_contact_admin(...)` with brackets, remove them by hand.

The library depends on `phoenix_live_view`, `phoenix_ecto`, `ecto_sql`,
`swoosh`, `oban (~> 2.19)` and `req`. Run `mix deps.get` and resolve any
version conflicts by updating this app's own deps, not by changing the library.

## 2. Oban (skip if the app already runs Oban)

* Add `{:oban, "~> 2.19"}`.
* Add a migration that runs `Oban.Migrations.up()` / `Oban.Migrations.down(version: 1)`.
* Add `{Oban, Application.fetch_env!(:my_app, Oban)}` to the supervision tree,
  after the Repo.
* `config/config.exs`: `config :my_app, Oban, repo: MyApp.Repo, queues: [default: 10, customer_contact: 5]`
* `config/test.exs`: `config :my_app, Oban, testing: :manual`

If Oban already runs, add `customer_contact: 5` to its `queues`. Keep the
concurrency at or below the account's SES maximum send rate (check it in the
SES console; 14/s is a common starting quota).

If the app already sets an Oban `testing:` mode, keep it. `:manual` and
`:inline` both work with the library. Under `:inline`, a test that clicks
Send also runs the send jobs immediately, so the emails reach the Swoosh
test mailbox right away rather than waiting as enqueued jobs. Write
assertions to match the mode in use.

## 3. Migration

```elixir
defmodule MyApp.Repo.Migrations.AddCustomerContact do
  use Ecto.Migration
  def up, do: CustomerContact.Migrations.up(version: 2)
  def down, do: CustomerContact.Migrations.down(version: 1)
end
```

This creates the `cc_*` tables (campaigns, deliveries, events, suppressions,
test recipients, tags, taggings, contacts).

## 4. Host module

Create `lib/my_app/customer_contact_host.ex` implementing
`CustomerContact.Host`:

```elixir
defmodule MyApp.CustomerContactHost do
  @behaviour CustomerContact.Host
  import Ecto.Query
  alias CustomerContact.Recipient

  @impl true
  def brand do
    %{
      name: "Organisation Name",
      from: {"Organisation Name", Application.fetch_env!(:my_app, :campaign_from_address)},
      reply_to: nil,                      # or "info@..."
      postal_address: "Street, City, Province/State, Postal code",  # required: campaigns can't be approved without it
      website_url: "https://example.com",
      logo_url: "https://example.com/images/logo.png",  # absolute URL or nil
      primary_color: "#1e3a5f",           # match the site's existing email styling
      accent_color: "#5b9ec9",
      background_color: "#e8f2f8"
    }
  end

  # Everyone who may receive campaigns. Leave out anyone the app has blocked.
  # `ref` must be a stable id as a string.
  @impl true
  def list_recipients do
    from(s in MyApp.Subscriber, select: %Recipient{ref: type(s.id, :string), email: s.email, name: s.name})
    |> MyApp.Repo.all()
  end

  # OPTIONAL: implement these two only if the app already has its own tags.
  # Otherwise omit them, and admins use CustomerContact's built-in tags on the
  # Audience page. Segment ids are strings; "all" is reserved.
  # @impl true
  # def list_segments, do: [%{id: tag_id_string, name: "Tag name", count: n}, ...]
  # @impl true
  # def recipients_for_segments(ids), do: [%Recipient{}, ...]  # union of the tags
end
```

Pick the from address the app already uses for SES (it must be a verified
SES identity). Don't hard-code secrets.

Unsubscribe links in sent emails are signed with the endpoint's
`secret_key_base`. Rotating it breaks every unsubscribe link already sent,
and the law expects them to keep working for 30 days (CAN-SPAM) to 60 days
(CASL). Tell the user this in the final summary.

If you don't know the organisation's postal address, don't invent one: leave
it `nil`, tell the user, and the campaign page will warn until it's set.

If the app should tag people automatically (e.g. a "Donors" tag kept in sync
with payments), use `CustomerContact.Audience.ensure_tag(name, description)`
to get the tag and `tag_recipient(tag.id, ref)` / `untag_recipient/2`.

## 5. Config

`config/config.exs`:

```elixir
config :customer_contact,
  repo: MyApp.Repo,
  mailer: MyApp.Mailer,
  host: MyApp.CustomerContactHost,
  endpoint: MyAppWeb.Endpoint,
  public_path: "/cc",
  oban: Oban,
  queue: :customer_contact
```

`config/runtime.exs`, inside `if config_env() == :prod`. Values come from
the environment and are never committed:

```elixir
config :customer_contact,
  ses_configuration_set: System.get_env("CC_SES_CONFIGURATION_SET"),
  sns_topic_arns:
    "CC_SNS_TOPIC_ARNS" |> System.get_env("") |> String.split(",", trim: true) |> Enum.map(&String.trim/1)
```

Also check:

* **The production mailer must really send through SES** (`Swoosh.Adapters.AmazonSES`
  or `Swoosh.Adapters.ExAwsAmazonSES`), not `Swoosh.Adapters.Local`.
* **`MyAppWeb.Endpoint` `url:` in production must be the public https host.**
  Tracking and unsubscribe links are built from `Endpoint.url()`.

## 6. Router

```elixir
import CustomerContact.Web.Router

# Public: tracking pixel, click redirect, unsubscribe, SNS webhook.
# Must be OUTSIDE any pipeline with :protect_from_forgery (SNS and
# one-click unsubscribe POST without a CSRF token; signed tokens / AWS
# signatures authorize them instead).
forward "/cc", CustomerContact.Web.PublicPlug

# Admin pages: inside the existing admin scope, behind BOTH the admin plug
# pipeline and the admin on_mount.
scope "/admin" do
  pipe_through [:browser, :require_authenticated_user, :require_admin_user]

  customer_contact_admin "/contact",
    on_mount: [{MyAppWeb.UserAuth, :require_admin}],
    home_path: "/admin"
end
```

* Set `home_path` to the app's admin dashboard. The home icon in the page
  header links there.
* Use whatever this app's real admin plug and `on_mount` are called. **Both
  must reject non-admins**: anyone who reaches these pages can email every
  customer. If the app has no admin check yet, add one first (see the
  app-specific notes below).
* Don't put the macro inside a scope with a module alias such as
  `scope "/admin", MyAppWeb do`. The macro resets the alias itself, but keep
  it simple.
* If `/cc` collides with an existing route, choose another path and set
  `public_path` to match.
* The admin user's email is recorded as `tested_by`, `approved_by` and
  `sent_by`. It's read from `@current_scope.user.email` or
  `@current_user.email`.

If the app already rate-limits public routes (e.g. with a Plug or at the
proxy), cover `/cc/*` too. It's optional; the endpoints are cheap and bounded.

Add a "Customer contact" link to the admin dashboard or nav that points to
`/admin/contact`.

## 7. Tailwind

The admin pages use Tailwind + daisyUI classes. In `assets/css/app.css` add:

```css
@source "../../deps/customer_contact/lib";
```

If the app doesn't use daisyUI, the pages still work but look plain. Tell
the user rather than restyling the library.

## 8. Tests

Add tests in this app (and make sure they pass):

1. A non-admin, and a logged-out visitor, can't load `/admin/contact`: they
   get a redirect.
2. An admin can load `/admin/contact`, `/admin/contact/audience` and
   `/admin/contact/campaigns/new`.
3. `MyApp.CustomerContactHost.list_recipients/0` returns `%CustomerContact.Recipient{}`
   structs with string refs and leaves out blocked people. If you implemented
   segments, test `recipients_for_segments/1` too.
4. `GET /cc/o/anything.gif` returns 200 `image/gif` without a session.

Then run `mix test` and `mix compile --warnings-as-errors`.

## 9. AWS setup (for the user, in the AWS console; you can't do it)

Include this checklist, filled in with this app's names, in the final summary:

1. **SES → Configuration sets → Create**: `<app>-campaigns`.
2. **SNS → Topics → Create** (Standard, same region as SES): `<app>-ses-events`.
3. **SES → Configuration set → Event destinations → Add**: choose Amazon SNS
   and the topic above. (Optional: on the SNS topic set the `SignatureVersion`
   attribute to `2` so messages are signed with SHA-256.) Events: Sends, Rejects, Deliveries, Hard bounces,
   Complaints, Rendering failures.
4. `fly secrets set CC_SES_CONFIGURATION_SET=<app>-campaigns CC_SNS_TOPIC_ARNS=<topic ARN>`
   and deploy **before** the next step.
5. **SNS → Topic → Create subscription**: protocol HTTPS, endpoint
   `https://<production host>/cc/sns`. The app confirms the subscription
   automatically. Check that the subscription shows "Confirmed".
6. The SES account must have **production access** (out of the sandbox) to
   email unverified addresses. The IAM key the app uses needs
   `ses:SendRawEmail` (and `ses:SendEmail`).
7. Smoke test: add yourself as a test recipient, send a test, open it, click
   a link, and check the campaign report.

## 10. Final summary

Report the branch, the files changed and why, any assumptions (especially who
counts as a recipient), the AWS checklist above, and anything in the library
that got in the way (as a note for the customer_contact session).
