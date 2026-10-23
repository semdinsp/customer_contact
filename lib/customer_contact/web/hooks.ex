defmodule CustomerContact.Web.Hooks do
  @moduledoc false
  import Phoenix.Component, only: [assign: 3]

  def on_mount({:base_path, base}, _params, _session, socket) do
    {:cont,
     socket
     |> assign(:cc_base, String.trim_trailing(base, "/"))
     |> assign(:cc_actor, actor(socket.assigns))}
  end

  # Identifies the admin in the audit fields (tested_by, approved_by, ...).
  # Works with phx.gen.auth scopes (`current_scope.user`) and the older
  # `current_user` assign.
  defp actor(%{current_scope: %{user: %{email: email}}}) when is_binary(email), do: email
  defp actor(%{current_user: %{email: email}}) when is_binary(email), do: email
  defp actor(_), do: "unknown admin"
end
