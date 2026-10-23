defmodule CustomerContact.Campaign do
  @moduledoc false
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @statuses ~w(draft approved sending sent cancelled)
  @layouts ~w(branded none)

  schema "cc_campaigns" do
    field :name, :string
    field :channel, :string, default: "email"
    field :subject, :string
    field :preheader, :string
    field :html_body, :string
    field :layout, :string, default: "branded"
    field :segment_ids, {:array, :string}, default: []
    field :status, :string, default: "draft"
    field :created_by, :string
    field :tested_hash, :string
    field :tested_at, :utc_datetime
    field :tested_by, :string
    field :approved_hash, :string
    field :approved_count, :integer
    field :approved_at, :utc_datetime
    field :approved_by, :string
    field :send_started_at, :utc_datetime
    field :send_completed_at, :utc_datetime
    field :sent_by, :string
    field :note, :string

    has_many :deliveries, CustomerContact.Delivery

    timestamps(type: :utc_datetime)
  end

  def statuses, do: @statuses
  def layouts, do: @layouts

  @doc "Changeset for the editable content of a draft or approved campaign."
  def changeset(campaign, attrs) do
    campaign
    |> cast(attrs, [:name, :subject, :preheader, :html_body, :layout, :segment_ids])
    |> validate_required([:name])
    |> validate_length(:name, max: 200)
    |> validate_length(:subject, max: 250)
    |> validate_length(:preheader, max: 250)
    |> validate_length(:html_body, max: 1_000_000)
    |> validate_inclusion(:layout, @layouts)
    |> validate_format(:subject, ~r/\A[^\r\n]*\z/, message: "must be a single line")
    |> validate_format(:preheader, ~r/\A[^\r\n]*\z/, message: "must be a single line")
    |> update_change(:segment_ids, &(&1 |> Enum.reject(fn id -> id in [nil, ""] end) |> Enum.uniq() |> Enum.sort()))
  end

  @doc "Hash of everything a test send shows; any change requires a new test."
  def content_hash(%__MODULE__{} = c) do
    hash({c.channel, c.subject, c.preheader, c.html_body, c.layout})
  end

  @doc "Hash of content plus audience; any change requires a new approval."
  def approval_hash(%__MODULE__{} = c) do
    hash({content_hash(c), Enum.sort(c.segment_ids || [])})
  end

  def tested?(%__MODULE__{} = c), do: c.tested_hash != nil and c.tested_hash == content_hash(c)

  def approved?(%__MODULE__{} = c) do
    c.status == "approved" and c.approved_hash != nil and c.approved_hash == approval_hash(c)
  end

  def editable?(%__MODULE__{status: status}), do: status in ~w(draft approved)

  defp hash(term) do
    :crypto.hash(:sha256, :erlang.term_to_binary(term)) |> Base.encode16(case: :lower)
  end
end
