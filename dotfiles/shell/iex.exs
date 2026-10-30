# IEx Configuration for Elite Elixir Development
# Symlink this to ~/.iex.exs

# Auto-import common modules for convenience
import_if_available(Ecto.Query)
import_if_available(Ecto.Changeset)

# Custom helper functions
defmodule IExHelpers do
  @moduledoc """
  Custom helper functions for IEx sessions.
  """

  @doc "Print all available routes (Phoenix)"
  def routes do
    if Code.ensure_loaded?(Mix.Tasks.Phx.Routes) do
      Mix.Tasks.Phx.Routes.run([])
    else
      IO.puts("Phoenix routes not available in this project")
    end
  end

  @doc "Reload all modules"
  def reload! do
    Mix.Task.reenable("compile.elixir")
    Application.stop(Mix.Project.config()[:app])
    Mix.Task.run("compile.elixir")
    Application.start(Mix.Project.config()[:app])
  end

  @doc "Clear the console"
  def clear do
    IO.write([IO.ANSI.home(), IO.ANSI.clear()])
  end

  @doc "Print the last `n` lines of history"
  def history(n \\ 20) do
    history = IEx.History.queue() |> Enum.take(-n)

    Enum.each(history, fn {counter, command} ->
      IO.puts("#{counter}: #{command}")
    end)
  end

  @doc "Pretty print with syntax highlighting"
  def pp(term) do
    term
    |> inspect(pretty: true, width: 80)
    |> IO.puts()
  end

  @doc "Time how long a function takes to execute"
  def time(fun) when is_function(fun) do
    {microseconds, result} = :timer.tc(fun)
    IO.puts("Time: #{microseconds / 1_000_000} seconds")
    result
  end

  @doc "Get application environment"
  def env(app) when is_atom(app) do
    Application.get_all_env(app)
  end

  @doc "List all running applications"
  def apps do
    Application.started_applications()
    |> Enum.map(fn {app, _desc, _vsn} -> app end)
    |> Enum.sort()
  end

  @doc "Check database connection (Ecto)"
  def db_check do
    if Code.ensure_loaded?(Ecto) do
      repo = Application.get_env(:phoenix, :ecto_repos, []) |> List.first()

      if repo do
        case repo.query("SELECT 1") do
          {:ok, _} -> IO.puts("✅ Database connection OK")
          {:error, error} -> IO.puts("❌ Database error: #{inspect(error)}")
        end
      else
        IO.puts("No Ecto repo configured")
      end
    else
      IO.puts("Ecto not available")
    end
  end
end

# Import helpers into IEx
import IExHelpers

# Pretty printing configuration
IEx.configure(
  colors: [
    syntax_colors: [
      number: :yellow,
      atom: :cyan,
      string: :green,
      boolean: :magenta,
      nil: [:magenta, :bright]
    ],
    ls_directory: :cyan,
    ls_device: :yellow,
    doc_code: :green,
    doc_inline_code: :magenta,
    doc_headings: [:cyan, :underline],
    doc_title: [:cyan, :bright, :underline]
  ],
  default_prompt:
    "#{IO.ANSI.green()}%prefix#{IO.ANSI.reset()} " <>
      "[#{IO.ANSI.cyan()}%counter#{IO.ANSI.reset()}] >",
  alive_prompt:
    "#{IO.ANSI.green()}%prefix#{IO.ANSI.reset()} " <>
      "(#{IO.ANSI.yellow()}%node#{IO.ANSI.reset()}) " <>
      "[#{IO.ANSI.cyan()}%counter#{IO.ANSI.reset()}] >",
  history_size: 500,
  inspect: [
    pretty: true,
    limit: :infinity,
    width: 80
  ]
)

# Startup message
IO.puts("""

#{IO.ANSI.cyan()}╔══════════════════════════════════════════════════════════════╗
║              Elite Elixir IEx Environment                    ║
╚══════════════════════════════════════════════════════════════╝#{IO.ANSI.reset()}

#{IO.ANSI.green()}Available helpers:#{IO.ANSI.reset()}
  • routes()      - Show Phoenix routes
  • reload!()     - Reload all modules
  • clear()       - Clear console
  • history(n)    - Show last n history items
  • pp(term)      - Pretty print
  • time(fun)     - Time function execution
  • env(app)      - Get app environment
  • apps()        - List running applications
  • db_check()    - Test database connection

#{IO.ANSI.yellow()}Auto-imported:#{IO.ANSI.reset()}
  • Ecto.Query
  • Ecto.Changeset
""")

# Helper to conditionally import modules
defp import_if_available(module) do
  Code.ensure_loaded?(module) && import(module)
end
