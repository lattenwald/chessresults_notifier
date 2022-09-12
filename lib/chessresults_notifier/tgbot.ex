defmodule ChessresultsNotifier.Tgbot do
  use GenServer
  require Logger

  def start_link(_) do
    Logger.info("starting")
    GenServer.start_link(
      __MODULE__,
      nil,
      name: __MODULE__
    )
  end

  @impl true
  def init(_) do
    send(self(), :init)
    {:ok, nil}
  end

  @impl true
  def handle_info(:init, nil) do
    Logger.info("starting get_updates() polling")
    {:ok, %{username: username}} = Nadia.get_me()
    poller = spawn_link(__MODULE__, :starter, [username])
    {:noreply, %{poller: poller, username: username}}
  end

  def starter(username, offset \\ 0) do
    case Nadia.get_updates(offset: offset) do
      {:ok, updates} ->
        next_offset =
          case List.last(updates) do
            nil -> offset
            upd -> upd.update_id + 1
          end

        for upd <- updates, do: process(upd, username)
        starter(username, next_offset)

      other ->
        Logger.warn("poller got #{inspect(other)}")
        starter(username, offset)
    end
  end

  defp process(upd = %{message: message = %{text: text}}, username) when text != nil do
    text = Regex.replace ~r/^(\/[^\s]+)@#{username}\b/i, text, "\\1"
    upd = %{upd | message: %{message | text: text}}
    process upd
  end
  defp process(upd, _), do: process upd

  defp process(%{message: %{text: "/id", chat: %{id: chat_id}, message_id: message_id}}) do
    Nadia.send_message(chat_id, "chat id: `#{chat_id}`", parse_mode: "Markdown", reply_to_message_id: message_id, reply_markup: %Nadia.Model.ReplyKeyboardRemove{})
  end

  defp process(%{message: %{text: url = "https://chess-results.com/" <> _, chat: %{id: chat_id}, message_id: message_id}}) do
    ChessresultsNotifier.Monitor.monitor chat_id, message_id, url
  end

  defp process(%{message: %{text: url = "https://chessresults.ru/ru/" <> _, chat: %{id: chat_id}, message_id: message_id}}) do
    ChessresultsNotifier.Monitor.monitor chat_id, message_id, url
  end

  defp process(%{message: %{text: "/list", chat: %{id: chat_id}, message_id: message_id}}) do
    monitored = ChessresultsNotifier.Monitor.list(chat_id)
    reply_markup = case monitored do
      [] -> %Nadia.Model.ReplyKeyboardRemove{}
      _ ->
        buttons = monitored
                  |> Enum.map(fn {id, _} -> %Nadia.Model.KeyboardButton{text: "/stop #{id}"} end)
                  |> split_by(3)
                  |> IO.inspect
        %Nadia.Model.ReplyKeyboardMarkup{keyboard: buttons, resize_keyboard: true}
    end
    msg = case Enum.count(monitored) do
      0 -> "Ничего не мониторится"
      _ ->
        monitored
        |> Enum.map(
          fn {_, %{url: url, last_round: nil, title: title}} ->
            "[#{title}](#{url})";
            {id, %{url: url, last_round: last_round, title: title, last_round_link: link}} ->
              "`#{id}`: [#{title}](#{url}) [#{last_round}](#{link})"
          end)
          |> Enum.join("\n")
    end
    Nadia.send_message(chat_id, msg, parse_mode: "Markdown", reply_to_message_id: message_id, disable_web_page_preview: true, reply_markup: reply_markup)
  end

  defp process(%{message: %{text: "/stop", chat: %{id: chat_id}, message_id: message_id}}) do
    :ok = ChessresultsNotifier.Monitor.unmonitor_all(chat_id)
    Nadia.send_message(chat_id, "ок", reply_to_message_id: message_id, reply_markup: %Nadia.Model.ReplyKeyboardRemove{})
  end

  defp process(%{message: %{text: "/stop " <> tourney_id, chat: %{id: chat_id}, message_id: message_id}}) do
    :ok = ChessresultsNotifier.Monitor.unmonitor(chat_id, tourney_id)
    Nadia.send_message(chat_id, "ок", reply_to_message_id: message_id, reply_markup: %Nadia.Model.ReplyKeyboardRemove{})
  end


  defp process(upd) do
    IO.inspect(upd)
  end

  def split_by(list, num), do: split_by(list, num, {[], []})

  defp split_by([], _, {[], acc}), do: Enum.reverse acc
  defp split_by([], _, {acc_hd, acc}), do: Enum.reverse [Enum.reverse(acc_hd) | acc]
  defp split_by([head | rest], num, {acc_hd, acc}) do
    if length(acc_hd) == num do
      split_by(rest, num, {[head], [Enum.reverse(acc_hd) | acc]})
    else
      split_by(rest, num, {[head | acc_hd], acc})
    end
  end

end
