defmodule ChessresultsNotifier.Monitor do
  use GenServer, restart: :transient, shutdown: 5_000
  require Logger

  @period 10_000

  defstruct chat_id: nil, message_id: nil, url: nil, last_round: nil, title: nil, last_round_link: nil

  def start_link({chat_id, url, message_id}) do
    Logger.info "starting for #{chat_id} with #{url}"
    GenServer.start_link(__MODULE__, {chat_id, url, message_id})
  end

  def info(pid) do
    GenServer.call pid, :info
  end

  def stop(pid) do
    GenServer.stop pid
  end

  @impl true
  def init({chat_id, url, message_id}) do
    Nadia.send_message(chat_id, "monitoring", reply_to_message_id: message_id)
    {:ok, _} = :timer.send_interval @period, :check
    send(self(), :check)
    {:ok, %__MODULE__{chat_id: chat_id, message_id: message_id, url: url}}
  end

  @impl true
  def handle_info(:check, state = %{chat_id: chat_id, message_id: message_id, url: url, last_round: last_round}) do
    case ChessresultsNotifier.fetch url do
      {:ok, title, ^last_round, _link} ->
        Logger.debug "no new round detected at #{url}"
        {:noreply, %{state | title: title}}
      {:ok, title, new_last_round, link} ->
        Logger.debug "new round #{new_last_round} #{link} detected at #{url}"
        msg = "[#{title}](#{url})\n[#{new_last_round}](#{link})"
        case Regex.match? ~r/(?:Тур|Rd\.)(\d+)\/\1$/, new_last_round do
          true ->
            Nadia.send_message chat_id, "#{msg}\nlast round, monitoring stopped", parse_mode: "Markdown", reply_to_message_id: message_id, disable_web_page_preview: true
            {:stop, :normal, state}
          false ->
            Nadia.send_message chat_id, msg, parse_mode: "Markdown", reply_to_message_id: message_id, disable_web_page_preview: true
            {:noreply, %{state | last_round: new_last_round, title: title, last_round_link: link}}
        end
      {:error, %{reason: :nxdomain}} ->
        Nadia.send_message chat_id, "Wrong link", reply_to_message_id: message_id
        {:stop, :normal, state}
      {:error, other} ->
        Nadia.send_message chat_id, "Error `#{inspect other}`", parse_mode: "Markdown", reply_to_message_id: message_id
        {:stop, :normal, state}
    end
  end

  @impl true
  def handle_call(:info, _from, state) do
    {:reply, state, state}
  end
end
