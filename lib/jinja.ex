defmodule Jinja do
  @readme Path.expand("../README.md", __DIR__)
  @external_resource @readme
  @moduledoc @readme
             |> File.read!()
             |> String.split("<!-- DOCS HERE -->")
             |> List.last()
             |> String.trim()

  use GenServer

  defstruct [:loader, :globals]

  import Structo

  @doc false
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Renders a template string with given assigns.

      iex> Jinja.render_string("<h1>hewwo {{ name }}</h1>", %{"name" => "world"})
      {:ok, "<h1>hewwo world</h1>"}

  """
  @spec render_string(String.t(), map()) :: {:ok, String.t()} | {:error, term()}
  def render_string(template, assigns \\ %{}) when is_binary(template) and is_map(assigns) do
    GenServer.call(__MODULE__, {:render_string, template, assigns})
  end

  @doc """
  Loads a template with the given name and source.

      iex> Jinja.load_template("page", \"""
      <html><body>{% block body %}{% endblock %}</body></html>
      \""")
      :ok

      iex> Jinja.load_template("post", \"""
      {% extends "page" %}
      {% block body %}
        {{ title }}
      {% endblock %}
      \""")
      :ok

  """
  @spec load_template(String.t(), String.t()) :: :ok | {:error, term()}
  def load_template(name, source) when is_binary(name) and is_binary(source) do
    GenServer.call(__MODULE__, {:load_template, name, source})
  end

  @doc """
  Renders a previously loaded template with given assigns.

      iex> Jinja.render_template("post", %{title: "hewwo world"})
      {:ok, "<html><body>hewwo world</body></html>"}

  """
  @spec load_template(String.t(), map()) :: {:ok, String.t()} | {:error, term()}
  def render_template(name, assigns \\ %{}) when is_binary(name) and is_map(assigns) do
    GenServer.call(__MODULE__, {:render_template, name, assigns})
  end

  @doc false
  def init(opts) do
    ensure_python_initialized()
    {loader, globals} = init_state(opts)
    {:ok, ~m{:__MODULE__, loader, globals}}
  end

  defp ensure_python_initialized do
    if toml = Application.get_env(:pythonx, :pyproject_toml) do
      if String.contains?(toml, "Jinja2") do
        :ok
      else
        raise "Please add Jinja2 to your :pyproject_toml config for Pythonx"
      end
    else
      try do
        Pythonx.eval("1 + 1", %{})
        :ok
      rescue
        _ ->
          Pythonx.uv_init("""
          [project]
          name = "jinja-elixir"
          version = "#{Application.spec(:jinja, :vsn)}"
          requires-python = "==3.13.*"
          dependencies = [
            "Jinja2==3.1.6"
          ]
          """)
      end
    end
  end

  defp init_state(opts) do
    case Keyword.get(opts, :loader, :dict) do
      :dict -> {:dict, init_dict_loader()}
      :path -> {:path, init_path_loader(opts)}
    end
  rescue
    e ->
      raise "Failed to initialize Jinja. Make sure Pythonx is configured with the Jinja2 dependency. Got: #{inspect(e)}"
  end

  defp init_dict_loader do
    initialise("""
    from jinja2 import Environment, DictLoader, select_autoescape

    templates = {}
    loader = DictLoader(templates)

    env = Environment(
      loader=loader,
      autoescape=select_autoescape(['html', 'htm', 'xml'])
    )
    """)
  end

  defp init_path_loader(opts) do
    search_path =
      Keyword.get(opts, :from) ||
        raise "when using loader: :path, please provide the search path via the :from option"

    initialise("""
    from jinja2 import Environment, FileSystemLoader, select_autoescape

    env = Environment(
      loader=FileSystemLoader('#{search_path}'),
      autoescape=select_autoescape(['html', 'htm', 'xml'])
    )
    """)
  end

  def handle_call({:render_string, template, assigns}, _from, state) do
    globals =
      state.globals
      |> put_glob(:source, template)
      |> put_glob(:assigns, assigns)

    rendered =
      execute(globals, """
      env.from_string(source).render(assigns)
      """)

    {:reply, {:ok, rendered}, state}
  rescue
    error -> {:reply, {:error, error}, state}
  end

  def handle_call({:load_template, name, source}, _from, %{loader: :dict} = state) do
    globals =
      state.globals
      |> put_glob(:name, name)
      |> put_glob(:source, source)

    execute(globals, """
    templates[name] = source
    env.loader = DictLoader(templates)
    True
    """)

    {:reply, :ok, state}
  rescue
    error -> {:reply, {:error, error}, state}
  end

  def handle_call({:load_template, _name, _source}, _from, %{loader: :path} = state) do
    {:reply, {:error, "loading templates at runtime is only supported for loader: :dict"}, state}
  end

  def handle_call({:render_template, name, assigns}, _from, state) do
    globals =
      state.globals
      |> put_glob(:name, name)
      |> put_glob(:assigns, assigns)

    rendered = execute(globals, "env.get_template(name).render(assigns)")

    {:reply, {:ok, rendered}, state}
  rescue
    error -> {:reply, {:error, error}, state}
  end

  defp initialise(source) do
    source
    |> Pythonx.eval(%{})
    |> then(fn {_, g} -> g end)
  end

  defp execute(globals, source) do
    source
    |> Pythonx.eval(globals)
    |> then(fn {r, _} -> r end)
    |> Pythonx.decode()
  end

  defp put_glob(globals, name, value) do
    Map.put(globals, to_string(name), Pythonx.encode!(value))
  end
end

Code.compiler_options(ignore_module_conflict: true)

defimpl Pythonx.Encoder, for: BitString do
  def encode(string, _opts) do
    Pythonx.NIF.unicode_from_string(string)
  end
end
