defmodule StreamystatServer.SyncTask do
  use GenServer
  alias StreamystatServer.JellyfinSync
  alias StreamystatServer.Servers
  alias StreamystatServer.Servers.Server
  alias StreamystatServer.Servers.SyncLog
  alias StreamystatServer.Repo
  require Logger

  @type server_id :: String.t()
  @type sync_type :: String.t()
  @type sync_result :: {:ok, Server.t()} | {:error, atom()}

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    {:ok, task_supervisor} = Task.Supervisor.start_link()
    schedule_full_sync()
    schedule_partial_sync()
    {:ok, %{task_supervisor: task_supervisor}}
  end

  @spec partial_sync(server_id()) :: :ok
  def partial_sync(server_id),
    do: GenServer.cast(__MODULE__, {:partial_sync, server_id})

  @spec full_sync(server_id()) :: :ok
  def full_sync(server_id), do: GenServer.cast(__MODULE__, {:full_sync, server_id})

  @spec sync_users(server_id()) :: :ok
  def sync_users(server_id), do: GenServer.cast(__MODULE__, {:sync_users, server_id})

  @spec sync_libraries(server_id()) :: :ok
  def sync_libraries(server_id), do: GenServer.cast(__MODULE__, {:sync_libraries, server_id})

  @spec sync_items(server_id()) :: :ok
  def sync_items(server_id), do: GenServer.cast(__MODULE__, {:sync_items, server_id})

  @spec sync_playback_stats(server_id()) :: :ok
  def sync_playback_stats(server_id),
    do: GenServer.cast(__MODULE__, {:sync_playback_stats, server_id})

  @impl true
  def handle_cast({sync_type, server_id}, %{task_supervisor: supervisor} = state)
      when sync_type in [
             :partial_sync,
             :full_sync,
             :sync_users,
             :sync_libraries,
             :sync_items,
             :sync_playback_stats
           ] do
    Task.Supervisor.async_nolink(supervisor, fn ->
      result = perform_sync(sync_type, server_id)
      update_sync_timestamp(server_id, Atom.to_string(sync_type), result)
    end)

    {:noreply, state}
  end

  @impl true
  def handle_info({ref, _result}, state) do
    # We don't care about the result, so we just remove the DOWN message from the mailbox
    Process.demonitor(ref, [:flush])
    {:noreply, state}
  end

  @impl true
  def handle_info(:sync, %{task_supervisor: supervisor} = state) do
    Task.Supervisor.async_nolink(supervisor, fn ->
      Servers.list_servers()
      |> Enum.each(fn server ->
        result = perform_sync(:full_sync, server.id)
        update_sync_timestamp(server.id, "full", result)
      end)
    end)

    schedule_full_sync()
    {:noreply, state}
  end

  @impl true
  def handle_info(:partial_sync, %{task_supervisor: supervisor} = state) do
    Task.Supervisor.async_nolink(supervisor, fn ->
      Servers.list_servers()
      |> Enum.each(fn server ->
        result = perform_sync(:partial_sync, server.id)
        update_sync_timestamp(server.id, "partial", result)
      end)
    end)

    schedule_partial_sync()
    {:noreply, state}
  end

  @impl true
  def handle_info({:DOWN, _ref, :process, _pid, _reason}, state) do
    {:noreply, state}
  end

  @spec perform_sync(atom(), server_id()) :: sync_result()
  defp perform_sync(sync_type, server_id) do
    with {:ok, server} <- get_server(server_id) do
      try do
        case sync_type do
          :partial_sync -> perform_partial_sync(server)
          :full_sync -> perform_full_sync(server)
          :sync_users -> JellyfinSync.sync_users(server)
          :sync_libraries -> JellyfinSync.sync_libraries(server)
          :sync_items -> JellyfinSync.sync_items(server)
          :sync_playback_stats -> JellyfinSync.sync_playback_stats(server)
        end

        Logger.info("#{sync_type} completed for server #{server.name}")
        {:ok, server}
      rescue
        e ->
          Logger.error("Error during #{sync_type} for server #{server.name}: #{inspect(e)}")
          {:error, :sync_failed}
      end
    end
  end

  @spec get_server(server_id()) :: {:ok, Servers.Server.t()} | {:error, :not_found}
  defp get_server(server_id) do
    case Servers.get_server(server_id) do
      nil ->
        Logger.error("Server with ID #{server_id} not found")
        {:error, :not_found}

      server ->
        {:ok, server}
    end
  end

  @spec update_sync_timestamp(server_id(), sync_type(), sync_result()) :: :ok
  defp update_sync_timestamp(server_id, sync_type, {:ok, _}) do
    %SyncLog{}
    |> SyncLog.changeset(%{
      server_id: server_id,
      sync_type: sync_type,
      synced_at: NaiveDateTime.utc_now()
    })
    |> Repo.insert()

    :ok
  end

  defp update_sync_timestamp(_, _, _) do
    Logger.warning("Sync failed, not updating timestamp")
    :ok
  end

  defp schedule_full_sync do
    # Run every 24 hours
    Process.send_after(self(), :full_sync, 24 * 60 * 60 * 1000)
  end

  defp schedule_partial_sync do
    # Run every hour
    Process.send_after(self(), :partial_sync, 60 * 1000)
  end

  @spec perform_full_sync(Servers.Server.t()) :: :ok
  defp perform_full_sync(server) do
    JellyfinSync.sync_users(server)
    JellyfinSync.sync_libraries(server)
    JellyfinSync.sync_items(server)
    JellyfinSync.sync_playback_stats(server)
    :ok
  end

  @spec perform_partial_sync(Servers.Server.t()) :: :ok
  defp perform_partial_sync(server) do
    # JellyfinSync.sync_users(server)
    # JellyfinSync.sync_libraries(server)
    # JellyfinSync.sync_recent_items(server)
    JellyfinSync.sync_playback_stats(server)
    :ok
  end
end