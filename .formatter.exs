[
  import_deps: [:ecto, :ecto_sql, :phoenix, :plug],
  plugins: [Phoenix.LiveView.HTMLFormatter],
  inputs: ["*.{heex,ex,exs}", "{config,lib,test}/**/*.{heex,ex,exs}"],
  line_length: 120,
  locals_without_parens: [customer_contact_admin: 1, customer_contact_admin: 2],
  export: [locals_without_parens: [customer_contact_admin: 1, customer_contact_admin: 2]]
]
