defmodule CustomerContact.SNS do
  @moduledoc """
  Verifies Amazon SNS messages before they are trusted.

  A message is accepted only if:

    * its `TopicArn` is listed in `config :customer_contact, sns_topic_arns: [...]`
      (anyone can create an SNS topic and have AWS sign messages for it, so
      the signature alone proves nothing about who sent it);
    * its signing certificate URL is exactly
      `https://sns.<topic region>.amazonaws.com/SimpleNotificationService-<id>.pem`
      (no query, fragment or userinfo; the region comes from the allow-listed
      TopicArn, so look-alike hosts such as S3 buckets are rejected); and
    * the RSA signature over the canonical string verifies against that
      certificate.
  """

  require Record

  Record.defrecordp(
    :otp_cert,
    :OTPCertificate,
    Record.extract(:OTPCertificate, from_lib: "public_key/include/public_key.hrl")
  )

  Record.defrecordp(
    :otp_tbs,
    :OTPTBSCertificate,
    Record.extract(:OTPTBSCertificate, from_lib: "public_key/include/public_key.hrl")
  )

  Record.defrecordp(
    :otp_spki,
    :OTPSubjectPublicKeyInfo,
    Record.extract(:OTPSubjectPublicKeyInfo, from_lib: "public_key/include/public_key.hrl")
  )

  @arn ~r/\Aarn:(aws|aws-cn|aws-us-gov):sns:([a-z0-9-]+):\d{12}:[A-Za-z0-9_-]+\z/
  @cert_path ~r/\A\/SimpleNotificationService-[A-Za-z0-9]+\.pem\z/

  # Signed messages older than this are refused, so a captured message can't
  # be replayed later (SNS retries well within an hour).
  @max_age_seconds 3_600
  # Certificates not yet cached may be fetched at most this often per
  # minute, so forged messages naming made-up certificate files can't make
  # the app hammer AWS. Real certificates are cached after the first fetch.
  @cert_fetches_per_minute 10

  @notification_keys ~w(Message MessageId Subject Timestamp TopicArn Type)
  @subscription_keys ~w(Message MessageId SubscribeURL Timestamp Token TopicArn Type)

  def verify(%{"Type" => type, "TopicArn" => arn} = msg)
      when type in ["Notification", "SubscriptionConfirmation", "UnsubscribeConfirmation"] do
    with :ok <- check_strings(msg),
         :ok <- check_topic(arn),
         :ok <- check_timestamp(msg["Timestamp"]),
         {:ok, host} <- sns_host(arn),
         {:ok, digest} <- digest(msg["SignatureVersion"]),
         {:ok, cert_url} <- aws_url(msg["SigningCertURL"], host, @cert_path),
         {:ok, signature} <- decode_signature(msg["Signature"]),
         {:ok, key} <- public_key(cert_url) do
      if :public_key.verify(string_to_sign(msg), digest, signature, key), do: :ok, else: {:error, :bad_signature}
    end
  end

  def verify(_), do: {:error, :malformed}

  @doc "Confirms a verified SubscriptionConfirmation by visiting its SubscribeURL."
  def confirm_subscription(%{"SubscribeURL" => url, "TopicArn" => arn}) do
    with {:ok, host} <- sns_host(arn),
         {:ok, url} <- aws_url(url, host, nil, allow_query: true),
         {:ok, %{status: 200}} <-
           Req.get(url, retry: false, redirect: false, connect_options: [timeout: 3_000], receive_timeout: 5_000) do
      :ok
    else
      _ -> {:error, :confirm_failed}
    end
  end

  @doc false
  def string_to_sign(%{"Type" => type} = msg) do
    keys = if type == "Notification", do: @notification_keys, else: @subscription_keys

    keys
    |> Enum.filter(&Map.has_key?(msg, &1))
    |> Enum.map_join(fn key -> "#{key}\n#{msg[key]}\n" end)
  end

  defp check_topic(arn) do
    if arn in CustomerContact.sns_topic_arns(), do: :ok, else: {:error, :topic_not_allowed}
  end

  defp check_timestamp(timestamp) when is_binary(timestamp) do
    with {:ok, sent_at, _} <- DateTime.from_iso8601(timestamp),
         age when age <= @max_age_seconds and age >= -300 <- DateTime.diff(DateTime.utc_now(), sent_at) do
      :ok
    else
      _ -> {:error, :stale}
    end
  end

  defp check_timestamp(_), do: {:error, :stale}

  defp digest("1"), do: {:ok, :sha}
  defp digest("2"), do: {:ok, :sha256}
  defp digest(_), do: {:error, :bad_signature_version}

  defp decode_signature(sig) when is_binary(sig) do
    case Base.decode64(sig) do
      {:ok, bin} -> {:ok, bin}
      :error -> {:error, :bad_signature}
    end
  end

  defp decode_signature(_), do: {:error, :bad_signature}

  # Every signed field must be a string (form-encoded or odd JSON bodies
  # would otherwise crash string_to_sign/1).
  defp check_strings(msg) do
    if Enum.all?(@subscription_keys ++ @notification_keys ++ ~w(Signature SigningCertURL SignatureVersion), fn key ->
         not Map.has_key?(msg, key) or is_binary(msg[key])
       end),
       do: :ok,
       else: {:error, :malformed}
  end

  defp sns_host(arn) do
    case Regex.run(@arn, arn) do
      [_, "aws-cn", region] -> {:ok, "sns.#{region}.amazonaws.com.cn"}
      [_, _partition, region] -> {:ok, "sns.#{region}.amazonaws.com"}
      _ -> {:error, :bad_topic_arn}
    end
  end

  defp aws_url(url, expected_host, path_pattern, opts \\ [])

  defp aws_url(url, expected_host, path_pattern, opts) when is_binary(url) do
    case URI.parse(url) do
      %URI{scheme: "https", host: ^expected_host, port: 443, userinfo: nil, fragment: nil, path: path, query: query}
      when is_binary(path) ->
        cond do
          query != nil and not Keyword.get(opts, :allow_query, false) -> {:error, :bad_url}
          path_pattern != nil and not Regex.match?(path_pattern, path) -> {:error, :bad_url}
          true -> {:ok, url}
        end

      _ ->
        {:error, :bad_url}
    end
  end

  defp aws_url(_, _, _, _), do: {:error, :bad_url}

  defp public_key(url) do
    case :persistent_term.get({__MODULE__, url}, nil) do
      nil ->
        with :ok <- allow_cert_fetch(), {:ok, pem} <- fetch_cert(url), {:ok, key} <- key_from_pem(pem) do
          :persistent_term.put({__MODULE__, url}, key)
          {:ok, key}
        end

      key ->
        {:ok, key}
    end
  end

  # A fixed-window counter shared by all request processes.
  defp allow_cert_fetch do
    counter = cert_fetch_counter()
    window = System.monotonic_time(:second) |> div(60)
    current = :atomics.get(counter, 1)

    if current != window and :atomics.compare_exchange(counter, 1, current, window) == :ok do
      :atomics.put(counter, 2, 0)
    end

    if :atomics.add_get(counter, 2, 1) <= @cert_fetches_per_minute, do: :ok, else: {:error, :cert_fetch_limited}
  end

  defp cert_fetch_counter do
    case :persistent_term.get({__MODULE__, :cert_fetches}, nil) do
      nil ->
        counter = :atomics.new(2, signed: true)
        :atomics.put(counter, 1, System.monotonic_time(:second) |> div(60))
        :persistent_term.put({__MODULE__, :cert_fetches}, counter)
        counter

      counter ->
        counter
    end
  end

  defp fetch_cert(url) do
    fetcher = Application.get_env(:customer_contact, :sns_cert_fetcher, &http_get/1)
    fetcher.(url)
  end

  defp http_get(url) do
    case Req.get(url, retry: false, redirect: false, connect_options: [timeout: 3_000], receive_timeout: 5_000) do
      {:ok, %{status: 200, body: body}} when is_binary(body) -> {:ok, body}
      _ -> {:error, :cert_unavailable}
    end
  end

  @doc false
  def key_from_pem(pem) do
    with [{:Certificate, der, _} | _] <- :public_key.pem_decode(pem),
         otp_cert(tbsCertificate: tbs) <- :public_key.pkix_decode_cert(der, :otp),
         otp_tbs(subjectPublicKeyInfo: spki) <- tbs,
         otp_spki(subjectPublicKey: key) <- spki do
      {:ok, key}
    else
      _ -> {:error, :bad_cert}
    end
  rescue
    _ -> {:error, :bad_cert}
  end
end
