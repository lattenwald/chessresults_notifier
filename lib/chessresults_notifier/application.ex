defmodule ChessresultsNotifier.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    storage = Application.fetch_env! :chessresults_notifier, :storage
    children = [
      {ChessresultsNotifier.Tgbot, []},
      {ChessresultsNotifier.Monitor, storage}
    ]

    Supervisor.start_link(children, strategy: :one_for_one)
  end
end
