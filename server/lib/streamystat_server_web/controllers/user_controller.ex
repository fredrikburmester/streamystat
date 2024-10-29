defmodule StreamystatServerWeb.UserController do
  use StreamystatServerWeb, :controller
  require Logger
  alias StreamystatServer.Contexts.Users

  def index(conn, %{"server_id" => server_id}) do
    users = Users.get_users(server_id)

    users_with_details =
      Enum.map(users, fn user ->
        watch_stats = Users.get_user_watch_stats(server_id, user.id)
        Logger.debug("User ID: #{user.id}, Watch Stats: #{inspect(watch_stats)}")
        %{user: user, watch_stats: watch_stats}
      end)

    render(conn, :index, users: users_with_details)
  end

  def show(conn, %{"server_id" => server_id, "id" => user_id}) do
    case Users.get_user(server_id, user_id) do
      nil ->
        conn
        |> put_status(:not_found)
        |> put_view(StreamystatServerWeb.ErrorJSON)
        |> render(:"404")

      user ->
        watch_history = Users.get_user_watch_history(server_id, user.id)
        watch_stats = Users.get_user_watch_stats(server_id, user.id)
        watch_time_per_day = Users.get_user_watch_time_per_day(server_id, user.id)

        render(conn, :show,
          user: user,
          watch_history: watch_history,
          watch_stats: watch_stats,
          watch_time_per_day: watch_time_per_day
        )
    end
  end
end