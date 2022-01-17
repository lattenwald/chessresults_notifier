defmodule ChessresultsNotifier.Monitor do
  defmodule Tourney do
    defstruct notify: nil, title: nil, url: nil, last_round: nil, last_round_link: nil
  end
  use GenServer, restart: :transient, shutdown: 5_000
  require Logger

  @period 10_000

  defstruct storage: nil, tourneys: %{}

  def start_link(storage) do
    Logger.info "starting with #{storage}"
    GenServer.start_link(__MODULE__, storage, name: __MODULE__)
  end

  def monitor(chat_id, message_id, url) do
    case Regex.run ~r/\/(tnr\d+)\.aspx/, url, capture: :all_but_first do
      nil -> notify(chat_id, message_id, "Invalind link")
      [id] -> GenServer.cast __MODULE__, {:monitor, id, chat_id, message_id, url}
    end
  end

  def info() do
    GenServer.call __MODULE__, :info
  end

  def list(chat_id) do
    GenServer.call __MODULE__, {:list, chat_id}
  end

  defp load(storage) do
    Logger.info "loading tourneys from #{storage}"
    with {:ok, contents} <- File.read(storage),
         tourneys <- :erlang.binary_to_term(contents) do
      {:ok, tourneys}
    else
      {:error, :enoent} -> {:ok, %{}}
      error = {:error, _} -> error
      error -> {:error, error}
    end
  end

  defp store(tourneys, storage) do
    Logger.info "storing #{Enum.count tourneys} tourneys to #{storage}"
    :ok = File.write(storage, :erlang.term_to_binary(tourneys))
  end

  defp notify({chat_id, message_id}, msg), do: notify(chat_id, message_id, msg)

  defp notify(chat_id, message_id, msg) do
    Nadia.send_message chat_id, msg, parse_mode: "Markdown", reply_to_message_id: message_id, disable_web_page_preview: true
  end

  @impl true
  def init(storage) do
    :timer.send_interval @period, :check
    case File.exists?(storage) do
      false -> {:ok, %__MODULE__{storage: storage}}
      true ->
        with {:ok, tourneys} <- load(storage) do
          Logger.info "loaded #{inspect tourneys} from #{storage}"
          send self(), :check
          {:ok, %__MODULE__{storage: storage, tourneys: tourneys}}
        else
          {:error, other} ->
            Logger.error other
            {:stop, other}
          other ->
            Logger.error other
            {:stop, other}
        end
    end
  end

  @impl true
  def handle_info(:check, state = %{tourneys: tourneys, storage: storage}) do
    new_tourneys =
      tourneys
      |> Enum.map(fn {id, tourney = %{notify: notify, url: url, last_round: last_round}} ->
        case Enum.count(notify) do
          0 ->
            Logger.debug "no observers for tourney #{id}, removing"
            {id, nil};
          _ ->
            case ChessresultsNotifier.fetch url do
              {:ok, %{title: title, round: ^last_round}} ->
                Logger.debug "no new round detected for #{id}"
                {id, %{tourney | title: title}}
              {:ok, %{title: title, round: new_last_round, round_link: link, board: board, color: color}} ->
                Logger.debug "new round #{new_last_round} #{link} detected for #{id}"
                msg = "[#{title}](#{url})\n[#{new_last_round}](#{link})"
                msg = case board do
                  nil -> msg
                  _ -> msg <> ", playing board *#{board}* with *#{color}*"
                end

                {msg, new_tourney} =
                  case Regex.match? ~r/(?:Тур|Rd\.)(\d+)\/\1$/, new_last_round do
                    true -> {"#{msg}\nlast round, monitoring stopped", nil}
                    false ->
                      {msg, %{tourney | title: title, last_round: new_last_round, last_round_link: link}}
                  end
                notify |> Enum.each(&notify(&1, msg))
                {id, new_tourney}
              {:error, %{notify: notify, reason: :nxdomain}} ->
                notify |> Enum.each(&notify(&1, "Wrong link"))
                {id, nil}
              {:error, other} ->
                notify |> Enum.each(&notify(&1, "Error `#{inspect other}`"))
                {id, nil}
            end
        end
      end
      )
      |> Enum.filter(fn {_, nil} -> false; _ -> true end)
      |> Enum.into(%{})

    if new_tourneys != tourneys, do: store(new_tourneys, storage)

    {:noreply, %{state | tourneys: new_tourneys}}
  end

  @impl true
  def handle_call(:info, _from, state) do
    {:reply, state, state}
  end

  def handle_call({:list, chat_id}, _from, state = %{tourneys: tourneys}) do
    list = tourneys
           |> Enum.filter(
             fn {_, %{notify: notify}} ->
               notify
               |> Enum.any?(
                 fn
                   {^chat_id, _} -> true;
                   _ -> false
                 end)
             end
           )
    {:reply, list, state}
  end

  @impl true
  def handle_cast({:monitor, id, chat_id, message_id, url}, state = %{storage: storage, tourneys: tourneys}) do
    notify = {chat_id, message_id}
    tourney =
      case Map.fetch tourneys, id do
        {:ok, stored = %{notify: stored_notify}} ->
          case MapSet.member? stored_notify, notify do
            true -> notify(chat_id, message_id, "Tournament `#{id}` is already monitored")
            false -> notify(chat_id, message_id, "Monitoring tournament `#{id}`")
          end
          %{stored | notify: MapSet.put(stored_notify, {chat_id, message_id})}
        :error ->
          notify(chat_id, message_id, "Monitoring tournament `#{id}`")
          %Tourney{notify: MapSet.new([notify]), url: url}
      end
    new_tourneys = Map.put tourneys, id, tourney
    Logger.info "new tourneys: #{inspect new_tourneys}"
    store new_tourneys, storage
    send self(), :check
    {:noreply, %{state | tourneys: new_tourneys}}
  end
end
