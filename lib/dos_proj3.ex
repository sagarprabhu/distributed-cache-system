defmodule DosProj3 do
  use GenServer

  # External API
  def start_link([input_name]) do
    GenServer.start_link(
      __MODULE__,
      %{:finger_table => [], :predecessor => [], :successor => [], :local_file => []},
      name: input_name
    )
  end

  # Genserver Implementation
  def init(initial_map) do
    {:ok, initial_map}
  end

  def handle_call(:gossip, _from, current_map) do
    {_, updated_map} =
      Map.get_and_update(current_map, :current_gossip_count, fn x -> {x, x - 1} end)

    {:reply, current_map, updated_map}
  end

  def handle_cast(:gossip, current_map) do
    {_, updated_map} =
      Map.get_and_update(current_map, :current_gossip_count, fn x -> {x, x - 1} end)

    IO.puts(current_map.current_gossip_count)
    {:noreply, updated_map}
  end

  def handle_cast({:set_neighbours, list_neighbours}, current_map) do

    [ input_predecessor | input_successors ] = list_neighbours

    {_, updated_map} =
      Map.get_and_update(current_map, :predecessor, fn x -> {x, x ++ input_predecessor} end)
  
    {_, updated_map} =
    Map.get_and_update(updated_map, :successor, fn x -> {x, x ++ input_successors} end)

    {:noreply, updated_map}
  end

  def handle_cast({:set_finger_table, finger_table}, current_map) do

    {_, updated_map} =
      Map.get_and_update(current_map, :finger_table, fn x -> {x, x ++ finger_table} end)
  
    {:noreply, updated_map}
  end

  def handle_cast({:store_file, file_name}, current_map) do
    {_, updated_map} =
      Map.get_and_update(current_map, :local_file, fn x -> {x, x ++ file_name} end)
    
    GenServer.cast(updated_map.predecessor |> Integer.to_string |> String.to_atom,
                          {:store_file_as_backup, file_name})
    
    GenServer.cast(List.first(updated_map.successor) |> Integer.to_string |> String.to_atom,
                          {:store_file_as_backup, file_name})
    
    {:noreply, updated_map}
  end

  def handle_cast({:store_file_as_backup, file_name}, current_map) do
    {_, updated_map} =
      Map.get_and_update(current_map, :local_file, fn x -> {x, x ++ file_name} end)
    
    {:noreply, updated_map}
  end

  def handle_cast({:print_state}, current_map) do
    IO.inspect current_map
    {:noreply, current_map}
  end
end
