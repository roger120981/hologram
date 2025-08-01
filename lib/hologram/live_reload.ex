defmodule Hologram.LiveReload do
  @moduledoc false

  use GenServer

  alias Hologram.Assets.ManifestCache
  alias Hologram.Assets.PageDigestRegistry
  alias Hologram.Assets.PathRegistry
  alias Hologram.Reflection
  alias Hologram.Router.PageModuleResolver

  # in milliseconds
  @debounce_delay 1_000

  @doc """
  Starts live reload process.
  """
  @spec start_link(keyword) :: GenServer.on_start()
  def start_link(_opts) do
    GenServer.start_link(__MODULE__, nil)
  end

  @impl GenServer
  def init(_opts) do
    {:ok, pid} =
      :os.type()
      |> watcher_opts()
      |> FileSystem.start_link()

    FileSystem.subscribe(pid)

    {:ok, %{endpoint: Reflection.phoenix_endpoint(), timer_ref: nil}}
  end

  @impl GenServer
  def handle_info({:file_event, _pid, :stop}, state) do
    {:noreply, state}
  end

  @impl GenServer
  def handle_info({:file_event, _pid, {_file_path, [:renamed]}}, state) do
    {:noreply, state}
  end

  @impl GenServer
  def handle_info({:file_event, _pid, {file_path, _events}}, state) do
    if state.timer_ref, do: Process.cancel_timer(state.timer_ref)

    # File change events are debounced to avoid multiple recompilations
    # when the same file is modified multiple times in quick succession.
    timer_ref = Process.send_after(self(), {:debounced_reload, file_path}, @debounce_delay)

    {:noreply, %{state | timer_ref: timer_ref}}
  end

  @impl GenServer
  def handle_info({:debounced_reload, modified_file_path}, state) do
    recompiled_file_path =
      case Path.extname(modified_file_path) do
        ".ex" ->
          modified_file_path

        ".holo" ->
          ex_file = Path.rootname(modified_file_path) <> ".ex"
          if File.exists?(ex_file), do: ex_file

        _fallback ->
          nil
      end

    if recompiled_file_path do
      reload(recompiled_file_path, state.endpoint)
    end

    {:noreply, %{state | timer_ref: nil}}
  end

  @doc """
  Returns the debounce delay in milliseconds.
  """
  @spec debounce_delay :: pos_integer
  def debounce_delay, do: @debounce_delay

  @doc """
  Returns the list of directories that are watched for file changes.

  The directories are determined by the project's `:elixirc_paths` configuration
  and are converted to absolute paths based on the project root directory.
  """
  @spec watched_dirs :: [String.t()]
  def watched_dirs do
    root_dir = Reflection.root_dir()
    compiled_paths = Mix.Project.get().project()[:elixirc_paths]
    Enum.map(compiled_paths, &Path.join(root_dir, &1))
  end

  @doc """
  Returns file watcher options based on the operating system type.

  For macOS (Darwin), additional options are added for optimal performance:
  - `latency: 0` for immediate file change detection
  - `no_defer: true` to avoid deferring events

  For other operating systems, only the directories to watch are specified.
  """
  @spec watcher_opts({atom, atom}) :: keyword
  def watcher_opts({:unix, :darwin}) do
    [dirs: watched_dirs(), latency: 0, no_defer: true]
  end

  def watcher_opts(_os_type) do
    [dirs: watched_dirs()]
  end

  defp broadcast_compilation_error(output) do
    Phoenix.PubSub.broadcast(
      Hologram.PubSub,
      "hologram_live_reload",
      {:compilation_error, output}
    )
  end

  defp broadcast_reload do
    Phoenix.PubSub.broadcast(Hologram.PubSub, "hologram_live_reload", :reload)
  end

  defp recompile_hologram do
    # credo:disable-for-next-line Credo.Check.Design.AliasUsage
    Mix.Tasks.Compile.Hologram.run([])
  end

  defp reload(_file_path, endpoint) do
    case reload_code(endpoint) do
      :ok ->
        recompile_hologram()
        reload_runtime()
        broadcast_reload()

      {:error, output} ->
        broadcast_compilation_error(output)
    end
  end

  defp reload_code(endpoint) do
    Phoenix.CodeReloader.reload(endpoint)

    # TODO: this will be used in Hologram standalone version
    # Code.put_compiler_option(:ignore_module_conflict, true)
    # Kernel.ParallelCompiler.compile_to_path([file_path], Mix.Project.compile_path())
    # Code.put_compiler_option(:ignore_module_conflict, false)
  end

  defp reload_runtime do
    PageModuleResolver.reload()
    PathRegistry.reload()
    ManifestCache.reload()
    PageDigestRegistry.reload()
  end
end
