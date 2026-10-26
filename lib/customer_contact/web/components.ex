defmodule CustomerContact.Web.Components do
  @moduledoc false
  # Self-contained components for the admin pages. Styled with Tailwind +
  # daisyUI classes; the host's app.css must @source this library.
  use Phoenix.Component

  alias Phoenix.LiveView.JS

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
          <svg
            xmlns="http://www.w3.org/2000/svg"
            viewBox="0 0 24 24"
            fill="none"
            stroke="currentColor"
            stroke-width="1.5"
            class="size-5"
            aria-hidden="true"
          >
            <path
              stroke-linecap="round"
              stroke-linejoin="round"
              d="m2.25 12 8.954-8.955a1.126 1.126 0 0 1 1.591 0L21.75 12M4.5 9.75v10.125c0 .621.504 1.125 1.125 1.125H9.75v-4.875c0-.621.504-1.125 1.125-1.125h2.25c.621 0 1.125.504 1.125 1.125V21h4.125c.621 0 1.125-.504 1.125-1.125V9.75M8.25 21h8.25"
            />
          </svg>
        </.link>
        <h1 class="text-xl font-semibold mr-4">Customer contact</h1>
        <.link navigate={@base} class={["btn btn-sm", if(@active == :campaigns, do: "btn-primary", else: "btn-ghost")]}>
          Campaigns
        </.link>
        <.link
          navigate={@base <> "/audience"}
          class={["btn btn-sm", if(@active == :audience, do: "btn-primary", else: "btn-ghost")]}
        >
          Audience
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
          <svg
            xmlns="http://www.w3.org/2000/svg"
            viewBox="0 0 24 24"
            fill="none"
            stroke="currentColor"
            stroke-width="1.5"
            class="size-5"
            aria-hidden="true"
          >
            <path
              stroke-linecap="round"
              stroke-linejoin="round"
              d="M9.879 7.519c1.171-1.025 3.071-1.025 4.242 0 1.172 1.025 1.172 2.687 0 3.712-.203.179-.43.326-.67.442-.745.361-1.45.999-1.45 1.827v.75M21 12a9 9 0 1 1-18 0 9 9 0 0 1 18 0Zm-9 5.25h.008v.008H12v-.008Z"
            />
          </svg>
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
              ✕
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
        ✕
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
