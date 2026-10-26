defmodule CustomerContact.Audience do
  @moduledoc """
  Who a campaign goes to: segments, built-in tags, test recipients and the
  suppression list.
  """

  import Ecto.Query

  alias CustomerContact.{Recipient, Suppression, Tag, Tagging, TestRecipient}

  @all "all"

  def normalize_email(nil), do: nil
  def normalize_email(email), do: email |> String.trim() |> String.downcase()

  ## Segments

  @doc "True when the host provides its own segments instead of built-in tags."
  def host_segments? do
    host = CustomerContact.host()
    Code.ensure_loaded?(host) and function_exported?(host, :list_segments, 0)
  end

  @doc "Every segment a campaign can target, with recipient counts."
  def list_segments do
    everyone = %{id: @all, name: "Everyone", count: length(CustomerContact.host().list_recipients())}

    others =
      if host_segments?() do
        CustomerContact.host().list_segments()
      else
        Enum.map(list_tags_with_counts(), fn {tag, count} ->
          %{id: "tag:" <> tag.id, name: tag.name, count: count}
        end)
      end

    [everyone | others]
  end

  @doc "Raw recipients for the given segment ids (may contain duplicates and suppressed people)."
  def recipients_for_segments([]), do: []

  def recipients_for_segments(ids) do
    host = CustomerContact.host()

    cond do
      @all in ids -> host.list_recipients()
      host_segments?() -> host.recipients_for_segments(ids)
      true -> built_in_tag_recipients(ids)
    end
  end

  defp built_in_tag_recipients(ids) do
    tag_ids = for "tag:" <> id <- ids, valid_uuid?(id), do: id

    refs =
      from(t in Tagging, where: t.tag_id in ^tag_ids, select: t.recipient_ref, distinct: true)
      |> repo().all()
      |> MapSet.new()

    Enum.filter(CustomerContact.host().list_recipients(), &MapSet.member?(refs, to_string(&1.ref)))
  end

  @doc """
  Recipients a campaign will actually be sent to: one per email address,
  without blank addresses or anyone on the suppression list.
  """
  def deliverable_recipients(ids) do
    recipients =
      ids
      |> recipients_for_segments()
      |> Enum.map(fn %Recipient{} = r -> %{r | email: normalize_email(r.email), ref: to_string(r.ref)} end)
      |> Enum.filter(&valid_email?(&1.email))
      |> Enum.uniq_by(& &1.email)

    suppressed = suppressed_emails(Enum.map(recipients, & &1.email))
    Enum.reject(recipients, &MapSet.member?(suppressed, &1.email))
  end

  @doc "Conservative address check: one @, no whitespace, control characters or commas."
  def valid_email?(email) when is_binary(email),
    do: Regex.match?(~r/\A[^\s@,;<>"\x00-\x1f]+@[^\s@,;<>"\x00-\x1f]+\.[^\s@,;<>"\x00-\x1f]+\z/, email)

  def valid_email?(_), do: false

  def count_deliverable(ids), do: length(deliverable_recipients(ids))

  ## Suppressions

  def suppressed_emails(emails) do
    emails
    |> Enum.chunk_every(5_000)
    |> Enum.flat_map(fn chunk ->
      repo().all(from s in Suppression, where: s.email in ^chunk, select: s.email)
    end)
    |> MapSet.new()
  end

  def suppressed?(email), do: MapSet.member?(suppressed_emails([normalize_email(email)]), normalize_email(email))

  def list_suppressions, do: repo().all(from s in Suppression, order_by: [desc: s.inserted_at])

  @doc "Adds an email to the suppression list. Already-suppressed emails keep their original reason."
  def suppress(email, reason, note \\ nil) do
    %Suppression{}
    |> Suppression.changeset(%{email: email, reason: reason, note: note})
    |> repo().insert(on_conflict: :nothing, conflict_target: :email)
  end

  def delete_suppression(id) do
    if valid_uuid?(id), do: repo().delete_all(from s in Suppression, where: s.id == ^id), else: {0, nil}
  end

  ## Test recipients

  def list_test_recipients, do: repo().all(from t in TestRecipient, order_by: t.email)

  def add_test_recipient(attrs), do: %TestRecipient{} |> TestRecipient.changeset(attrs) |> repo().insert()

  def change_test_recipient(attrs \\ %{}), do: TestRecipient.changeset(%TestRecipient{}, attrs)

  def delete_test_recipient(id) do
    if valid_uuid?(id), do: repo().delete_all(from t in TestRecipient, where: t.id == ^id), else: {0, nil}
  end

  ## Built-in tags

  def list_tags, do: repo().all(from t in Tag, order_by: t.name)

  def list_tags_with_counts do
    counts =
      from(t in Tagging, group_by: t.tag_id, select: {t.tag_id, count(t.id)})
      |> repo().all()
      |> Map.new()

    Enum.map(list_tags(), &{&1, Map.get(counts, &1.id, 0)})
  end

  def create_tag(attrs), do: %Tag{} |> Tag.changeset(attrs) |> repo().insert()

  @doc """
  Returns the built-in tag with this name, creating it if needed. For apps
  that tag recipients automatically (e.g. a "Donors" tag kept in sync).
  """
  def ensure_tag(name, description \\ nil) when is_binary(name) do
    name = String.trim(name)

    with nil <- repo().get_by(Tag, name: name),
         {:error, changeset} <- create_tag(%{name: name, description: description}) do
      # Another process may have created it between the lookup and the insert.
      case repo().get_by(Tag, name: name) do
        nil -> {:error, changeset}
        tag -> {:ok, tag}
      end
    else
      %Tag{} = tag -> {:ok, tag}
      {:ok, tag} -> {:ok, tag}
    end
  end

  def change_tag(attrs \\ %{}), do: Tag.changeset(%Tag{}, attrs)

  def delete_tag(id) do
    if valid_uuid?(id), do: repo().delete_all(from t in Tag, where: t.id == ^id), else: {0, nil}
  end

  @doc "Map of recipient ref => MapSet of tag ids."
  def taggings_by_ref do
    from(t in Tagging, select: {t.recipient_ref, t.tag_id})
    |> repo().all()
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
    |> Map.new(fn {ref, ids} -> {ref, MapSet.new(ids)} end)
  end

  def tag_recipient(tag_id, ref) do
    if valid_uuid?(tag_id), do: insert_tagging(tag_id, ref), else: {0, nil}
  end

  defp insert_tagging(tag_id, ref) do
    repo().insert_all(Tagging, [%{tag_id: tag_id, recipient_ref: to_string(ref), inserted_at: now()}],
      on_conflict: :nothing
    )
  end

  def untag_recipient(tag_id, ref) do
    if valid_uuid?(tag_id), do: delete_tagging(tag_id, ref), else: {0, nil}
  end

  defp delete_tagging(tag_id, ref) do
    repo().delete_all(from t in Tagging, where: t.tag_id == ^tag_id and t.recipient_ref == ^to_string(ref))
  end

  defp valid_uuid?(id), do: match?({:ok, _}, Ecto.UUID.cast(id))
  defp now, do: DateTime.utc_now() |> DateTime.truncate(:second)
  defp repo, do: CustomerContact.repo()
end
