defmodule DosProj3 do
 use GenServer

  # External API
  def start_link([input_name]) do
    GenServer.start_link(
      __MODULE__,
      %{:finger_table => [],
        :predecessor => [],
        :successor => [],
        :local_file => []},
      name: input_name
    )
  end

  # Genserver Implementation
  def init(initial_map) do
    {:ok, initial_map}
  end

  def handle_call(:gossip, _from, current_map) do
    {_, updated_map} = Map.get_and_update(current_map, :current_gossip_count, fn x -> {x, x - 1} end)
    {:reply, current_map, updated_map}
  end

  def handle_cast(:gossip, current_map) do
    {_, updated_map} = Map.get_and_update(current_map, :current_gossip_count, fn x -> {x, x - 1} end)
    IO.puts current_map.current_gossip_count
    {:noreply, updated_map}
  end
end
