defmodule CustomerContact.Web.Components do
  @moduledoc false
  # Self-contained components for the admin pages. Styled with Tailwind +
  # daisyUI classes; the host's app.css must @source this library.
  use Phoenix.Component

  alias Phoenix.LiveView.JS

  # Heroicons (outline, 24px), inlined so host apps need no icon setup.
  @icons %{
    "home" =>
      "m2.25 12 8.954-8.955a1.126 1.126 0 0 1 1.591 0L21.75 12M4.5 9.75v10.125c0 .621.504 1.125 1.125 1.125H9.75v-4.875c0-.621.504-1.125 1.125-1.125h2.25c.621 0 1.125.504 1.125 1.125V21h4.125c.621 0 1.125-.504 1.125-1.125V9.75M8.25 21h8.25",
    "help" =>
      "M9.879 7.519c1.171-1.025 3.071-1.025 4.242 0 1.172 1.025 1.172 2.687 0 3.712-.203.179-.43.326-.67.442-.745.361-1.45.999-1.45 1.827v.75M21 12a9 9 0 1 1-18 0 9 9 0 0 1 18 0Zm-9 5.25h.008v.008H12v-.008Z",
    "campaigns" =>
      "M10.34 15.84c-.688-.06-1.386-.09-2.09-.09H7.5a4.5 4.5 0 1 1 0-9h.75c.704 0 1.402-.03 2.09-.09m0 9.18c.253.962.584 1.892.985 2.783.247.55.06 1.21-.463 1.511l-.657.38c-.551.318-1.26.117-1.527-.461a20.845 20.845 0 0 1-1.44-4.282m3.102.069a18.03 18.03 0 0 1-.59-4.59c0-1.586.205-3.124.59-4.59m0 9.18a23.848 23.848 0 0 1 8.835 2.535M10.34 6.66a23.847 23.847 0 0 0 8.835-2.535m0 0A23.74 23.74 0 0 0 18.795 3m.38 1.125a23.91 23.91 0 0 1 1.014 5.395m-1.014 8.855c-.118.38-.245.754-.38 1.125m.38-1.125a23.91 23.91 0 0 0 1.014-5.395m0-3.46c.495.413.811 1.035.811 1.73 0 .695-.316 1.317-.811 1.73m0-3.46a24.347 24.347 0 0 1 0 3.46",
    "audience" =>
      "M18 18.72a9.094 9.094 0 0 0 3.741-.479 3 3 0 0 0-4.682-2.72m.94 3.198.001.031c0 .225-.012.447-.037.666A11.944 11.944 0 0 1 12 21c-2.17 0-4.207-.576-5.963-1.584A6.062 6.062 0 0 1 6 18.719m12 0a5.971 5.971 0 0 0-.941-3.197m0 0A5.995 5.995 0 0 0 12 12.75a5.995 5.995 0 0 0-5.058 2.772m0 0a3 3 0 0 0-4.681 2.72 8.986 8.986 0 0 0 3.74.477m.94-3.197a5.971 5.971 0 0 0-.94 3.197M15 6.75a3 3 0 1 1-6 0 3 3 0 0 1 6 0Zm6 3a2.25 2.25 0 1 1-4.5 0 2.25 2.25 0 0 1 4.5 0Zm-13.5 0a2.25 2.25 0 1 1-4.5 0 2.25 2.25 0 0 1 4.5 0Z",
    "send" => "M6 12 3.269 3.125A59.769 59.769 0 0 1 21.485 12 59.768 59.768 0 0 1 3.27 20.875L5.999 12Zm0 0h7.5",
    "test" =>
      "M21.75 6.75v10.5a2.25 2.25 0 0 1-2.25 2.25h-15a2.25 2.25 0 0 1-2.25-2.25V6.75m19.5 0A2.25 2.25 0 0 0 19.5 4.5h-15a2.25 2.25 0 0 0-2.25 2.25m19.5 0v.243a2.25 2.25 0 0 1-1.07 1.916l-7.5 4.615a2.25 2.25 0 0 1-2.36 0L3.32 8.91a2.25 2.25 0 0 1-1.07-1.916V6.75",
    "plus" => "M12 4.5v15m7.5-7.5h-15",
    "save" => "m4.5 12.75 6 6 9-13.5",
    "approve" => "M9 12.75 11.25 15 15 9.75M21 12a9 9 0 1 1-18 0 9 9 0 0 1 18 0Z",
    "undo" => "M9 15 3 9m0 0 6-6M3 9h12a6 6 0 0 1 0 12h-3",
    "trash" =>
      "m14.74 9-.346 9m-4.788 0L9.26 9m9.968-3.21c.342.052.682.107 1.022.166m-1.022-.165L18.16 19.673a2.25 2.25 0 0 1-2.244 2.077H8.084a2.25 2.25 0 0 1-2.244-2.077L4.772 5.79m14.456 0a48.108 48.108 0 0 0-3.478-.397m-12 .562c.34-.059.68-.114 1.022-.165m0 0a48.11 48.11 0 0 1 3.478-.397m7.5 0v-.916c0-1.18-.91-2.164-2.09-2.201a51.964 51.964 0 0 0-3.32 0c-1.18.037-2.09 1.022-2.09 2.201v.916m7.5 0a48.667 48.667 0 0 0-7.5 0",
    "close" => "M6 18 18 6M6 6l12 12",
    "unsubscribe" =>
      "M22 10.5h-6m-2.25-4.125a3.375 3.375 0 1 1-6.75 0 3.375 3.375 0 0 1 6.75 0ZM4 19.235v-.11a6.375 6.375 0 0 1 12.75 0v.109A12.318 12.318 0 0 1 10.374 21c-2.331 0-4.512-.645-6.374-1.766Z",
    "resubscribe" =>
      "M18 7.5v3m0 0v3m0-3h3m-3 0h-3m-2.25-4.125a3.375 3.375 0 1 1-6.75 0 3.375 3.375 0 0 1 6.75 0ZM3 19.235v-.11a6.375 6.375 0 0 1 12.75 0v.109A12.318 12.318 0 0 1 9.374 21c-2.331 0-4.512-.645-6.374-1.766Z",
    "block" => "M18.364 18.364A9 9 0 0 0 5.636 5.636m12.728 12.728A9 9 0 0 1 5.636 5.636m12.728 12.728L5.636 5.636",
    "tag" =>
      "M9.568 3H5.25A2.25 2.25 0 0 0 3 5.25v4.318c0 .597.237 1.17.659 1.591l9.581 9.581c.699.699 1.78.872 2.607.33a18.095 18.095 0 0 0 5.223-5.223c.542-.827.369-1.908-.33-2.607L11.16 3.66A2.25 2.25 0 0 0 9.568 3ZM6 6h.008v.008H6V6Z",
    "refresh" =>
      "M16.023 9.348h4.992v-.001M2.985 19.644v-4.992m0 0h4.992m-4.993 0 3.181 3.183a8.25 8.25 0 0 0 13.803-3.7M4.031 9.865a8.25 8.25 0 0 1 13.803-3.7l3.181 3.182m0-4.991v4.99",
    "report" =>
      "M3 13.125C3 12.504 3.504 12 4.125 12h2.25c.621 0 1.125.504 1.125 1.125v6.75C7.5 20.496 6.996 21 6.375 21h-2.25A1.125 1.125 0 0 1 3 19.875v-6.75ZM9.75 8.625c0-.621.504-1.125 1.125-1.125h2.25c.621 0 1.125.504 1.125 1.125v11.25c0 .621-.504 1.125-1.125 1.125h-2.25a1.125 1.125 0 0 1-1.125-1.125V8.625ZM16.5 4.125c0-.621.504-1.125 1.125-1.125h2.25C20.496 3 21 3.504 21 4.125v15.75c0 .621-.504 1.125-1.125 1.125h-2.25a1.125 1.125 0 0 1-1.125-1.125V4.125Z",
    "edit" =>
      "m16.862 4.487 1.687-1.688a1.875 1.875 0 1 1 2.652 2.652L10.582 16.07a4.5 4.5 0 0 1-1.897 1.13L6 18l.8-2.685a4.5 4.5 0 0 1 1.13-1.897l8.932-8.931Zm0 0L19.5 7.125M18 14v4.75A2.25 2.25 0 0 1 15.75 21H5.25A2.25 2.25 0 0 1 3 18.75V8.25A2.25 2.25 0 0 1 5.25 6H10",
    "more" => "m19.5 8.25-7.5 7.5-7.5-7.5"
  }

  attr :name, :string, required: true, values: Map.keys(@icons)
  attr :class, :string, default: "size-4"

  def icon(assigns) do
    assigns = assign(assigns, :path, Map.fetch!(@icons, assigns.name))

    ~H"""
    <svg
      xmlns="http://www.w3.org/2000/svg"
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      stroke-width="1.5"
      class={["shrink-0", @class]}
      aria-hidden="true"
    >
      <path stroke-linecap="round" stroke-linejoin="round" d={@path} />
    </svg>
    """
  end

  attr :flash, :map, required: true
  attr :base, :string, required: true
  attr :home, :string, default: "/"
  attr :active, :atom, required: true
  slot :inner_block, required: true
  slot :help, doc: "A short guide to the page, shown by the help icon in the header."

  def shell(assigns) do
    ~H"""
    <div class="mx-auto max-w-6xl px-4 py-6">
      <div class="flex flex-wrap items-center gap-2 mb-6">
        <.link href={@home} class="btn btn-sm btn-ghost btn-square" title="Home" aria-label="Home" id="cc-home">
          <.icon name="home" class="size-5" />
        </.link>
        <h1 class="text-xl font-semibold mr-4">Customer contact</h1>
        <.link navigate={@base} class={["btn btn-sm", if(@active == :campaigns, do: "btn-primary", else: "btn-ghost")]}>
          <.icon name="campaigns" /> Campaigns
        </.link>
        <.link
          navigate={@base <> "/sent"}
          class={["btn btn-sm", if(@active == :sent, do: "btn-primary", else: "btn-ghost")]}
        >
          <.icon name="send" /> Sent
        </.link>
        <.link
          navigate={@base <> "/audience"}
          class={["btn btn-sm", if(@active == :audience, do: "btn-primary", else: "btn-ghost")]}
        >
          <.icon name="audience" /> Audience
        </.link>
        <div class="grow"></div>
        <button
          :if={@help != []}
          type="button"
          phx-click={JS.toggle(to: "#cc-help")}
          class="btn btn-sm btn-ghost btn-square"
          title="Help"
          aria-label="Help"
          aria-controls="cc-help"
          id="cc-help-toggle"
        >
          <.icon name="help" class="size-5" />
        </button>
      </div>
      <div :if={@help != []} id="cc-help" class="hidden card bg-base-200 border border-base-300 mb-6">
        <div class="card-body p-4 text-sm">
          <div class="flex items-center">
            <h2 class="font-semibold grow">How this page works</h2>
            <button
              type="button"
              phx-click={JS.hide(to: "#cc-help")}
              class="btn btn-ghost btn-xs"
              aria-label="Close help"
            >
              <.icon name="close" />
            </button>
          </div>
          {render_slot(@help)}
        </div>
      </div>
      <div :if={msg = Phoenix.Flash.get(@flash, :info)} role="alert" class="alert alert-success mb-4" id="cc-flash-info">
        {msg}
      </div>
      <div :if={msg = Phoenix.Flash.get(@flash, :error)} role="alert" class="alert alert-error mb-4" id="cc-flash-error">
        {msg}
      </div>
      {render_slot(@inner_block)}
      <%!-- The same messages, pinned to the corner of the screen: the buttons that
           cause them are often scrolled well below the alerts above. --%>
      <div class="toast toast-end toast-bottom z-50">
        <.toast flash={@flash} kind={:info} class="alert-success" />
        <.toast flash={@flash} kind={:error} class="alert-error" />
      </div>
    </div>
    """
  end

  attr :flash, :map, required: true
  attr :kind, :atom, required: true
  attr :class, :string, required: true

  defp toast(assigns) do
    ~H"""
    <div
      :if={msg = Phoenix.Flash.get(@flash, @kind)}
      role="alert"
      class={["alert shadow-lg max-w-sm", @class]}
      id={"cc-toast-#{@kind}"}
    >
      <span>{msg}</span>
      <button
        type="button"
        class="btn btn-ghost btn-xs"
        aria-label="Dismiss"
        phx-click={JS.push("lv:clear-flash", value: %{key: @kind})}
      >
        <.icon name="close" />
      </button>
    </div>
    """
  end

  attr :status, :string, required: true

  def status_badge(assigns) do
    ~H"""
    <span class={["badge", badge_class(@status)]}>{@status}</span>
    """
  end

  defp badge_class("draft"), do: "badge-ghost"
  defp badge_class("approved"), do: "badge-info"
  defp badge_class("sending"), do: "badge-warning"
  defp badge_class(s) when s in ["sent", "delivered"], do: "badge-success"
  defp badge_class(s) when s in ["bounced", "complained", "failed"], do: "badge-error"
  defp badge_class(_), do: "badge-neutral"

  attr :field, Phoenix.HTML.FormField, required: true
  attr :label, :string, required: true
  attr :type, :string, default: "text"
  attr :rest, :global, include: ~w(placeholder rows phx-debounce disabled)

  def input(%{type: "textarea"} = assigns) do
    ~H"""
    <fieldset class="fieldset">
      <label class="label" for={@field.id}>{@label}</label>
      <textarea id={@field.id} name={@field.name} class="textarea w-full font-mono text-xs" {@rest}>{Phoenix.HTML.Form.normalize_value("textarea", @field.value)}</textarea>
      <.errors field={@field} />
    </fieldset>
    """
  end

  def input(assigns) do
    ~H"""
    <fieldset class="fieldset">
      <label class="label" for={@field.id}>{@label}</label>
      <input type={@type} id={@field.id} name={@field.name} value={@field.value} class="input w-full" {@rest} />
      <.errors field={@field} />
    </fieldset>
    """
  end

  attr :field, Phoenix.HTML.FormField, required: true

  defp errors(assigns) do
    ~H"""
    <p
      :for={{msg, opts} <- if(Phoenix.Component.used_input?(@field), do: @field.errors, else: [])}
      class="text-error text-sm"
    >
      {translate(msg, opts)}
    </p>
    """
  end

  defp translate(msg, opts) do
    Enum.reduce(opts, msg, fn {key, value}, acc ->
      String.replace(acc, "%{#{key}}", fn _ -> to_string(value) end)
    end)
  end

  def format_time(nil), do: "—"
  def format_time(%DateTime{} = dt), do: Calendar.strftime(dt, "%Y-%m-%d %H:%M UTC")

  def percent(_n, 0), do: "—"
  def percent(n, total), do: "#{Float.round(n * 100 / total, 1)}%"
end
