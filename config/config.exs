import Config

# The library itself is configured by the host app. This file only sets up
# the library's own test environment.
if config_env() == :test, do: import_config("test.exs")
