defmodule CustomerContact.DataCase do
  use ExUnit.CaseTemplate

  using do
    quote do
      use Oban.Testing, repo: CustomerContact.TestRepo
      import Swoosh.TestAssertions
      import CustomerContact.DataCase
      import Ecto.Query
      alias CustomerContact.TestRepo, as: Repo
    end
  end

  setup tags do
    pid = Ecto.Adapters.SQL.Sandbox.start_owner!(CustomerContact.TestRepo, shared: not tags[:async])
    on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(pid) end)
    :ok
  end

  def campaign_fixture(attrs \\ %{}) do
    {:ok, campaign} =
      CustomerContact.Campaigns.create_campaign(
        Map.merge(
          %{
            name: "Spring news",
            subject: "Hello {{first_name}}",
            html_body: ~s(<p>Hi {{name}}</p><p><a href="https://example.org/page?a=1&amp;b=2">Read</a></p>),
            segment_ids: ["all"]
          },
          attrs
        ),
        "author@example.test"
      )

    campaign
  end

  def test_recipient_fixture(email \\ "tester@example.test") do
    {:ok, tr} = CustomerContact.Audience.add_test_recipient(%{email: email, name: "Tester"})
    tr
  end
end
