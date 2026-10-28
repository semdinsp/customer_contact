defmodule CustomerContact.Audience do
  @moduledoc """
  Who a campaign goes to: segments, built-in tags, test recipients and the
  suppression list.
  """

  import Ecto.Query

  alias CustomerContact.{Contact, Recipient, Suppression, Tag, Tagging, TestRecipient}

  @all "all"
  @manual "manual"

  def normalize_email(nil), do: nil
  def normalize_email(email), do: email |> String.trim() |> String.downcase()

  ## Segments

  @doc "True when the host provides its own segments instead of built-in tags."
  def host_segments? do
    host = CustomerContact.host()
    Code.ensure_loaded?(host) and function_exported?(host, :list_segments, 0)
  end

  @doc "Everyone who may receive campaigns: the host's recipients plus contacts added by hand."
  def list_recipients do
    CustomerContact.host().list_recipients() ++ Enum.map(list_contacts(), &contact_recipient/1)
  end

  @doc "Every segment a campaign can target, with recipient counts."
  def list_segments do
    contacts = list_contacts()
    everyone = %{id: @all, name: "Everyone", count: length(CustomerContact.host().list_recipients()) + length(contacts)}
    manual = %{id: @manual, name: "Added manually", count: length(contacts)}

    others =
      if host_segments?() do
        CustomerContact.host().list_segments()
      else
        Enum.map(list_tags_with_counts(), fn {tag, count} ->
          %{id: "tag:" <> tag.id, name: tag.name, count: count}
        end)
      end

    [everyone | others] ++ if(contacts == [], do: [], else: [manual])
  end

  @doc "Raw recipients for the given segment ids (may contain duplicates and suppressed people)."
  def recipients_for_segments([]), do: []

  def recipients_for_segments(ids) do
    if @all in ids do
      list_recipients()
    else
      {manual, others} = Enum.split_with(ids, &(&1 == @manual))
      manual = if manual == [], do: [], else: Enum.map(list_contacts(), &contact_recipient/1)
      segment_recipients(others) ++ manual
    end
  end

  defp segment_recipients([]), do: []

  defp segment_recipients(ids) do
    if host_segments?(), do: CustomerContact.host().recipients_for_segments(ids), else: built_in_tag_recipients(ids)
  end

  defp built_in_tag_recipients(ids) do
    tag_ids = for "tag:" <> id <- ids, valid_uuid?(id), do: id

    refs =
      from(t in Tagging, where: t.tag_id in ^tag_ids, select: t.recipient_ref, distinct: true)
      |> repo().all()
      |> MapSet.new()

    Enum.filter(list_recipients(), &MapSet.member?(refs, to_string(&1.ref)))
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

  ## Contacts added by hand

  def list_contacts, do: repo().all(from c in Contact, order_by: [desc: c.inserted_at])

  def change_contact(attrs \\ %{}), do: Contact.changeset(%Contact{}, attrs)

  @doc """
  Adds a person by hand. Refused if the host already supplies that address.
  `actor` is recorded with the consent confirmation.
  """
  def add_contact(attrs, actor) do
    changeset = Contact.changeset(%Contact{added_by: actor}, attrs)
    email = Ecto.Changeset.get_field(changeset, :email)

    if email && Enum.any?(CustomerContact.host().list_recipients(), &(normalize_email(&1.email) == email)) do
      {:error, %{Ecto.Changeset.add_error(changeset, :email, "is already in the audience") | action: :insert}}
    else
      changeset
      |> Ecto.Changeset.put_change(:consent_note, "Consent confirmed by #{actor}")
      |> repo().insert()
    end
  end

  @doc """
  Adds the people in `rows` (`%{line:, email:, name:}`, from
  `CustomerContact.CSV.parse_people/1`) as hand-added contacts, and gives every
  listed address the built-in tag `tag_id` if one is given, including people
  who were already in the audience.

  Returns `{:ok, %{added:, existing:, tagged:, invalid: [line]}}`. Addresses
  repeated in the file count once; `existing` is people already in the
  audience and `tagged` is people who didn't already have the tag. `{:error, :unknown_tag}` if the tag doesn't exist.
  """
  def import_contacts(rows, actor, tag_id \\ nil) do
    with :ok <- check_tag(tag_id) do
      {valid, invalid} =
        rows
        |> Enum.map(&%{&1 | email: normalize_email(&1.email)})
        |> Enum.split_with(&(valid_email?(&1.email) and String.length(&1.email) <= 160))

      valid = Enum.uniq_by(valid, & &1.email)

      host_refs =
        CustomerContact.host().list_recipients()
        |> Enum.filter(& &1.email)
        |> Enum.group_by(&normalize_email(&1.email), &to_string(&1.ref))

      {:ok, result} =
        repo().transaction(fn ->
          new = Enum.reject(valid, &Map.has_key?(host_refs, &1.email))
          added = insert_contacts(new, actor)
          contact_ids = contact_ids_by_email(Enum.map(new, & &1.email))

          tagged =
            if tag_id do
              valid
              |> Enum.flat_map(&(Map.get(host_refs, &1.email) || ["manual:" <> Map.fetch!(contact_ids, &1.email)]))
              |> tag_refs(tag_id)
            else
              0
            end

          %{added: added, existing: length(valid) - added, tagged: tagged, invalid: Enum.map(invalid, & &1.line)}
        end)

      {:ok, result}
    end
  end

  defp check_tag(nil), do: :ok

  defp check_tag(tag_id) do
    if valid_uuid?(tag_id) and repo().exists?(from t in Tag, where: t.id == ^tag_id),
      do: :ok,
      else: {:error, :unknown_tag}
  end

  defp insert_contacts(rows, actor) do
    now = now()

    rows
    |> Enum.map(fn r ->
      %{
        email: r.email,
        name: r.name && String.slice(r.name, 0, 120),
        added_by: actor,
        consent_note: "Consent confirmed by #{actor} (CSV import)",
        inserted_at: now,
        updated_at: now
      }
    end)
    |> Enum.chunk_every(1_000)
    |> Enum.map(&elem(repo().insert_all(Contact, &1, on_conflict: :nothing, conflict_target: :email), 0))
    |> Enum.sum()
  end

  defp contact_ids_by_email(emails) do
    emails
    |> Enum.chunk_every(5_000)
    |> Enum.flat_map(&repo().all(from c in Contact, where: c.email in ^&1, select: {c.email, c.id}))
    |> Map.new()
  end

  defp tag_refs(refs, tag_id) do
    now = now()

    refs
    |> Enum.uniq()
    |> Enum.map(&%{tag_id: tag_id, recipient_ref: &1, inserted_at: now})
    |> Enum.chunk_every(5_000)
    |> Enum.map(&elem(repo().insert_all(Tagging, &1, on_conflict: :nothing), 0))
    |> Enum.sum()
  end

  @doc "Removes a hand-added person and their tags. Doesn't suppress the address."
  def delete_contact(id) do
    if valid_uuid?(id) do
      repo().transaction(fn ->
        repo().delete_all(from t in Tagging, where: t.recipient_ref == ^("manual:" <> id))
        repo().delete_all(from c in Contact, where: c.id == ^id)
      end)
    else
      {:error, :invalid}
    end
  end

  defp contact_recipient(%Contact{} = c), do: %Recipient{ref: "manual:" <> c.id, email: c.email, name: c.name}

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
