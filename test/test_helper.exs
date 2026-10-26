alias CustomerContact.TestRepo

_ = Ecto.Adapters.Postgres.storage_down(TestRepo.config())
:ok = Ecto.Adapters.Postgres.storage_up(TestRepo.config())

{:ok, _} = TestRepo.start_link()
Ecto.Migrator.up(TestRepo, 1, CustomerContact.TestObanMigration, log: false)
Ecto.Migrator.up(TestRepo, 2, CustomerContact.TestMigration, log: false)
Ecto.Migrator.up(TestRepo, 3, CustomerContact.TestMigrationV2, log: false)
{:ok, _} = Oban.start_link(repo: TestRepo, testing: :manual)
{:ok, _} = Phoenix.PubSub.Supervisor.start_link(name: CustomerContact.TestPubSub)
{:ok, _} = CustomerContact.TestEndpoint.start_link()

Ecto.Adapters.SQL.Sandbox.mode(TestRepo, :manual)
ExUnit.start()
