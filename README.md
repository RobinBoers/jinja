# Jinja

<!-- DOCS HERE -->

Jinja is a fast, expressive, extensible templating engine written in Python.

This library provides a public API for working with Jinja templates in Elixir.
This is not a port of Jinja, but rather a wrapper that runs using `Pythonx`.

See <https://jinja.palletsprojects.com/en/stable/templates/> for a guide on
template syntax.

## Usage

Add `Jinja` to your application supervision tree:

```elixir
children = [
  Jinja,
  ...
]
```

## Loaders

The default loader is `:dict`. This allows you to register templates at runtime,
for the lifetime of your application. Templates can be loaded and rendered as such:

```elixir
Jinja.load_template("hello", "hewwo {{ name }}") # => :ok
Jinja.render_template("hello", %{name: "Robin"}) # => {:ok, "hewwo Robin"}
```

The `:path` loader allows you to specify a directory on disk to load templates
from. When configured, the `load_template/2` function will be unavailable.

```elixir
children = [
  {Jinja,
    loader: :path,
    from: Application.app_dir(:your_app, ~w(lib your_app_web templates))
  }
]

# Loads template from lib/your_app_web/templates/hello.html
iex> Jinja.render_template("hello.html", %{name: "Robin"})
{:ok, "hewwo Robin"}

# `load_template/2` is unavailable for loader: :path
iex> Jinja.load_template("bye", "...")
{:error, "loading templates at runtime is only supported for loader: :dict"}
```
