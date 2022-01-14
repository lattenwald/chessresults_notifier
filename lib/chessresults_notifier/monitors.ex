defmodule ChessresultsNotifier.Monitors do
  use DynamicSupervisor
  require Logger

  def start_link(_) do
    DynamicSupervisor.start_link(__MODULE__, nil, name: __MODULE__)
  end

  @impl true
  def init(nil) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  def monitor(chat_id, url, message_id) do
    case list() |> Enum.any?(fn {_, %{url: ^url}} -> true; _ -> false end) do
      true ->
        Nadia.send_message(chat_id, "already monitored", reply_to_message_id: message_id)
      false ->
        spec = {ChessresultsNotifier.Monitor, {chat_id, url, message_id}}
        DynamicSupervisor.start_child(__MODULE__, spec)
    end
  end

  def list do
    DynamicSupervisor.which_children(__MODULE__)
    |> Enum.filter(fn {_, _, :worker, [ChessresultsNotifier.Monitor]} -> true; _ -> false end)
    |> Enum.map(fn {_, pid, _, _} -> {pid, ChessresultsNotifier.Monitor.info(pid)} end)
  end
end
